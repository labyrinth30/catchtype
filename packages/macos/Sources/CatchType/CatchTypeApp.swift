#if os(macOS)
//
//  CatchTypeApp.swift
//  CatchType
//
//  CGEventTap 기반 백그라운드 상태바(status-item) 앱 — main entry.
//
//  구조:
//   1. 접근성 권한 검사/프롬프트 (PermissionPrompt)
//   2. CGEventTap 설치(kCGEventKeyDown 감시, default 수정 권한) + 런루프 소스 등록
//   3. 키스트림 → EventStreamCorrector(엔진 임베드 판정) → 재전송(backspace+교정문)
//   4. 상태바 메뉴: 대상 앱 토글, 세션 언어 표시, 비밀번호 방어 토글, 종료
//   5. AX 비밀번호 필드 감시(이중 방어 a) + 터미널 프롬프트 휴리스틱(이중 방어 b)
//

import Cocoa
import ApplicationServices
import CatchTypeCore

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let config = CTConfigStore.load()
    lazy var corrector = EventStreamCorrector()
    var eventTap: CFMachPort? = nil
    var tapSource: CFRunLoopSource? = nil
    var idleTimer: Timer? = nil
    var frontAppBundleID: String? = nil
    var debugLog = false   // set from config

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 백그라운드 상주 앱 — Dock 아이콘 없음
        NSApp.setActivationPolicy(.accessory)

        // 0) 접근성 권한 — 없으면 프롬프트 + 대기 모드로 진입(권한 생기면 tap 재시도)
        let granted = CTAccessibility.requestWithPrompt(showAlert: true)
        setupStatusBar()
        refreshMenu()

        if granted {
            installEventTap()
        } else {
            setStatusWaitingForPermission()
            schedulePermissionPolling()
        }

        // idle 타이머 — 런 진행 중 입력이 멈추면 확정(교정 필요 시 post)
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.handleIdleCommit()
        }
        RunLoop.main.add(idleTimer!, forMode: .common)

        // 포어그라운드 앱 추적 — 앱 전환 시 런 flush + 타겟 갱신
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventTap = eventTap {
            CGEventTapEnable(eventTap, false)
            if let src = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
            CFMachPortInvalidate(eventTap)
        }
        idleTimer?.invalidate()
    }

    // MARK: 포어그라운드 앱 추적

    /// 런루프 타이머가 부르는 확정 종점: timeout 런을 CGEvent post로 교정.
    func handleIdleCommit() {
        guard let commit = corrector.handleIdleCommit(nowMs: Date().timeIntervalSince1970 * 1000),
              commit.backspaceCount > 0, !commit.replacement.isEmpty else { return }
        var events: [CTKey] = []
        for _ in 0..<commit.backspaceCount { events.append(CTKey(code: "Backspace", shift: false)) }
        for ch in commit.replacement {
            if ch == "\n" { events.append(CTKey(code: "Enter", shift: false)) }
            else if ch == " " { events.append(CTKey(code: "Space", shift: false)) }
            else if let k = ctCharToKey(ch) { events.append(k) }
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        postCorrectionSequence(events, via: source)
    }

    @objc func frontAppChanged(_ note: Notification) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier else { return }
        frontAppBundleID = bid
        corrector.handlePossibleInterruption() // 앱 전환 = 런 확정
        let targeted = CTConfigStore.isTargeted(config, bundleID: bid)
        corrector.setSuppressed(!targeted)
        refreshMenu()
    }

    // MARK: - CGEventTap

    func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            return delegate.onEvent(type: type, event: event)
        }
        guard let tap = CGEventTapCreate(
            .cgSessionTap,                 // 세션 탭 — 사용자 세션 동안
            .headInsertEventTap,           // 다른 tap보다 먼저
            .defaultTap,                   // 이벤트 수정 허용
            mask,
            callback,
            Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[catchtype] CGEventTapCreate failed — 권한을 확인하세요")
            setStatusWaitingForPermission()
            schedulePermissionPolling()
            return
        }
        self.eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.tapSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEventTapEnable(tap, true)
        setStatusActive()
    }

    func schedulePermissionPolling() {
        // 권한 대기 모드: 2초마다 재검사 — 통과되면 tap 설치
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if AXIsProcessTrusted() {
                t.invalidate()
                self.installEventTap()
                self.refreshMenu()
            }
        }
    }

    // MARK: 키 이벤트 처리 (CGEventTap 콜백, 메인 런루프)

    /// 콜백 반환은 유지할(Unswizzle 된) 이벤트 — nil이면 이벤트가 소멸(삭제).
    func onEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS가 tap을 비활성화했으면 재활성 (안전장치)
            if let tap = eventTap { CGEventTapEnable(tap, true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // 타겟 앱이 아니면 그대로 통과
        guard let bid = frontAppBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              CTConfigStore.isTargeted(config, bundleID: bid) else {
            corrector.flushPending(sendCorrection: false)
            return Unmanaged.passUnretained(event)
        }

        // 이중 방어 (a): AX 비밀번호 필드 — 비용 문제로 런 첫 글쇠에서만 검사
        if config.passwordGuard && corrector.pendingKeys.isEmpty {
            let secure = CTPasswordGuard.isSecureTextFieldFocused()
            corrector.setSuppressed(secure)  // 이후 글쇠에서도 우회
            if secure { return Unmanaged.passUnretained(event) }
        }

        // CGEvent → CTKey (KVK keycode + shift 플래그)
        let keyCode = event.getIntegerIntegerField(.keyboardEventKeycode)
        let shift = event.flags.contains(.maskShift)
        guard let key = ctKeyFromKeyCode(UInt16(keyCode), shift: shift) else {
            // 매핑 없는 글쇠(F키, 방향키, 모디파이어 조합 등) — 런을 확정하고 통과.
            // 교정이 필요하면 그 결과는 포스트로 보내고, 원본은 그대로 흐른다.
            postCorrectionFromNonAlpha(corrector, timestampMs: nowMs())
            return Unmanaged.passUnretained(event)
        }

        // 런 진행 처리 + 재전송 필요 여부
        let replacementKeys = corrector.handleKey(key, timestampMs: nowMs())
        if replacementKeys.isEmpty {
            return Unmanaged.passUnretained(event) // 원본 통과 (런 진행 중)
        }
        if replacementKeys.count == 1 && replacementKeys[0] == key {
            return Unmanaged.passUnretained(event) // 우회 모드 — 원본 통과
        }

        // 교정: (1) backspace N회 (2) 교정 문자열 전송 + 런 종료 글쇠(Space/Enter)
        return postReplacementEvents(replacementKeys, originalEvent: event)
    }

    /// 매핑 없는 글쇠(F키, 방향키 등)가 들어왔을 때 런 확정 — 교정이 필요하면 post.
    /// CGEventTap 콜백 안에서 원본과 무관하게 시스템에 직접 보내는 경로.
    func postCorrectionFromNonAlpha(_ corrector: EventStreamCorrector, timestampMs: Double) {
        let events = corrector.handleNonAlphaEvent(timestampMs: timestampMs)
        guard !events.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        postCorrectionSequence(events, via: source)
    }

    /// CTKey 시퀀스를 down/up 쌍 CGEvent로 시스템에 전송.
    private func postCorrectionSequence(_ keys: [CTKey], via source: CGEventSource?) {
        for k in keys {
            guard let keyCode = ctKeyCode(k) else { continue }
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            down?.flags = akFlags(k)
            down?.post(tap: .cgHeadInsertEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            up?.flags = akFlags(k)
            up?.post(tap: .cgHeadInsertEventTap)
        }
    }

    /// 교정 이벤트를 시스템에 흘려보낸다.
    /// CGEventTap 콜백 규약: 원본을 없애려면 NULL을 돌려야 하지만 Swift 시그니처는
    /// Unmanaged<CGEvent>를 요구한다. 우리의 전략:
    ///  1) 원본 keydown의 keycode/flags를 교정문 첫 글쇠로 '변조' — 원본이 그대로
    ///     시스템으로 흐르되 내용만 교정 첫 글쇠가 된다(콜백 반환으로 자연 전달).
    ///  2) 나머지 글쇠는 새 down/up 쌍 CGEvent를 post.
    ///  3) 변조된 keycode와 짝이 맞는 keyup을 미리 post — 원본 keyup(keycode 불일치)에
    ///     대한 정리. 원본 자체의 keyup도 추가로 들어오지만 중복 up은 터미널에서 무해.
    func postReplacementEvents(_ keys: [CTKey], originalEvent: CGEvent) -> Unmanaged<CGEvent> {
        let source = CGEventSource(stateID: .combinedSessionState)

        // 1) 원본 keydown 변조 — 교정문 첫 글쇠로
        if let first = keys.first, let kc = ctKeyCode(first) {
            originalEvent.setIntegerValueField(.keyboardEventKeycode, value: Int64(kc))
            originalEvent.flags = akFlags(first)
        }

        // 2) 나머지 글쇠 — down/up 쌍 post
        for k in keys.dropFirst() {
            guard let keyCode = ctKeyCode(k) else { continue }
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            down?.flags = akFlags(k)
            down?.post(tap: .cgHeadInsertEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            up?.flags = akFlags(k)
            up?.post(tap: .cgHeadInsertEventTap)
        }
        // 3) 변조 쌍의 up — 콜백이 흘려보낸 keydown에 대응 (중복 up 무해: repeat down만 문제)
        if let first = keys.first, let kc = ctKeyCode(first) {
            let up = CGEvent(keyboardEventSource: source, virtualKey: kc, keyDown: false)
            up?.flags = akFlags(first)
            up?.post(tap: .cgHeadInsertEventTap)
        }

        return Unmanaged.passUnretained(originalEvent)
    }

    private func akFlags(_ k: CTKey) -> CGEventFlags {
        k.shift ? CGEventFlags.maskShift : []
    }

    // MARK: keycode 변환 — KVK_ANSI 역방향

    /// CTKey → CGEvent 가상 keycode (Events.h kVK_ANSI). 매핑 없는 글쇠는 nil.
    func ctKeyCode(_ k: CTKey) -> UInt16? {
        CT_KVK_ANSI[k.code]
    }

    /// CGEvent keycode → CTKey (KVK_ANSI 역방향). 매핑 없는 키는 nil.
    func ctKeyFromKeyCode(_ code: UInt16, shift: Bool) -> CTKey? {
        if let entry = ktReverseKeycode.first(where: { $0.value == code }) {
            return CTKey(code: entry.key, shift: shift)
        }
        return nil
    }

    static let ktReverseKeycode: [String: UInt16] = {
        var m: [String: UInt16] = [:]
        for (k, v) in CT_KVK_ANSI { m[k] = v } // code → keycode (동일 방향)
        return m
    }()

    private func nowMs() -> Double {
        Date().timeIntervalSince1970 * 1000
    }

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
        let summary = NSMenuItem(title: "세션 언어: \(langLabel)", action: nil, keyEquivalent: "")
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
