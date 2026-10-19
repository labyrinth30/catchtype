#if os(macOS)
import Cocoa
import ApplicationServices
import Carbon
import CatchTypeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var config = CTConfigStore.load()
    lazy var corrector = EventStreamCorrector(config: .init(
        initialLang: CTLang(rawValue: config.initialLang) ?? .en,
        wordTimeoutMs: config.wordTimeoutMs.isFinite && config.wordTimeoutMs > 0 ? config.wordTimeoutMs : 1200))
    var eventTap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var idleTimer: Timer?
    var permissionTimer: Timer?
    var frontAppBundleID: String?
    private var contextPID: pid_t?
    private var contextSource: String?
    private var contextElement: AXUIElement?
    private var swallowedKeyUps: Set<Int64> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        frontAppChanged(Notification(name: NSWorkspace.didActivateApplicationNotification))
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if CTAccessibility.requestWithPrompt(showAlert: true) { installEventTap() }
        else { setStatusWaitingForPermission(); schedulePermissionPolling() }
        idleTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.handleIdleTimeout()
        }
        RunLoop.main.add(idleTimer!, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        idleTimer?.invalidate()
        permissionTimer?.invalidate()
    }

    @objc func frontAppChanged(_ note: Notification) {
        frontAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        corrector.handlePossibleInterruption()
        contextPID = nil
        contextElement = nil
        refreshMenu()
    }

    /// Validate the actual focus and input source before each physical keystroke.
    private func canCorrect(now: Double) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            corrector.setSuppressed(true)
            return false
        }
        frontAppBundleID = app.bundleIdentifier
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID).map {
            Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
        } ?? ""
        if contextPID != app.processIdentifier || contextSource != sourceID {
            corrector.handlePossibleInterruption()
            contextPID = app.processIdentifier
            contextSource = sourceID
        }
        // shortcut: IME composition is passed through; add composition-aware deletion before supporting Korean input sources.
        guard let bid = app.bundleIdentifier, CTConfigStore.isTargeted(config, bundleID: bid),
              sourceID.hasPrefix("com.apple.keylayout."), !IsSecureEventInputEnabled(), AXIsProcessTrusted() else {
            corrector.setSuppressed(true)
            return false
        }
        if config.passwordGuard || config.terminalPromptGuard {
            guard let focus = CTPasswordGuard.focusedControl() else {
                corrector.setSuppressed(true)
                return false
            }
            if let previous = contextElement, !CFEqual(previous, focus.element) {
                corrector.handlePossibleInterruption()
            }
            contextElement = focus.element
            if config.passwordGuard && CTPasswordGuard.isSecure(role: focus.role, subrole: focus.subrole,
                description: focus.description, title: focus.title) {
                corrector.setSuppressed(true)
                return false
            }
            if config.terminalPromptGuard {
                guard let line = CTPasswordGuard.terminalLine(focus) else {
                    corrector.setSuppressed(true)
                    return false
                }
                corrector.notePasswordPrompt(line: line, nowMs: now)
            }
        }
        corrector.setSuppressed(false)
        return true
    }

    func handleIdleTimeout() {
        corrector.expirePending(nowMs: nowMs())
    }

    func installEventTap() {
        guard eventTap == nil else { return }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                .onEvent(proxy: proxy, type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            setStatusWaitingForPermission()
            schedulePermissionPolling()
            return
        }
        eventTap = tap
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        setStatusActive()
    }

    func schedulePermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if AXIsProcessTrusted() {
                self.installEventTap()
                if self.eventTap != nil {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    func onEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == CTEventSender.marker {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            corrector.handlePossibleInterruption()
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if swallowedKeyUps.remove(code) != nil { return nil }
            return Unmanaged.passUnretained(event)
        }
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]
        if type != .keyDown || !event.flags.intersection(modifiers).isEmpty {
            if type != .flagsChanged || !event.flags.intersection(modifiers).isEmpty {
                corrector.handlePossibleInterruption()
            }
            return Unmanaged.passUnretained(event)
        }
        let now = nowMs()
        guard canCorrect(now: now) else { return Unmanaged.passUnretained(event) }
        guard let keyCode = UInt16(exactly: code) else {
            corrector.handlePossibleInterruption()
            return Unmanaged.passUnretained(event)
        }
        let tail = ["Space", "Enter", "Tab"].first { CT_KVK_ANSI[$0] == keyCode }
        let correction: CTCorrection?
        if let tail = tail {
            correction = corrector.handleKey(CTKey(code: tail, shift: event.flags.contains(.maskShift)), timestampMs: now)
        } else {
            var chars = [UniChar](repeating: 0, count: 16)
            var length = 0
            event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
            let text = String(utf16CodeUnits: chars, count: min(length, chars.count))
            if text.isEmpty || [UInt16(0x33), 0x35, 0x7b, 0x7c, 0x7d, 0x7e, 0x73, 0x77, 0x74, 0x79, 0x75].contains(keyCode) {
                corrector.handlePossibleInterruption()
                return Unmanaged.passUnretained(event)
            }
            correction = corrector.handleText(text, timestampMs: now)
        }
        refreshMenu()
        guard let correction = correction, CTEventSender.send(correction, proxy: proxy) else {
            return Unmanaged.passUnretained(event)
        }
        swallowedKeyUps.insert(code)
        return nil
    }

    private func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    // MARK: - 상태바

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⌨" // 활성 상태 — refreshMenu에서 갱신
            button.action = #selector(statusClicked(_:))
            button.target = self
        }
    }

    @objc func statusClicked(_ sender: Any?) {
        // 좌클릭도 메뉴를 연다(간단 UX).
    }

    func refreshMenu() {
        let menu = NSMenu()

        // 상태 요약
        let targeted = frontAppBundleID.map { CTConfigStore.isTargeted(config, bundleID: $0) } ?? false
        let langLabel: String
        switch corrector.sessionLang {
        case .ko: langLabel = "한국어"
        case .en: langLabel = "영어"
        }
        let summary = NSMenuItem(title: "최근 판정 언어: \(langLabel)", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)

        let targetItem = NSMenuItem(title: targeted ? "현재 앱: 교정 ON" : "현재 앱: 교정 OFF",
                                    action: nil, keyEquivalent: "")
        targetItem.isEnabled = false
        menu.addItem(targetItem)
        menu.addItem(.separator())

        // 대상 앱 토글
        let header = NSMenuItem(title: "대상 앱", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for app in config.apps {
            let item = NSMenuItem(title: "\(app.enabled ? "✓" : "  ") \(app.name)",
                                  action: #selector(toggleApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleID
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // 비밀번호 방어
        let pwItem = NSMenuItem(title: "\(config.passwordGuard ? "✓" : "  ") 비밀번호 필드 방어 (AX)",
                                action: #selector(togglePasswordGuard(_:)), keyEquivalent: "")
        pwItem.target = self
        menu.addItem(pwItem)

        let promptItem = NSMenuItem(title: "\(config.terminalPromptGuard ? "✓" : "  ") 터미널 프롬프트 방어",
                                    action: #selector(togglePromptGuard(_:)), keyEquivalent: "")
        promptItem.target = self
        menu.addItem(promptItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Catchtype 종료", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc func toggleApp(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        if let idx = config.apps.firstIndex(where: { $0.bundleID == bid }) {
            config.apps[idx].enabled.toggle()
            CTConfigStore.save(config)
            if bid == frontAppBundleID {
                corrector.setSuppressed(!config.apps[idx].enabled)
            }
            refreshMenu()
        }
    }

    @objc func togglePasswordGuard(_ sender: NSMenuItem) {
        config.passwordGuard.toggle()
        CTConfigStore.save(config)
        refreshMenu()
    }

    @objc func togglePromptGuard(_ sender: NSMenuItem) {
        config.terminalPromptGuard.toggle()
        CTConfigStore.save(config)
        refreshMenu()
    }

    @objc func quitApp(_ sender: NSMenuItem) {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        NSApp.terminate(nil)
    }

    func setStatusActive() {
        statusItem?.button?.title = "⌨"
        statusItem?.button?.toolTip = "Catchtype — 교정 활성"
    }

    func setStatusWaitingForPermission() {
        statusItem?.button?.title = "⚠"
        statusItem?.button?.toolTip = "Catchtype — 손쉬운 사용 권한 대기 중"
    }
}

#endif // os(macOS)
