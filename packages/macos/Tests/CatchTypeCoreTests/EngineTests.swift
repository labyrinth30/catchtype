//
//  EngineTests.swift
//  CatchTypeCoreTests
//
//  judgeWord 직접 호출 규약(TS engine.ts v1.1 문서) + 사전 모듈 비교 검증.
//  TS tests/dictionary.test.ts 전수 이식.
//

import XCTest
@testable import CatchTypeCore

final class EngineTests: XCTestCase {
    /// TS 규약: processText는 augmentDicts를 자동 적용하지만, judgeWord 직접 호출자는
    /// 보강본을 직접 넘겨야 한다 — 컴파일 시그니처로 규약을 잠는다.
    func testJudgeWordSignatureAugmentContract() {
        let base = ctLoadBuiltinDicts()
        let ks = "git".compactMap { ctCharToKey($0) }
        let _ = ctJudgeWord(ks, .ko, base)
        // 무보강 사전으로는 'git'이 en 사전 히트로 안 나올 수 있음 — 그러나
        // 보강본으로는 both-alt(basis)로 확실히 잡힌다.
        let aug = ctAugmentDicts(base)
        let augDecision = ctJudgeWord(ks, .ko, aug)
        XCTAssertEqual(augDecision.output, "git")
        XCTAssertEqual(augDecision.reason, "both-alt(basis)")
    }

    func testAugmentIdempotent() {
        let base = ctLoadBuiltinDicts()
        let once = ctAugmentDicts(base)
        let twice = ctAugmentDicts(once)
        XCTAssertEqual(twice.en.words.count, once.en.words.count)
    }

    func testExtraEnWordsPresent() {
        let aug = ctAugmentDicts(ctLoadBuiltinDicts())
        for w in ["git", "npm", "yaml", "json"] {
            XCTAssertNotNil(aug.en.words[w], "missing: \(w)")
        }
    }

    // MARK: - Dictionary module (TS dictionary.test.ts)

    func testDictionaryQueries() {
        let dict = CTDict(lang: .en, entries: [
            ("the", 100), ("of", 90), ("cat", 40), ("cathedral", 10), ("catnip", 5),
        ])
        XCTAssertTrue(dict.hasWord("cat"))
        XCTAssertTrue(dict.hasWord("CAT")) // 영어는 대소문자 무관
        XCTAssertFalse(dict.hasWord("dog"))

        XCTAssertTrue(dict.hasPrefix("cat"))
        XCTAssertTrue(dict.hasPrefix("ca"))
        XCTAssertTrue(dict.hasPrefix("cath"))
        XCTAssertFalse(dict.hasPrefix("cu"))
    }

    func testDictionaryWeights() {
        let dict = CTDict(lang: .en, entries: [
            ("the", 100), ("of", 90), ("cat", 40), ("cathedral", 10), ("catnip", 5),
        ])
        let wThe = dict.weightOf("the")!
        let wCat = dict.weightOf("cat")!
        let wCatnip = dict.weightOf("catnip")!
        XCTAssertTrue(wThe > wCat)
        XCTAssertTrue(wCat > wCatnip)
        XCTAssertEqual(wThe, 1.0, accuracy: 1e-9)
        XCTAssertNil(dict.weightOf("zzz"))
        XCTAssertTrue(dict.weightOf("the")! > dict.weightOf("cathedral")!)
    }

    func testDictionaryDupKeepsMax() {
        let d = CTDict(lang: .en, entries: [("w1", 5), ("w1", 99)])
        XCTAssertEqual(d.words["w1"], 99)
    }

    func testKoreanDictNoCaseNormalize() {
        let ko = CTDict(lang: .ko, entries: [("감사", 500)])
        XCTAssertTrue(ko.hasWord("감사"))
        XCTAssertEqual(ko.size, 1)
    }

    // MARK: - Password guard (TS engine_looksLikePassword)

    func testLooksLikePassword() {
        XCTAssertTrue(ctLooksLikePassword("Tr0ub4dor&3")) // 대소문자+숫자+기호 = 4종
        XCTAssertFalse(ctLooksLikePassword("abc123"))     // 소문자+숫자 = 2종 — 판정 계속
        XCTAssertFalse(ctLooksLikePassword("banana"))     // 1종
        // 규약(engine.ts): 문자 클래스(대/소/숫자/기호) 3종 이상 혼용이면 의심.
        // 'Catch22'는 대+소+숫자 = 3종이라 의심 TRUE가 맞다 (TS와 동일).
        XCTAssertTrue(ctLooksLikePassword("Catch22"))
    }
}
