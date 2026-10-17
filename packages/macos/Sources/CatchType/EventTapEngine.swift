#if os(macOS)
//
//  EventTapEngine.swift
//  CatchType
//
//  입력 스트림 상태 기계 — keystroke 런 수집 → 판정 → 재전송(rewrite) 결정.
//  타이핑 도중 prefix 근거로 "조용히 대기"하는 단계적 판정(SPEC.md open question 3)의
//  실 구현: 단어가 진행 중인 동안은 이벤트를 통과시키고, 단어가 끝나는 글쇠
//  (공백/개행/기호/비활성 간격)에서 확정 문자열을 한 번에 교정해 SEND한다.
//

import Foundation
import CatchTypeCore

/// 실시간 스트림 판정기 — 메인 스레드 배타. CGEventTap 콜백은 런루프 스레드에서 호출.
final class EventStreamCorrector {
    // MARK: 설정 주입
    struct Config {
        var initialLang: CTLang = .en
        /// 콜백이 교정을 검사하기 전 마지막 글쇠와 이번 글쇠 사이 최대 간격(ms).
        /// 초과하면 런을 강제 확정(사람이 멈춰있으면 문장 경계로 본다).
        var wordTimeoutMs: Double = 1200.0
        /// 교정 재전송 최대 문자 수 (이 이상이면 그냥 통과 — UI 충돌 회피).
        var maxRewriteLength: Int = 24
        /// 입력 소스 상태 자동 추적 (CGEventSourceStateID + 한영 토글 키 감시).
        var trackSourceLanguage: Bool = true
    }
    var config = Config()

    // MARK: 런타임 상태
    private(set) var sessionLang: CTLang = .en
    private var pendingKeys: [(key: CTKey, timestamp: Double)] = []
    /// pendingKeys에 대응하는 raw 문자열 (출력 재구성/되돌리기용) — 일관성 캐시.
    private var pendingRaw: String = ""
    /// 판정기 캐시 — 콜드 스타트 후 1회 빌드.
    private var dicts: CTDicts? = nil
    /// 마지막 이벤트 타임스탬프(ms) — word timeout 검사용.
    private var lastEventMs: Double = 0
    /// 디버그 로깅
    var debugLog: Bool = false

    // MARK: 차단기 (비밀번호·앱 보호)
    /// 현재 포어그라운드 앱이 보호 대상이면 true — 판정 규칙을 완전 우회하고 그대로 통과.
    private var suppressedAppActive = false
    /// 마지막에 감지한 비밀번호 프롬프트(터미널 라인) 시각 — 최근 N초 동안은 판정 중지.
    private var promptHoldUntil: Double = 0

    init() {
        self.dicts = ctLoadAugmentedBuiltinDicts()
        self.sessionLang = config.initialLang
    }

    // MARK: 보호 콜백 (AppDelegate가 세팅)
    func setSuppressed(_ suppressed: Bool) {
        if suppressed {
            // 상태 전환 시 런을 끊어 캐시된 pending을 버린다(위조 판정 방지).
            flushPending(sendCorrection: false)
        }
        suppressedAppActive = suppressed
    }

    func notePasswordPrompt(line: String) {
        // 터미널 프롬프트 휴리스틱: password:, PIN:, 패스워드 등 — 이후 holdMs 동안 무판정.
        guard line.range(of: #"([Pp]assword|[Pp]assphrase|PIN|[bp]i밀번호)\s*[:：]"#, options: .regularExpression) != nil
           || line.range(of: #"(?i)password\s*[:：]"#, options: .regularExpression) != nil
        else { return }
        let now = Date().timeIntervalSince1970 * 1000
        promptHoldUntil = now + 8000.0
        flushPending(sendCorrection: false)
        if debugLog { fputs("[ct] password prompt detected — 8s hold\n", stderr) }
    }

    func clearPasswordHold() {
        promptHoldUntil = 0
    }

    /// 판정 중지 여부 (CGEventTap 콜백 최상단에서 검사).
    func shouldSuppressCorrection() -> Bool {
        if suppressedAppActive { return true }
        if Date().timeIntervalSince1970 * 1000 < promptHoldUntil { return true }
        return false
    }

    // MARK: 키스트림 처리

    /// CGEventTap 콜백이 글쇠마다 호출. 반환: 대체 이벤트 버퍼(비어있으면 통과).
    ///  - 글쇠가 포함된 이벤트는 (a) pendingKey에 추가하고 "일단 수용",
    ///    (b) 런이 끝나는 글쇠면 판정 후 needed만큼 backspace + 교정문 전송.
    func handleKey(_ key: CTKey, timestampMs: Double) -> [CTKey] {
        if shouldSuppressCorrection() {
            flushPending(sendCorrection: false)
            return [key]
        }

        // word timeout: 사람이 멈추면 런을 확정하고 다음 키부터 새 런 시작.
        // 교정이 필요하면 (backspace N + 교정문)을 리턴 이벤트 앞에 붙인다.
        var deferredEvents: [CTKey] = []
        if !pendingKeys.isEmpty, lastEventMs > 0,
           timestampMs - lastEventMs > config.wordTimeoutMs {
            deferredEvents = commitPendingFromTimeout()
        }
        lastEventMs = timestampMs

        pendingKeys.append((key, timestampMs))
        pendingRaw += ctKeyToLatin(key)

        // 런 종료 글쇠인가? (공백/개행 등 판정 후보 이외 문자)
        if isRunEndKey(key) {
            // 마지막 글쇠(공백·개행 등)는 판정 대상에서 제외 — 뒤에 붙여 재전송
            let wordKeys = Array(pendingKeys.dropLast())
            let tailKey = pendingKeys.last!.key
            let decisionText = judge(wordKeys)
            if decisionText == nil || decisionText!.count > config.maxRewriteLength {
                // 교정 없음 — 그대로 통과(런 비움)
                pendingKeys.removeAll(); pendingRaw.removeAll()
                return [key]
            }
            // 1) 단어 부분만 backspace로 지우고, 2) 교정문 + tail 글쇠를 순서대로 SEND.
            var events: [CTKey] = []
            for _ in 0..<wordKeys.count { events.append(CTKey(code: "Backspace", shift: false)) }
            for ch in decisionText! {
                if ch == "\n" {
                    events.append(CTKey(code: "Enter", shift: false))
                } else if ch == " " {
                    events.append(CTKey(code: "Space", shift: false))
                } else if let k = ctCharToKey(ch) {
                    events.append(k)
                }
                // 판정기가 숫자/기호를 내줄 일은 없음(런 판정은 영문자만) — 방어적 스킵.
            }
            events.append(tailKey)
            pendingKeys.removeAll(); pendingRaw.removeAll()
            return events
        }

        // 아직 런 진행 중 — 판정 시도(opportunistic): prefix 근거 이하면 조용히 유지.
        // 실제 재전송은 런 종료에서 한 번만 일어난다.
        if deferredEvents.isEmpty { return [] }
        return deferredEvents + [key]
    }

    /// 비영문 글쇠(숫자/기호/모디파이어) — 런을 끊고 확정.
    /// 반환: 교정 이벤트 시퀀스(backspace N + 교정문) — 비어있으면 통과.
    func handleNonAlphaEvent(timestampMs: Double) -> [CTKey] {
        lastEventMs = timestampMs
        guard !shouldSuppressCorrection(), !pendingKeys.isEmpty else {
            pendingKeys.removeAll(); pendingRaw.removeAll()
            return []
        }
        return commitPendingFromTimeout()
    }

    /// 입력 소스가 바뀌었을 때(한영 전환 등) — 런을 끊는다(교정 없음 — 소스 전환은 의도 변경).
    func handlePossibleInterruption() {
        pendingKeys.removeAll(); pendingRaw.removeAll()
    }

    /// word timeout 경로의 런 확정: (backspace N, 교정문) → CTKey 이벤트 시퀀스로 변환.
    private func commitPendingFromTimeout() -> [CTKey] {
        defer { pendingKeys.removeAll(); pendingRaw.removeAll() }
        if shouldSuppressCorrection() { return [] }
        guard let decision = judge(pendingKeys.map(\.key)),
              decision.count <= config.maxRewriteLength else { return [] }
        return buildCorrectionEvents(backspaceCount: pendingKeys.count, replacement: decision, tail: nil)
    }

    /// 일정 시간 입력이 없을 때(런루프 타이머) — 런 강제 확정.
    /// 반환: 교정이 확정되면 (지울 글쇠 수, 교정 문자열) — AppDelegate가 CGEvent로 전송.
    func handleIdleCommit(nowMs: Double) -> (backspaceCount: Int, replacement: String)? {
        guard !pendingKeys.isEmpty else { return nil }
        guard lastEventMs > 0, nowMs - lastEventMs > config.wordTimeoutMs else { return nil }
        let count = pendingKeys.count
        let events = commitPendingFromTimeout()
        guard !events.isEmpty else { return nil }
        // events: backspace N + 교정문 — 교정문 텍스트만 다시 뽑는다.
        var replacement = ""
        for k in events.dropFirst(count) {
            switch k.code {
            case "Enter": replacement.append("\n")
            case "Space": replacement.append(" ")
            default: replacement.append(ctKeyToLatin(k))
            }
        }
        return (count, replacement)
    }

    /// 교정 이벤트 시퀀스 생성: backspace N + 교정문(+optional tail 글쇠).
    private func buildCorrectionEvents(backspaceCount: Int, replacement: String, tail: CTKey?) -> [CTKey] {
        var events: [CTKey] = []
        for _ in 0..<backspaceCount { events.append(CTKey(code: "Backspace", shift: false)) }
        for ch in replacement {
            if ch == "\n" {
                events.append(CTKey(code: "Enter", shift: false))
            } else if ch == " " {
                events.append(CTKey(code: "Space", shift: false))
            } else if let k = ctCharToKey(ch) {
                events.append(k)
            }
            // 판정기가 숫자/기호를 내줄 일은 없음(런 판정은 영문자만) — 방어적 스킵.
        }
        if let tail = tail { events.append(tail) }
        return events
    }

    private func isRunEndKey(_ key: CTKey) -> Bool {
        switch key.code {
        case "Space", "Enter", "Tab":
            return true
        default:
            return false
        }
    }

    /// 판정 → 교정 문자열(원본과 같으면 nil). 세션 언어 상태 갱신.
    private func judge(_ wordKeys: [CTKey]) -> String? {
        guard let dicts = dicts, !wordKeys.isEmpty else { return nil }
        // pending 런 전체를 processText 규약으로 판정 — 덩어리 1회 처리가 세션 상태 흐름과 동일.
        let raw = wordKeys.map(ctKeyToLatin).joined()
        let result = ctProcessText(raw, initialLang: sessionLang, dicts: dicts)
        guard let first = result.words.first else { return nil }
        // 관대 통과: 판정 결과가 원본과 같으면 재전송 생략 — 전송 이벤트 최소화.
        // (passwordSuspect 런도 raw==output이라 여기서 자동 통과 — 이중 방어 3번째 층.)
        if first.output == first.raw { return nil }
        // mixed 런은 세그먼트 결합 출력 — raw와 다르므로 교정 대상.
        sessionLang = result.finalLang
        return first.output
    }

    /// pending 런을 보류(flush)만 — 교정 없음(앱 전환·권한 대기 등).
    func flushPending(sendCorrection: Bool) {
        pendingKeys.removeAll(); pendingRaw.removeAll()
    }
}

#endif // os(macOS)
