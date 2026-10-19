#if os(macOS)
import XCTest
import CatchTypeCore
@testable import CatchTypeApp

final class EventStreamTests: XCTestCase {
    func type(_ text: String, into engine: EventStreamCorrector, at time: Double = 100) {
        for ch in text { _ = engine.handleKey(ctCharToKey(ch)!, timestampMs: time) }
    }

    func testSpaceKeepsCompleteKoreanReplacement() {
        let engine = EventStreamCorrector()
        type("dkssudgktpdy", into: engine)
        let result = engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 200)
        XCTAssertEqual(result?.replacement, "안녕하세요")
        XCTAssertEqual(result?.backspaceCount, 12)
        XCTAssertEqual(result?.tail?.code, "Space")
    }

    func testIdleTimeoutDiscardsWithoutSendingDestructiveEvents() {
        let engine = EventStreamCorrector()
        type("dkssudgktpdy", into: engine)
        engine.expirePending(nowMs: 1400)
        XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 1500))
    }

    func testInterruptionDiscardsPendingInsteadOfDeletingAtNewCursor() {
        let engine = EventStreamCorrector()
        type("dkssudgktpdy", into: engine)
        engine.handlePossibleInterruption()
        XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 1400))
    }

    func testDigitsKeepWholePasswordTokenUnchanged() {
        let engine = EventStreamCorrector()
        for ch in "dkssudgktpdy123!" { _ = engine.handleText(String(ch), timestampMs: 100) }
        XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 200))
    }

    func testPromptHoldExpiresAndNeverCommitsOldInput() {
        let engine = EventStreamCorrector()
        type("dkssudgktpdy", into: engine)
        engine.notePasswordPrompt(line: "[sudo] password:", nowMs: 200)
        XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 300))
        engine.expirePending(nowMs: 9000)
        type("dkssudgktpdy", into: engine, at: 9000)
        XCTAssertEqual(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 9100)?.replacement, "안녕하세요")
    }

    func testSuppressionClearsPendingAndDoesNotLeakIntoNextApp() {
        let engine = EventStreamCorrector()
        type("dkssudgktpdy", into: engine)
        engine.setSuppressed(true)
        XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 1400))
        engine.setSuppressed(false)
        type("dkssudgktpdy", into: engine, at: 1500)
        XCTAssertEqual(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 1600)?.replacement, "안녕하세요")
    }

    func testTimeoutBeforeNextLetterDiscardsInsteadOfDeletingNewInput() {
        let engine = EventStreamCorrector()
        type("dkssudgktpdy", into: engine)
        _ = engine.handleText("a", timestampMs: 2000)
        XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 2100))
    }

    func testShiftDelimiterNeverChangesReverseTabOrMultilineEnter() {
        for code in ["Tab", "Enter", "Space"] {
            let engine = EventStreamCorrector()
            type("dkssudgktpdy", into: engine)
            XCTAssertNil(engine.handleKey(CTKey(code: code, shift: true), timestampMs: 200))
            XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 1400))
        }
    }

    func testMixedSuffixAndCamelCaseSurviveStream() {
        let engine = EventStreamCorrector()
        type("READMEdp", into: engine)
        XCTAssertEqual(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 200)?.replacement, "README에")
        type("Figma", into: engine, at: 300)
        XCTAssertNil(engine.handleKey(CTKey(code: "Space", shift: false), timestampMs: 400))
    }

    func testPromptClassificationAndSecureSubrole() {
        XCTAssertTrue(CTPasswordGuard.isSecure(role: "AXTextField", subrole: "AXSecureTextField", description: "", title: ""))
        XCTAssertTrue(CTPasswordGuard.terminalPromptLooksLikePassword("user@host's password:"))
        XCTAssertTrue(CTPasswordGuard.terminalPromptLooksLikePassword("Enter passphrase for key '/tmp/test':"))
        XCTAssertFalse(CTPasswordGuard.terminalPromptLooksLikePassword("$ echo password"))
    }
}
#endif
