//
//  Dictionary.swift
//  CatchTypeCore
//
//  사전 모듈 — TS engine (packages/engine/src/dictionary.ts)의 전수 이식.
//  순수 자료구조. 판정 질의: hasWord / hasPrefix / weightOf.
//  규약: 값이 클수록 흔한 단어(EN은 순위를 역산 저장). weights는 0~1 정규 빈도.
//

import Foundation

public struct CTDict {
    public let lang: CTLang
    /// word → 빈도(또는 순위)
    public let words: [String: Double]
    /// 오름차순 정렬된 단어 배열(접두어 이분 탐색용)
    public let sorted: [String]
    /// word → 0~1 정규 빈도 가중치(최빈도 단어 = 1). 값 내림차순 순위 기반.
    public let weights: [String: Double]

    public init(lang: CTLang, entries: [(String, Double)]) {
        self.lang = lang
        var words: [String: Double] = [:]
        for (raw, freq) in entries {
            let w = CTDictionary.norm(lang, raw)
            if w.isEmpty { continue }
            let prev = words[w]
            if prev == nil || freq > prev! { words[w] = freq }
        }
        self.words = words
        self.sorted = words.keys.sorted { $0 < $1 }
        // 규약: 값이 클수록 흔한 단어. 내림차순 순위 기반 0~1 가중치.
        let byFreq = words.sorted { $0.value > $1.value }
        let n = byFreq.count
        var weights: [String: Double] = [:]
        for (i, kv) in byFreq.enumerated() { weights[kv.key] = (Double(n - i) / Double(n)) }
        self.weights = weights
    }

    func norm(_ w: String) -> String { CTDictionary.norm(lang, w) }
}

enum CTDictionary {
    static func norm(_ lang: CTLang, _ w: String) -> String {
        lang == .en ? w.lowercased() : w
    }
}

extension CTDict {
    public func hasWord(_ w: String) -> Bool {
        words[norm(w)] != nil
    }

    /** 사전에 w를 접두어로 갖는 단어가 존재하는가(타이핑 도중 판정용) — 이분 탐색 */
    public func hasPrefix(_ w: String) -> Bool {
        let t = norm(w)
        if t.isEmpty { return false }
        var lo = 0
        var hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        return lo < sorted.count && sorted[lo].hasPrefix(t)
    }

    /// 빈도 가중치(0~1). 없는 단어는 nil.
    public func weightOf(_ w: String) -> Double? {
        weights[norm(w)]
    }

    public var size: Int { words.count }
}
