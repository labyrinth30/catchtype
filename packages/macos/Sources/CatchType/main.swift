// CatchType — macOS 상태바 앱 entry point (top-level code는 main.swift만 가능).
#if os(macOS)
import Cocoa
import CatchTypeCore

// CGEventTap 백그라운드 상주 앱은 Xcode 프로젝트 없이 CLI 실행으로도 구동된다.
// NSApplication 수동 부트 — 스토리보드/Info.plist 불필요.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
