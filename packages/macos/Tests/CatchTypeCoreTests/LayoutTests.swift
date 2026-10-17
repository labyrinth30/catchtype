//
//  LayoutTests.swift
//  CatchTypeCoreTests
//
//  TS engine tests/layout.test.ts의 전수 이식.
//

import XCTest
@testable import CatchTypeCore

final class LayoutTests: XCTestCase {
    func testTwoBulsikMap() {
        XCTAssertEqual(CT_EN_CHAR_TO_KO["r"], "ㄱ")
        XCTAssertEqual(CT_EN_CHAR_TO_KO["k"], "ㅏ")
        XCTAssertEqual(CT_EN_CHAR_TO_KO["o"], "ㅐ")
        XCTAssertEqual(CT_EN_CHAR_TO_KO["p"], "ㅔ")
        XCTAssertEqual(CT_EN_CHAR_TO_KO["q"], "ㅂ")
        XCTAssertEqual(CT_EN_SHIFT_TO_KO["r"], "ㄲ")
        XCTAssertEqual(CT_EN_SHIFT_TO_KO["q"], "ㅃ")
        XCTAssertEqual(CT_EN_SHIFT_TO_KO["o"], "ㅒ")
        XCTAssertEqual(CT_EN_SHIFT_TO_KO["p"], "ㅖ")
    }

    func testShiftNoOpKeys() {
        XCTAssertEqual(ctKeyToJamo(ctCharToKey("a")!), "ㅁ")
        XCTAssertEqual(ctKeyToJamo(ctCharToKey("A")!), "ㅁ")
    }

    func testReverseMap() {
        for (en, jamo) in CT_EN_CHAR_TO_KO {
            XCTAssertEqual(CT_KO_CHAR_TO_EN[jamo], en, "jamo \(jamo)")
        }
        XCTAssertEqual(CT_KO_CHAR_TO_EN["ㄲ"], "R")
        XCTAssertEqual(CT_KO_CHAR_TO_EN["ㅖ"], "P")
    }

    func testCharKeyRoundtrip() {
        for ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let k = ctCharToKey(Character(String(ch)))
            XCTAssertNotNil(k, "charToKey fail: \(ch)")
            XCTAssertEqual(ctKeyToLatin(k!), String(ch))
        }
        XCTAssertNil(ctCharToKey("1"))
        XCTAssertNil(ctCharToKey("!"))
    }

    func testKVKANSIValues() {
        XCTAssertEqual(CT_KVK_ANSI["KeyA"], 0x00)
        XCTAssertEqual(CT_KVK_ANSI["Space"], 0x31)
        XCTAssertEqual(CT_KVK_ANSI["Enter"], 0x24)
        XCTAssertEqual(CT_KVK_ANSI["Backspace"], 0x33)
    }

    func testDkssudgktpdyJamoSeq() {
        let seq = "dkssudgktpdy".compactMap { ctKeyToJamo(ctCharToKey($0)!) }
        XCTAssertEqual(seq.joined(), "ㅇㅏㄴㄴㅕㅇㅎㅏㅅㅔㅇㅛ")
    }
}
