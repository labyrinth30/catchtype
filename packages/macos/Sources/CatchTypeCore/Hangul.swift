//
//  Hangul.swift
//  CatchTypeCore
//
//  한글 조합기 — TS engine (packages/engine/src/hangul.ts)의 전수 이식.
//  규약 동일: 두벌식 호환 자모(U+3131–U+3163) 시퀀스를 표준 IME 조합 규칙으로
//  완성형 음절(U+AC00–)로 조립. 현 IME가 하듯 라이브 음절 하나 남기고 확정.
//

/// 초성 19 (유니코드 음절 인덱스 순와 동일한 순서)
public let CT_CHO: [String] = [
    "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
    "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
]

/// 중성 21
public let CT_JUNG: [String] = [
    "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ",
    "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ",
]

/// 종성 28 (0 = 종성 없음). index 0은 placeholder null.
public let CT_JONG: [String?] = [
    nil, "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ",
    "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ",
    "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
]

/// 복모음 합성: [첫 중성, 둘째 중성] → 합성 중성
private let CT_JUNG_MERGE: [String: String] = [
    "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ",
    "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ",
    "ㅡㅣ": "ㅢ",
]

/// 겹받침 합성: [받침, 자음] → 겹받침
private let CT_JONG_MERGE: [String: String] = [
    "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ",
    "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ",
    "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
]

private let CT_CHO_MERGE: [String: String] = [
    "ㄱㄱ": "ㄲ", "ㄷㄷ": "ㄸ", "ㅂㅂ": "ㅃ", "ㅅㅅ": "ㅆ", "ㅈㅈ": "ㅉ",
]

private let CT_CHO_IDX: [String: Int] = Dictionary(uniqueKeysWithValues: CT_CHO.enumerated().map { ($1, $0) })
private let CT_JUNG_IDX: [String: Int] = Dictionary(uniqueKeysWithValues: CT_JUNG.enumerated().map { ($1, $0) })
private let CT_JONG_IDX: [String: Int] = {
    var m: [String: Int] = [:]
    for (i, j) in CT_JONG.enumerated() { if let j = j { m[j] = i } }
    return m
}()

/// 종성이 될 수 있는 단일 받침 (겹받침은 합성으로만 생김)
private let CT_JONG_SINGLE: Set<String> = [
    "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
]

public func ctIsHangulSyllable(_ ch: Character) -> Bool {
    guard ch.unicodeScalars.count == 1, let s = ch.unicodeScalars.first else { return false }
    let n = Int(s.value)
    return n >= 0xAC00 && n <= 0xD7A3
}

/// 호환 자모 3개 합성: 초/중/종 인덱스로 완성형 음절 1글자. 잘못된 조합은 nil.
public func ctComposeSyllable(_ cho: String, _ jung: String, _ jong: String? = nil) -> String? {
    guard let c = CT_CHO_IDX[cho], let j = CT_JUNG_IDX[jung] else { return nil }
    var g = 0
    if let jong = jong {
        guard let gg = CT_JONG_IDX[jong] else { return nil }
        g = gg
    }
    if let scalar = Unicode.Scalar(0xAC00 + c * 588 + j * 28 + g) {
        return String(Character(scalar))
    }
    return nil
}

private enum CTLive {
    case cho(String)
    case jung(String)
    case syll(cho: String, jung: String, jong: String?)
}

private func ctFlush(_ live: CTLive?, _ out: inout [String]) {
    guard let live = live else { return }
    switch live {
    case .cho(let ch), .jung(let ch):
        out.append(ch) // 호환 자모 그대로
    case .syll(let cho, let jung, let jong):
        if let s = ctComposeSyllable(cho, jung, jong) { out.append(s) }
    }
}

/**
 * 호환 자모(두벌식 자모) 시퀀스를 조합 규칙에 따라 문자열로 조립.
 * 실 IME처럼: 조합 중인 마지막 요소만 미완으로 남기고 완성분은 확정.
 * 예) ["ㅇ","ㅏ","ㄴ","ㄴ","ㅕ","ㅇ"] → "안녕"
 *     ["ㄹ","ㅗ","ㄴ","ㅇ","ㅏ","ㄴ"] → "롤안" (ㄴ+ㅇㅏ: 받친 ㄴ이 회수되어 안)
 * 타이핑 시퀀스는 단일 자모만 나오지만, decompose()의 역산 재조립(recompose)을
 * 지원하기 위해 복합 종성(ㄳ ㄵ ㄶ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅄ)이 직접 들어오면
 * 현재 음절의 받침으로 수용한다 (실 IME 합성 결과와 동일한 최종 상태).
 */
public func ctComposeJamo(_ seq: [String]) -> String {
    var out: [String] = []
    var live: CTLive? = nil

    for jamo in seq {
        let isVowel = CT_JUNG_IDX[jamo] != nil
        if isVowel {
            if live == nil {
                live = .jung(jamo)
            } else if case .cho(let ch) = live! {
                live = .syll(cho: ch, jung: jamo, jong: nil)
            } else if case .jung(let cur) = live! {
                if let m = CT_JUNG_MERGE[cur + jamo] {
                    live = .jung(m)
                } else {
                    ctFlush(live, &out)
                    live = .jung(jamo)
                }
            } else if case .syll(let cho, let jung, let jong) = live! {
                if let jong = jong,
                   let kc = firstSplit(of: jong, table: ctJongSplitTable) {
                    // 겹받침 분해: 앞쪽 받침은 확정, 남은 자음이 새 음절 초성이 되어 모음과 합침
                    if let s = ctComposeSyllable(cho, jung, kc[0]) { out.append(s) }
                    live = .syll(cho: kc[1], jung: jamo, jong: nil)
                } else if jong != nil {
                    // 단일 받침 회수: 모음이 들어오면 받칀이 다음 음절의 초성으로 넘어간다.
                    // 실 IME 동작 — 예) ㅎㅏㅅㅔ → 하|세 (핫ㅔ 아님)
                    if let s = ctComposeSyllable(cho, jung, nil) { out.append(s) }
                    live = .syll(cho: jong!, jung: jamo, jong: nil)
                } else if let m = CT_JUNG_MERGE[jung + jamo] {
                    live = .syll(cho: cho, jung: m, jong: nil)
                } else {
                    ctFlush(live, &out)
                    live = .jung(jamo)
                }
            }
        } else {
            // 자음
            if live == nil {
                live = .cho(jamo)
            } else if case .cho(let cur) = live! {
                if let m = CT_CHO_MERGE[cur + jamo] {
                    live = .cho(m)
                } else {
                    ctFlush(live, &out)
                    live = .cho(jamo)
                }
            } else if case .jung = live! {
                ctFlush(live, &out)
                live = .cho(jamo)
            } else if case .syll(let cho, let jung, let jong) = live! {
                if jong == nil {
                    if CT_JONG_SINGLE.contains(jamo) || CT_JONG_IDX[jamo] != nil {
                        live = .syll(cho: cho, jung: jung, jong: jamo)
                    } else {
                        ctFlush(live, &out)
                        live = .cho(jamo)
                    }
                } else if let m = CT_JONG_MERGE[jong! + jamo] {
                    live = .syll(cho: cho, jung: jung, jong: m)
                } else {
                    ctFlush(live, &out)
                    live = .cho(jamo)
                }
            }
        }
    }
    ctFlush(live, &out)
    return out.joined()
}

/// 겹받침 분해 역산 ( JongSplit )
private let ctJongSplitTable: [String: [String]] = {
    var m: [String: [String]] = [:]
    for (k, v) in CT_JONG_MERGE { m[v] = [String(k.prefix(1)), String(k.suffix(1))] }
    return m
}()

private func firstSplit(of jong: String, table: [String: [String]]) -> [String]? {
    table[jong]
}

/**
 * 문자열을 자모 시퀀스로 분해. 완성형 음절은 초/중/종으로, 호환 자모는 그대로,
 * 그 외 문자(라틴, 숫자 등)는 그대로 둔다.
 */
public func ctDecomposeText(_ text: String) -> [String] {
    var out: [String] = []
    for ch in text {
        guard let s = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
            out.append(String(ch))
            continue
        }
        let n = Int(s.value)
        let isSyll = n >= 0xAC00 && n <= 0xD7A3
        if isSyll {
            let idx = n - 0xAC00
            let cho = CT_CHO[idx / 588]
            let jung = CT_JUNG[(idx % 588) / 28]
            let jong = CT_JONG[idx % 28]
            out.append(cho)
            out.append(jung)
            if let jong = jong { out.append(jong) }
        } else {
            out.append(String(ch))
        }
    }
    return out
}

/// 분해된 시퀀스가 완성형 음절만으로 재조립 가능한지(= roundtrip) 검사용
public func ctRecomposeDecomposed(_ seq: [String]) -> String {
    ctComposeJamo(seq)
}
