//
//  HangulTests.swift
//  CatchTypeCoreTests
//
//  TS engine tests/hangul.test.ts의 전수 이식 + 11,172 완성형 roundtrip.
//

import XCTest
@testable import CatchTypeCore

final class HangulTests: XCTestCase {
    func testComposeSyllableBasic() {
        XCTAssertEqual(ctComposeSyllable("ㅇ", "ㅏ", "ㄴ"), "안")
        XCTAssertEqual(ctComposeSyllable("ㄱ", "ㅏ", nil), "가")
        XCTAssertNil(ctComposeSyllable("x", "y", nil))
    }

    func testComposeSingleJamo() {
        XCTAssertEqual(ctComposeJamo(["ㅇ", "ㅏ", "ㄴ"]), "안")
        XCTAssertEqual(ctComposeJamo(["ㄱ", "ㅏ", "ㅁ"]), "감")
        XCTAssertEqual(ctComposeJamo(["ㅎ", "ㅏ", "ㄴ", "ㄱ", "ㅡ", "ㄹ"]), "한글")
    }

    func testFinalRecycleOnVowel() {
        XCTAssertEqual(ctComposeJamo(["ㅎ", "ㅏ", "ㅅ", "ㅔ", "ㅇ", "ㅛ"]), "하세요")
        XCTAssertEqual(ctComposeJamo(["ㅇ", "ㅏ", "ㄴ", "ㄴ", "ㅕ", "ㅇ"]), "안녕")
    }

    func testCompoundVowelMerge() {
        XCTAssertEqual(ctComposeJamo(["ㅇ", "ㅗ", "ㅏ"]), "와")
        XCTAssertEqual(ctComposeJamo(["ㅂ", "ㅜ", "ㅓ"]), "붜")
        XCTAssertEqual(ctComposeJamo(["ㅎ", "ㅗ", "ㅣ"]), "회")
        XCTAssertEqual(ctComposeJamo(["ㅂ", "ㅜ", "ㅓ", "ㄱ"]), "붝")
        XCTAssertEqual(ctComposeJamo(["ㅂ", "ㅜ", "ㄱ", "ㅓ"]), "부거")
    }

    func testDoubleBatchimSplit() {
        XCTAssertEqual(ctComposeJamo(["ㅇ", "ㅣ", "ㄹ", "ㄱ", "ㅣ"]), "일기")
        XCTAssertEqual(ctComposeJamo(["ㅇ", "ㅜ", "ㄹ", "ㅁ", "ㅏ", "ㄴ"]), "울만")
    }

    func testDoubleCho() {
        XCTAssertEqual(ctComposeJamo(["ㄱ", "ㄱ", "ㅏ"]), "까")
        XCTAssertEqual(ctComposeJamo(["ㅅ", "ㅅ", "ㅏ"]), "싸")
    }

    func testConsecutiveConsonants() {
        XCTAssertEqual(ctComposeJamo(["ㄱ", "ㅏ", "ㅂ", "ㅅ"]), "값")
        XCTAssertEqual(ctComposeJamo(["ㄱ", "ㅏ", "ㄴ", "ㅏ"]), "가나")
    }

    func testStandaloneJamo() {
        XCTAssertEqual(ctComposeJamo(["ㄱ"]), "ㄱ")
        XCTAssertEqual(ctComposeJamo(["ㅋ", "ㅋ", "ㄋ"]), "ㅋㅋㄋ")
        XCTAssertEqual(ctComposeJamo(["ㅋ", "ㅋ"]), "ㅋㅋ")
    }

    func testDecomposeBasic() {
        XCTAssertEqual(ctDecomposeText("한"), ["ㅎ", "ㅏ", "ㄴ"])
        XCTAssertEqual(ctDecomposeText("가"), ["ㄱ", "ㅏ"])
    }

    func testDecomposeLatinUntouched() {
        XCTAssertEqual(ctDecomposeText("ab1!"), ["a", "b", "1", "!"])
    }

    func testDecomposeComplexJong() {
        XCTAssertEqual(ctDecomposeText("흙"), ["ㅎ", "ㅡ", "ㄺ"])
    }

    /// TS hangul.test.ts 핵심: 전체 11,172 완성형 roundtrip — compose∘decompose = id.
    func testFullSyllableRoundtrip() {
        var failures: [String] = []
        for c in CT_CHO {
            for v in CT_JUNG {
                for t in CT_JONG {
                    let s = ctComposeSyllable(c, v, t)
                    XCTAssertNotNil(s, "compose failed: \(c)\(v)\(t ?? "-")")
                    guard let syll = s else { continue }
                    let back = ctComposeJamo(ctDecomposeText(syll))
                    if back != syll {
                        failures.append("\(syll): \(ctDecomposeText(syll).joined(separator: ",")) -> \(back)")
                        if failures.count > 5 { XCTFail("roundtrip failures: \(failures)"); return }
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "roundtrip failures: \(failures.prefix(5))")
    }

    func testIsHangulSyllable() {
        XCTAssertTrue(ctIsHangulSyllable("가"))
        XCTAssertFalse(ctIsHangulSyllable("a"))
        XCTAssertFalse(ctIsHangulSyllable("ㄱ"))
    }
}
