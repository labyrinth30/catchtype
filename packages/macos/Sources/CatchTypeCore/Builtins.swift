//
//  Builtins.swift
//  CatchTypeCore
//
//  내장 데이터 로더 — TS engine (packages/engine/src/builtin.ts)의 이식.
//  데이터는 Datasets.generated.swift에 소스 임베드되어 있으므로 파일 I/O가 없다
//  (앱 샌드박스·번들 어디서든 동일 동작). 캐싱됨.
//

import Foundation

private func ctSplitLines(_ blob: String) -> [String] {
    var lines: [String] = []
    var cur = ""
    for ch in blob.unicodeScalars {
        if ch == "\n" {
            lines.append(cur)
            cur = ""
        } else {
            cur.unicodeScalars.append(ch)
        }
    }
    if !cur.isEmpty { lines.append(cur) }
    // 마지막 개행 뒤 빈 줄 제거 — TS builtin.ts가 split('\\n') 후 빈 줄을 skip하는 것과 동일 결과
    return lines
}

private func ctParseTsvBlob(_ blob: String) -> [(String, Double)] {
    var entries: [(String, Double)] = []
    for line in ctSplitLines(blob) {
        if line.isEmpty { continue }
        guard let tab = line.firstIndex(of: "\t") else { continue }
        let w = String(line[..<tab])
        let f = Double(line[line.index(after: tab)...]) ?? 0
        entries.append((w, f.isFinite ? f : 0))
    }
    return entries
}

private func ctParseBigramsBlob(_ blob: String) -> Set<String> {
    Set(ctSplitLines(blob).filter { !$0.isEmpty })
}

private enum CTBuiltinCache {
    static var cached: CTDicts?
}

/// 내장 데이터셋을 판정 자료(CTDicts)로 구성. 캐싱됨 — 프로세스당 1회 빌드.
public func ctLoadBuiltinDicts() -> CTDicts {
    if let cached = CTBuiltinCache.cached { return cached }
    let ds = ctBuiltinDataset
    let dicts = CTDicts(
        ko: CTDict(lang: .ko, entries: ctParseTsvBlob(ds.koWordsRaw)),
        en: CTDict(lang: .en, entries: ctParseTsvBlob(ds.enWordsRaw)),
        koBigrams: ctParseBigramsBlob(ds.koBigramsRaw)
    )
    CTBuiltinCache.cached = dicts
    return dicts
}

/// 편의: 내장 사전 + v1.1 보강까지 적용된 CTDicts (macOS 셸 권용법).
/// TS 규약 주의문 그대로: judgeWord 직접 호출자는 보강본을 넘겨야 한다.
public func ctLoadAugmentedBuiltinDicts() -> CTDicts {
    ctAugmentDicts(ctLoadBuiltinDicts())
}
