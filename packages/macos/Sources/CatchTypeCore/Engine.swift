//
//  Engine.swift
//  CatchTypeCore
//
//  판정 엔진 — TS engine (packages/engine/src/engine.ts v1.1)의 전수 이식.
//  규칙(v1.1, docs/SPEC.md 우선순위 구현):
//   1) 현재 언어로 읽은 읽기가 "말이 되면" 통과 (근거: 사전 일치 > 약어 > 자모 반복 > 통계)
//   2) 아니면 반대 언어로 읽어 유효하면 그 단어만 반대 언어로 판정(상태 전환)
//   3) 둘 다 유효하면 근거 등급이 높은 쪽 승; 같으면 현재 상태 유지.
//      단, 둘 다 사전 일치이고 반대쪽 빈도 가중치가 3배 이상이면 반대쪽 승.
//   4) 둘 다 무효면 단어 내부 분할(mixed)을 시도.
//   5) 그래도 무효면 그대로 통과(fallback — 오타/부호/고유명사, 카멜케이스 보호).
//  비밀번호 의심 토큰(문자 클래스 3종 이상 혼용)은 판정하지 않고 통과 + 플래그.
//

import Foundation

/// 판정 근거. prefix는 "타이핑 도중이라 아직 유효"인 중간 상태만 해당.
public enum CTBasis: String, Equatable {
    case dict, prefix, acronym
    case jamoRun = "jamo-run"
    case stats
    case none

    var rank: Int {
        switch self {
        case .dict: return 5
        case .acronym: return 4
        case .jamoRun: return 3
        case .stats: return 2
        case .prefix: return 1
        case .none: return 0
        }
    }

    var confidence: Double {
        switch self {
        case .dict: return 0.95
        case .acronym: return 0.8
        case .jamoRun: return 0.7
        case .stats: return 0.75
        case .prefix: return 0.55
        case .none: return 0
        }
    }
}

public struct CTRead: Equatable {
    public var text: String        // 해당 언어로 읽은 문자열
    public var basis: CTBasis
    public var confidence: Double  // 0~1
    public var valid: Bool

    static let invalid = CTRead(text: "", basis: .none, confidence: 0, valid: false)
}

public struct CTSegmentInfo: Equatable {
    public var raw: String
    public var lang: CTLang
    public var text: String
    /// 세그먼트는 "완성 근거"만 인정 (dict/acronym/jamo-run) — mixed fallback분할은 'fallback'
    public var basis: String
    public var confidence: Double
}

public struct CTWordDecision: Equatable {
    public var raw: String         // 입력(영문 키 문자열)
    public var output: String      // 판정 결과 문자열
    public var lang: CTLang        // 이 단어의 확정 언어(세션 상태 갱신에 사용)
    public var switched: Bool      // 세션 상태가 바뀌었는가
    public var reason: String      // dict | acronym | jamo-run | stats | prefix | alt-hit | both-keep | both-alt | mixed | fallback | password-suspect
    public var confidence: Double
    public var segments: [CTSegmentInfo]?
    public var passwordSuspect: Bool
}

public struct CTEngineResult: Equatable {
    public var text: String
    public var initialLang: CTLang
    public var finalLang: CTLang
    public var words: [CTWordDecision]
    public var passwordSuspect: Bool
}

public struct CTDicts {
    public var ko: CTDict
    public var en: CTDict
    /// 한국어 자모 바이그램 허용집합(통계 판정용, 없으면 통계 경로 비활성)
    public var koBigrams: Set<String>?

    public init(ko: CTDict, en: CTDict, koBigrams: Set<String>?) {
        self.ko = ko
        self.en = en
        self.koBigrams = koBigrams
    }
}

/**
 * 사전 보강(v1.1): EXTRA_EN_WORDS(개발 용어 등)를 en사전에 합쳐 CTDicts 회선.
 * weightOf는 rank 기반이므로 보강 단어는 인공 순위로 넣어 흔한 단어와 충돌하지 않게 한다
 * (가중치 ~0.75 — 흔한 단어(1.0) 역전을 일으키지 않는 수준).
 * 자주 불리는 순수 함수이므로 입력 CTDicts가 같으면 캐시한 결과를 돌려준다.
 */
public let ctExtraEnWords: [String] = [
    "git", "npm", "yaml", "json", "eslint", "prettier", "webpack",
    "typescript", "javascript", "bash", "zsh", "vim", "nvim", "sudo", "curl",
    "docker", "kubernetes", "pytest", "django", "flask", "golang", "rust",
    "localhost", "hostname", "rebase", "stash", "fork", "pypi", "rubygems",
    "dotenv", "vite", "rollup", "esbuild", "bun", "deno", "jsx", "tsx",
    "uuid", "oauth", "jwt", "sdk", "jdk", "tokenizer", "transpile",
]

/// 자모 반복 이모티콘 휴리스틱 (ㅋㅋ, ㅎㅎ, ㅠㅠ, ㅡㅡ, ㅜㅜ)
private let ctRunSet: Set<String> = ["ㅋ", "ㅎ", "ㅠ", "ㅡ", "ㅜ"]

/**
 * 충돌 시 빈도 가중치 역전 임계(3배): 'dp vs 에'(3.97배), 'rh vs 고'(3.98배) 같은
 * 단일 사전 충돌을 되돌리려면 4배로는 비좁다. 3배 임계로 내려도 사전 {fickme, fsoj}
 * 검증에서 흔한 영어 단어(빈도 상위)는 하나도 역전되지 않는다.
 */
private let ctWeightFlipRatio = 3.0

private enum CTDictsAugmentCache {
    static var cachedRef: CTDicts?
    static var cached: CTDicts?
}

public func ctAugmentDicts(_ dicts: CTDicts) -> CTDicts {
    // 캐시 규약: 같은 참조 입력(TS) 대신 Swift에서는 사전 크기가 같으면 캐시 결과,
    // 다르면 재계산. augment∘augment = augment (부수효과 없음).
    if let ref = CTDictsAugmentCache.cachedRef, let cached = CTDictsAugmentCache.cached {
        if ref.en.sorted.count == dicts.en.sorted.count && ref.ko.sorted.count == dicts.ko.sorted.count {
            return cached
        }
    }
    var entries: [(String, Double)] = dicts.en.sorted.compactMap { w in
        guard let f = dicts.en.words[w] else { return nil }
        return (w, f)
    }
    let present = Set(dicts.en.words.keys)
    let newOnes = ctExtraEnWords.filter { !present.contains($0) }
    let rankBase = dicts.en.sorted.count
    let rankScale = max(1.0, Double(Int(Double(rankBase) / 4.0))) // 상위 25% 수준의 가중치
    for (i, w) in newOnes.enumerated() {
        entries.append((w, Double(max(1, rankBase + 1 - i * Int(rankScale)))))
    }
    let en = CTDict(lang: .en, entries: entries)
    let out = CTDicts(ko: dicts.ko, en: en, koBigrams: dicts.koBigrams)
    CTDictsAugmentCache.cachedRef = dicts
    CTDictsAugmentCache.cached = out
    return out
}

/**
 * 비밀번호 의심: 문자 클래스(대문자/소문자/숫자/기호) 3종 이상 혼용.
 * 2종 혼용은 평범한 문장·토큰('Catch22', 'abc123')과 구분이 안 되므로 판정을 계속한다.
 */
public func ctLooksLikePassword(_ token: String) -> Bool {
    var classes = 0
    if token.range(of: "[A-Z]", options: .regularExpression) != nil { classes += 1 }
    if token.range(of: "[a-z]", options: .regularExpression) != nil { classes += 1 }
    if token.range(of: "[0-9]", options: .regularExpression) != nil { classes += 1 }
    if token.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { classes += 1 }
    return classes >= 3
}

/** ㅋㅎㅠㅜㅡ 반복 이모티콘 */
private func ctIsEmojiRun(_ text: String) -> Bool {
    let chars = Array(text)
    guard chars.count >= 2, let first = chars.first, ctRunSet.contains(String(first)) else { return false }
    return chars.allSatisfy { String($0) == String(first) }
}

/// 자판 런 폴백 (한국어 상태 전용) 판정용: en 읽기가 무근거 + 전 글쇠 자모 매핑 성공
private func ctIsQwertyRunFallback(_ keys: [CTKey], _ enRead: CTRead) -> Bool {
    if enRead.basis != .none { return false }
    return keys.allSatisfy { ctKeyToJamo($0) != nil }
}

/**
 * 통계 판정: 조합 전의 "타이핑된 자모 시퀀스"를 그대로 검사한다 (조합 출력을
 * 다시 분해하지 않는다 — ㄷㄷ→ㄸ 같은 쌍자모 합성이 분해 roundtrip을 깨기 때문).
 * 인접 자모 바이그램이 모두 코퍼스 허용집합에 속하면 "한글다운"으로 본다 (≥3 자모).
 */
private func ctIsPlausibleJamoSeq(_ jamo: [String], _ bigrams: Set<String>?) -> Bool {
    guard let bigrams = bigrams, !bigrams.isEmpty, jamo.count >= 3 else { return false }
    for i in 0..<(jamo.count - 1) {
        if !bigrams.contains(jamo[i] + jamo[i + 1]) { return false }
    }
    return true
}

/// 영어 읽기: 대소문자 보존, 사전 비교는 소문자
private func ctReadEn(_ keys: [CTKey], _ dict: CTDict?) -> CTRead {
    let text = keys.map(ctKeyToLatin).joined()
    let low = text.lowercased()
    if let dict = dict {
        if dict.hasWord(low) { return CTRead(text: text, basis: .dict, confidence: CTBasis.dict.confidence, valid: true) }
        if dict.hasPrefix(low) { return CTRead(text: text, basis: .prefix, confidence: CTBasis.prefix.confidence, valid: true) }
    }
    // /^[A-Z]{2,4}$/ 약어 판정 — ASCII 대문자 2~4글자(둘 이상)
    if text.count >= 2, text.count <= 4,
       text.unicodeScalars.allSatisfy({ $0.value >= 0x41 && $0.value <= 0x5A }) {
        return CTRead(text: text, basis: .acronym, confidence: CTBasis.acronym.confidence, valid: true)
    }
    return .invalid
}

/// 한국어 읽기: 두벌식 자모 조합 → 완성형 문자열
private func ctReadKo(_ keys: [CTKey], _ dict: CTDict?, _ bigrams: Set<String>?) -> CTRead {
    var jamo: [String] = []
    for k in keys {
        guard let j = ctKeyToJamo(k) else { return .invalid }
        jamo.append(j)
    }
    let text = ctComposeJamo(jamo)
    if let dict = dict {
        if dict.hasWord(text) { return CTRead(text: text, basis: .dict, confidence: CTBasis.dict.confidence, valid: true) }
        if dict.hasPrefix(text) { return CTRead(text: text, basis: .prefix, confidence: CTBasis.prefix.confidence, valid: true) }
    }
    if ctIsPlausibleJamoSeq(jamo, bigrams) { return CTRead(text: text, basis: .stats, confidence: CTBasis.stats.confidence, valid: true) }
    if ctIsEmojiRun(text) { return CTRead(text: text, basis: .jamoRun, confidence: CTBasis.jamoRun.confidence, valid: true) }
    return .invalid
}

private func ctRead(_ keys: [CTKey], _ lang: CTLang, _ dict: CTDict?, _ bigrams: Set<String>?) -> CTRead {
    lang == .en ? ctReadEn(keys, dict) : ctReadKo(keys, dict, bigrams)
}

/// 완성된 세그먼트용 읽기 — 접두어·통계 근거는 불인정(아무 데나 자를 수 있게 됨)
private func ctReadComplete(_ keys: [CTKey], _ lang: CTLang, _ dict: CTDict?, _ bigrams: Set<String>?) -> CTRead {
    let r = ctRead(keys, lang, dict, bigrams)
    if r.basis == .prefix || r.basis == .stats {
        return CTRead(text: r.text, basis: .none, confidence: 0, valid: false)
    }
    return r
}

/**
 * 충돌 해소: 둘 다 유효할 때 어느 쪽을 택할까.
 * 근거 등급이 높은 쪽 승 → 같으면 사전 일치 간 빈도 역전(3배) 검사 → 그래도 현상태.
 */
private func ctResolveConflict(
    _ cur: CTRead, _ alt: CTRead, _ state: CTLang, _ dicts: CTDicts?
) -> (pick: CTLang, why: String) {
    let rc = cur.basis.rank
    let ra = alt.basis.rank
    if ra > rc { return (state.other, "both-alt(basis)") }
    if ra < rc { return (state, "both-keep(basis)") }
    if cur.basis == .dict, let dicts = dicts {
        let wc = dicts[state].weightOf(cur.text)
        let wa = dicts[state.other].weightOf(alt.text)
        if let wc = wc, let wa = wa, wa >= wc * ctWeightFlipRatio {
            return (state.other, "both-alt(freq)")
        }
    }
    return (state, "both-keep")
}

/**
 * v1.1 카멜케이스/고유명 보호: 대문자-시작 카멜케이스 토큰('Figma', 'GitHub')을 쳤는데
 * en사전에(접두어조차) 없을 때, 반대 언어 읽기가 통계·자모런 근거로 이기려 하면 오판이다 —
 * 진짜 영어 고유명을 ko통계로 갈아치우는 실수. 두 상태(@ko와 @en 모두)에서 발동.
 */
private func ctIsCamelCaseProtected(
    _ keys: [CTKey], _ cur: CTRead, _ alt: CTRead, _ raw: String, _ dict: CTDict?
) -> Bool {
    // /^[A-Z][a-z]+$/ — 대문자 1 + 소문자들(약어 TODO·A와 구분)
    let scalars = Array(raw.unicodeScalars)
    guard scalars.count >= 2, scalars[0].value >= 0x41 && scalars[0].value <= 0x5A,
          scalars.dropFirst().allSatisfy({ $0.value >= 0x61 && $0.value <= 0x7A }) else { return false }
    guard let dict = dict else { return false }
    if dict.hasPrefix(raw.lowercased()) { return false } // 사전 접두어도 없음
    // ko 쪽이 약근거(stats·jamo-run)일 때만 보호: 어느 상태든 ko읽기 근거로 판단.
    let koIsWeak = cur.basis == .stats || cur.basis == .jamoRun ||
        alt.basis == .stats || alt.basis == .jamoRun
    if !koIsWeak { return false }
    return true
}

private func ctMixedSegments(
    _ keys: [CTKey], _ state: CTLang, _ dicts: CTDicts
) -> (segments: [CTSegmentInfo], confidence: Double)? {
    // v1.1 분할 정책:
    //  - 앞세그먼트 "완성 근거" 필수, 뒤세그먼트 2키 이상(조사 결합형 허용: test+도, README+에).
    //    단, 앞세그먼트가 2키이면 뒤세그먼트도 2키여야 한다(고전 규칙 유지: AIfh→AI+로).
    //  - 뒤세그먼트가 3키 이상이면 사전 일치만 인정 — 완전 접두 오분할('te|st'류) 차단.
    //  - 앞세그먼트는 반대 언어 "사전 prefix"도 인정.
    //  - 세그먼트 순서는 [반대 언어, 현재 언어]를 먼저 스캔: 판정을 뒤집는 mixed 우선.
    var best: ([CTSegmentInfo], Double)? = nil
    var bestScore = -1.0
    if keys.count >= 4 {
        for i in 2...(keys.count - 2) {
            for (l1, l2) in [(state.other, state), (state, state.other)] {
                let aRaw = Array(keys[0..<i])
                let a = ctRead(aRaw, l1, dicts[l1], dicts.koBigrams)
                if !a.valid { continue }
                // 앞세그먼트가 "완성 근거"(dict·acronym)가 아니면(=prefix·stats만) 접두어 사용 조건 검사:
                // 반대 세그먼트는 반드시 사전 일치여야 한다 (아닐 시 이 분할은 불인정).
                let needsComplete = a.basis != .dict && a.basis != .acronym
                let bRaw = Array(keys[i...])
                if bRaw.count < 2 { continue }
                // 앞세그먼트 2키면 뒤세그먼트도 2키여야 한다(고전 규칙: AIfh → AI+로).
                if i == 2 && bRaw.count > 2 { continue }
                let b = ctRead(bRaw, l2, dicts[l2], dicts.koBigrams)
                if !b.valid { continue }
                if needsComplete || bRaw.count >= 3 {
                    // 둘 중 하나라도 "완전 확정" 조건 요구 시: 양쪽 모두 사전 일치여야 한다
                    if a.basis != .dict || b.basis != .dict || aRaw.count < 3 || bRaw.count > 2 { continue }
                }
                let score = min(a.confidence, b.confidence) * 100 + (a.confidence + b.confidence)
                if score > bestScore {
                    bestScore = score
                    let segs: [CTSegmentInfo] = [
                        CTSegmentInfo(raw: aRaw.map(ctKeyToLatin).joined(), lang: l1, text: a.text, basis: a.basis.rawValue, confidence: a.confidence),
                        CTSegmentInfo(raw: bRaw.map(ctKeyToLatin).joined(), lang: l2, text: b.text, basis: b.basis.rawValue, confidence: b.confidence),
                    ]
                    best = (segs, min(a.confidence, b.confidence))
                }
            }
        }
    }
    if let best = best { return best }
    // v1.1 조사 결합 fallback분할: 앞세그먼트에 사전 근거가 없어도(README 등 fallback 통과
    // 접두 명사), 뒤세그먼트가 고빈도 한국어 조사(도/에/는/은/이/가/를/을/로 등, 2키,
    // 사전 일치 + 가중치 0.9 이상)일 때는 'READMEdp'→'README에' 혼합을 인정한다.
    // 앞세그먼트는 3키 이상, 언어는 현재 상태(그대로 통과), 뒤세그먼트는 반대 언어.
    if keys.count >= 5 {
        for i in 3...keys.count-2 {
            let bRaw = Array(keys[i...])
            if bRaw.count != 2 { continue }
            let altLang = state.other
            let b = ctReadComplete(bRaw, altLang, dicts[altLang], dicts.koBigrams)
            if !b.valid || b.basis != .dict { continue }
            let w = dicts[altLang].weightOf(b.text)
            if w == nil || w! < 0.9 { continue }
            let aText = keys[0..<i].map(ctKeyToLatin).joined()
            return (
                [
                    CTSegmentInfo(raw: aText, lang: state, text: aText, basis: "fallback", confidence: 0),
                    CTSegmentInfo(raw: bRaw.map(ctKeyToLatin).joined(), lang: altLang, text: b.text, basis: b.basis.rawValue, confidence: b.confidence),
                ],
                b.confidence
            )
        }
    }
    return nil
}

private func ctKeysraw(_ keys: [CTKey]) -> String {
    keys.map(ctKeyToLatin).joined()
}

/** 단어(영문자만으로 된 키 런) 하나를 판정. 세션 상태(state)를 받아 결정을 돌려준다. */
public func ctJudgeWord(_ keys: [CTKey], _ state: CTLang, _ dicts: CTDicts?) -> CTWordDecision {
    let raw = ctKeysraw(keys)
    func passthrough(_ reason: String, _ lang: CTLang, _ conf: Double = 0) -> CTWordDecision {
        CTWordDecision(raw: raw, output: raw, lang: lang, switched: false, reason: reason,
                       confidence: conf, segments: nil, passwordSuspect: false)
    }

    if keys.isEmpty { return passthrough("empty", state) }

    if ctLooksLikePassword(raw) {
        return CTWordDecision(raw: raw, output: raw, lang: state, switched: false,
                              reason: "password-suspect", confidence: 0, segments: nil, passwordSuspect: true)
    }

    let cur = ctRead(keys, state, dicts?[state], dicts?.koBigrams)
    let alt = ctRead(keys, state.other, dicts?[state.other], dicts?.koBigrams)

    // 카멜케이스 보호(v1.1): 한국어 상태에서 대문자 시작 단어가 en사전에 없어
    // ko통계가 이기려 할 때, en 무근거를 "고유명사"로 보고 그대로 통과시킨다.
    if let dicts = dicts, ctIsCamelCaseProtected(keys, cur, alt, raw, dicts.en) {
        return passthrough("fallback", state)
    }

    // 자판 런 폴백: 한국어 상태 + en 쪽 완전 무근거 + 전 글쇠 자모 매핑 성공
    // (zzqq → ㅋㅌㅊㅍ, asdf → ㅁㄴㅇㄹ) — 어떤 유효 판정도 안 나왔을 때만 적용.
    if state == .ko, !cur.valid, !alt.valid,
       ctIsQwertyRunFallback(keys, cur), ctIsQwertyRunFallback(keys, alt) {
        let jamoSeq = keys.compactMap(ctKeyToJamo)
        let text = ctComposeJamo(jamoSeq)
        return CTWordDecision(raw: raw, output: text, lang: .ko, switched: false,
                              reason: "jamo-run", confidence: CTBasis.jamoRun.confidence,
                              segments: nil, passwordSuspect: false)
    }

    if cur.valid && alt.valid {
        let (pick, why) = ctResolveConflict(cur, alt, state, dicts)
        let chosen = pick == state ? cur : alt
        return CTWordDecision(raw: raw, output: chosen.text, lang: pick,
                              switched: pick != state, reason: why,
                              confidence: chosen.confidence, segments: nil, passwordSuspect: false)
    }

    if cur.valid {
        return CTWordDecision(raw: raw, output: cur.text, lang: state, switched: false,
                              reason: cur.basis.rawValue, confidence: cur.confidence,
                              segments: nil, passwordSuspect: false)
    }

    let mixed = dicts.map { ctMixedSegments(keys, state, $0) } ?? nil

    // v1.1: 반대 언어 읽기가 최약 근거(통계)뿐이고, 사전 일치 세그먼트로 완성되는 혼합 분할이
    // 있으면 그쪽을 택한다 — 'testeh'(@en)는 ko통계 'ㅅㄷㄴㅅ도'보다 'test+도' 혼합이 옳다.
    let weakAlt = alt.valid && (alt.basis == .stats || alt.basis == .jamoRun)
    if weakAlt, let mixed = mixed {
        let allDict = mixed.segments.allSatisfy { $0.basis == "dict" }
        let altLang = state.other
        // 혼합이 반대 언어 결론(마지막 세그먼트가 alt 언어)일 때만 반대 읽기를 덮어쓴다
        if allDict, let last = mixed.segments.last, last.lang == altLang {
            return CTWordDecision(raw: raw, output: mixed.segments.map(\.text).joined(),
                                  lang: altLang, switched: true, reason: "mixed",
                                  confidence: mixed.confidence, segments: mixed.segments,
                                  passwordSuspect: false)
        }
    }

    if alt.valid {
        return CTWordDecision(raw: raw, output: alt.text, lang: state.other, switched: true,
                              reason: "alt-hit", confidence: alt.confidence,
                              segments: nil, passwordSuspect: false)
    }

    if let mixed = mixed {
        let last = mixed.segments[mixed.segments.count - 1]
        return CTWordDecision(raw: raw, output: mixed.segments.map(\.text).joined(),
                              lang: last.lang, switched: last.lang != state,
                              reason: "mixed", confidence: mixed.confidence,
                              segments: mixed.segments, passwordSuspect: false)
    }

    return passthrough("fallback", state)
}

private func ctTokenize(_ input: String) -> [String] {
    // 공백 런을 보존하면서 비공백 토큰으로 분할
    var out: [String] = []
    var cur = ""
    var curIsSpace: Bool? = nil
    for ch in input {
        let isSpace = ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
        if curIsSpace == nil {
            cur = String(ch); curIsSpace = isSpace
        } else if curIsSpace == isSpace {
            cur.append(ch)
        } else {
            out.append(cur); cur = String(ch); curIsSpace = isSpace
        }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

private func ctIsAllWhitespace(_ token: String) -> Bool {
    !token.isEmpty && token.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
}

private func ctIsAlpha(_ s: String) -> Bool {
    !s.isEmpty && s.unicodeScalars.allSatisfy { ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) }
}

private func ctHasAlpha(_ s: String) -> Bool {
    s.unicodeScalars.contains { ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) }
}

/**
 * 토큰 내부를 영문자 런 / 비영문자 런으로 분리.
 * TS 규약과 동일한 /([a-zA-Z]+|[^a-zA-Z]+)/g 분할.
 */
private func ctTokenRuns(_ token: String) -> [String] {
    var out: [String] = []
    var cur = ""
    var curIsAlpha: Bool? = nil
    for ch in token.unicodeScalars {
        let isAlpha = (ch.value >= 0x41 && ch.value <= 0x5A) || (ch.value >= 0x61 && ch.value <= 0x7A)
        if let prev = curIsAlpha, prev == isAlpha {
            cur.unicodeScalars.append(ch)
        } else {
            if !cur.isEmpty { out.append(cur) }
            cur = String(ch)
            curIsAlpha = isAlpha
        }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

/**
 * 전체 문장 처리. 공백/개행은 그대로 보존, 비공백 토큰은
 * - 비밀번호 의심 → 그대로 통과
 * - 그 외: 영문자 런은 판정, 나머지(숫자/부호) 런은 그대로 통과
 * 세션 언어 상태는 판정이 확정될 때만 갱신된다.
 */
public func ctProcessText(
    _ input: String,
    initialLang: CTLang = .en,
    dicts: CTDicts?,
    noAugment: Bool = false
) -> CTEngineResult {
    var state = initialLang
    var out = ""
    var words: [CTWordDecision] = []
    var passwordSuspect = false

    // v1.1: 사전 보강(개발 용어 등) 기본 적용. noAugment 로 원본 사전만 쓰는 보수 모드.
    var effDicts = dicts
    if dicts != nil, !noAugment {
        effDicts = ctAugmentDicts(dicts!)
    }

    for token in ctTokenize(input) {
        if ctIsAllWhitespace(token) {
            out += token
            continue
        }
        if ctLooksLikePassword(token) {
            out += token
            passwordSuspect = true
            words.append(CTWordDecision(raw: token, output: token, lang: state, switched: false,
                                        reason: "password-suspect", confidence: 0, segments: nil,
                                        passwordSuspect: true))
            continue
        }
        // 토큰 내부를 영문자 런 / 비영문자 런으로 분리.
        // TS 규약: 영문자 런만 판정; 나머지(숫자/부호/한글 혼입)는 그대로 통과.
        for run in ctTokenRuns(token) {
            if !ctHasAlpha(run) {
                out += run // 숫자·부호: 두 언어 모두 통과
                continue
            }
            if !ctIsAlpha(run) {
                // 영문자 혼입 런(한글 등) — 영문자 부분만 판정 대상.
                // TS와 동일하게 순서를 보존: 판정 가능한 영문자만 judgeWord에 넘긴다.
                var keys: [CTKey] = []
                for ch in run where ctCharToKey(ch) != nil {
                    keys.append(ctCharToKey(ch)!)
                }
                if !keys.isEmpty {
                    let decision = ctJudgeWord(keys, state, effDicts)
                    out += decision.output
                    state = decision.lang
                    words.append(decision)
                    if decision.passwordSuspect { passwordSuspect = true }
                    continue
                }
                out += run // 판정 가능한 글쇠가 없으면 그대로
                continue
            }
            var keys: [CTKey] = []
            for ch in run {
                if let k = ctCharToKey(ch) { keys.append(k) }
            }
            if keys.isEmpty {
                out += run // 판정 가능한 영문 글쇠가 하나도 없는 런 — 그대로 통과
                continue
            }
            let decision = ctJudgeWord(keys, state, effDicts)
            out += decision.output
            state = decision.lang
            words.append(decision)
            if decision.passwordSuspect { passwordSuspect = true }
        }
    }

    return CTEngineResult(text: out, initialLang: initialLang, finalLang: state,
                          words: words, passwordSuspect: passwordSuspect)
}

extension CTDicts {
    public subscript(lang: CTLang) -> CTDict {
        lang == .ko ? ko : en
    }
}
