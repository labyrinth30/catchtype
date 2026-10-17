#if os(macOS)
//
//  PasswordGuard.swift
//  CatchType
//
//  이중 비밀번호 방어 (SPEC.md):
//   (a) AXUIElement 계층 확인 — 포커스 요소가 secure text field인지 검사 (원작 방식, 개념 참고)
//   (b) 프롬프트 휴리스틱 — 터미널 라인 "password:", "PIN:" 감지 시 일시 중지
//   (+) 엔진의 passwordSuspect 플래그 — 3종 혼용 토큰은 판정 자체를 건너뜀 (Engine 내장)
//
//  AX 규약: AXUIElement는 CF 타입(Unmanaged) — Swift에서 takeRetainedValue/takeUnretainedValue는
//  쓰지 않고 오버로드된 세 함수(AxisWide/focusedElement/StringAttribute)에 캐스팅을 몰아넣는다
//  (무료 브리지된 CF 타입은 `as?`로 직접 Swift 타입으로 내려온다).
//

import ApplicationServices
import AppKit
import CatchTypeCore

enum CTPasswordGuard {
    /// (a) 포커스된 AX 요소가 비밀번호 입력 필드인지 조회. 타임아웃은 AX 호출 자체에 기본 6초 — 시스템 정책.
    static func isSecureTextFieldFocused() -> Bool {
        let systemEl = AXUIElementCreateSystemWide()
        guard let app = focusedApp(systemEl) else { return false }

        // 1) focused UI element — role이 AXSecureTextField인지 직접 검사.
        if let el = focusedElement(app), attrString(el, kAXRoleAttribute) == "AXSecureTextField" {
            return true
        }
        // 2) 원작 방식: title/description에 'password/비밀번호'가 있으면 의심 (오탐 허용).
        if let el = focusedElement(app) {
            let d = attrString(el, kAXDescriptionAttribute) ?? ""
            let t = attrString(el, kAXTitleAttribute) ?? ""
            let low = (d + " " + t).lowercased()
            if low.contains("password") || low.contains("비밀번호") || low.contains("패스워드") {
                return true
            }
        }
        return false
    }

    /// CFTypeRef에서 Swift 값으로 안전 추출.
    private static func copyAttr(_ el: AXUIElement, _ attr: CFString) -> CFTypeRef? {
        var value: CFTypeRef? = nil
        let err = AXUIElementCopyAttributeValue(el, attr, &value)
        guard err == .success else { return nil }
        return value
    }

    private static func attrString(_ el: AXUIElement, _ attr: CFString) -> String? {
        copyAttr(el, attr) as? String
    }

    private static func focusedApp(_ systemEl: AXUIElement) -> AXUIElement? {
        guard let v = copyAttr(systemEl, kAXFocusedApplicationAttribute) else { return nil }
        // kAXFocusedApplicationAttribute의 값은 AXUIElement (CF 타입, 무료 브리지).
        let r = unsafeBitCast(v, to: AXUIElement.self)
        return r
    }

    private static func focusedElement(_ app: AXUIElement) -> AXUIElement? {
        guard let v = copyAttr(app, kAXFocusedUIElementAttribute) else { return nil }
        let r = unsafeBitCast(v, to: AXUIElement.self)
        return r
    }

    /// (b) 터미널 프롬프트 휴리스틱: 최근에 읽은 화면 라인들에서 password/PIN 패턴 검사.
    static func terminalPromptLooksLikePassword(_ line: String) -> Bool {
        // sudo/ssh/su 프롬프트에서 password: 라인이 들어올 때.
        return line.range(of: #"(?i)^\s*\[?(sudo|ssh|su)\]?.*(password|pass phrase)"#,
                          options: .regularExpression) != nil
            || line.range(of: #"(?i)^[^\s@]+@[^\s]+.*(password|암호|비밀번호)"#,
                          options: .regularExpression) != nil
            || line.range(of: #"(?i)^[Pp]assword\s*[:：]"#, options: .regularExpression) != nil
            || line.range(of: #"(?i)^\s*[Pp][Ii][Nn]\s*[:：]"#, options: .regularExpression) != nil
    }

    /// 세 가지 방어 모두 고려한 판정 우회 여부.
    static func shouldBypass(cfg: CTAppConfig, corrector: EventStreamCorrector) -> Bool {
        guard cfg.passwordGuard || cfg.terminalPromptGuard else { return false }
        if cfg.passwordGuard && isSecureTextFieldFocused() { return true }
        return corrector.shouldSuppressCorrection() // (b) 프롬프트 hold + 엔진 passwordSuspect
    }
}

#endif // os(macOS)
