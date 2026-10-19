#if os(macOS)
//
//  PermissionPrompt.swift
//  CatchType
//
//  접근성(Accessibility) 권한 확인 + 첫 실행 안내 얼럿.
//  권한이 없으면 AXIsProcessTrustedWithOptions가 시스템 환경설정으로 유도하고,
//  앱은 자체 안내 얼럿을 띄운 뒤 대기 모드(schedulePermissionPolling)로 진입한다.
//

import ApplicationServices
import AppKit

enum CTAccessibility {
    /// 접근성 권한이 이미 부여됐는지.
    static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /**
     * 권한 프롬프트 표시(시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용).
     * kAXTrustedCheckOptionPrompt = true로 시스템 얼럿을 유도하고,
     * non-trusted면 자체 안내 얼럿(다시 확인/나중에)을 띄운다.
     * 이후 재검사는 AppDelegate.schedulePermissionPolling이 매 2초 담당.
     */
    @discardableResult
    static func requestWithPrompt(showAlert: Bool) -> Bool {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showAlert] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted && showAlert {
            showWaitingAlert()
        }
        return trusted
    }

    private static func showWaitingAlert() {
        let alert = NSAlert()
        alert.messageText = "Catchtype — 손쉬운 사용 권한 필요"
        alert.informativeText = """
        키 입력을 감시·교정하려면 시스템 환경설정에서 손쉬운 사용 권한을 켜야 합니다.

        1. 시스템 설정 열기 (자동으로 열림)
        2. 개인정보 보호 및 보안 → 손쉬운 사용
        3. 목록에 Catchtype 추가(없으면 + 버튼으로 선택) & 토글 ON
        4. 이 창의 "다시 확인"을 눌러 재검사

        권한이 없어도 앱은 실행되지만 키 입력을 보지 못합니다(메뉴막대에 "권한 대기" 표시).
        """
        alert.addButton(withTitle: "다시 확인")
        alert.addButton(withTitle: "나중에")
        alert.alertStyle = .informational
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        _ = alert.runModal()
    }
}

#endif
