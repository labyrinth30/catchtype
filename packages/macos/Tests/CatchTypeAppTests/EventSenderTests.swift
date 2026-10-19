#if os(macOS)
import XCTest
import CoreGraphics
import CatchTypeCore
@testable import CatchTypeApp

final class EventSenderTests: XCTestCase {
    func testDeletesThenSendsUnicodeThenDelimiterWithTaggedPairs() throws {
        let correction = CTCorrection(backspaceCount: 2, replacement: "안녕", tail: CTKey(code: "Space", shift: false))
        let events = try XCTUnwrap(CTEventSender.events(for: correction))
        XCTAssertEqual(events.count, 10)
        XCTAssertEqual(events.map { $0.type }, [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp])
        XCTAssertEqual(events.prefix(4).map { $0.getIntegerValueField(.keyboardEventKeycode) }, [51, 51, 51, 51])
        var text = ""
        for event in [events[4], events[6]] {
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
            text += String(utf16CodeUnits: chars, count: length)
        }
        XCTAssertEqual(text, "안녕")
        XCTAssertEqual(events[8].getIntegerValueField(.keyboardEventKeycode), 49)
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == CTEventSender.marker })
    }

    func testInvalidReplacementNeverProducesDeleteOnlyEvents() {
        XCTAssertNil(CTEventSender.events(for: .init(backspaceCount: 12, replacement: "", tail: nil)))
        XCTAssertNil(CTEventSender.events(for: .init(backspaceCount: 0, replacement: "안녕", tail: nil)))
        XCTAssertNil(CTEventSender.events(for: .init(backspaceCount: 257, replacement: "안녕", tail: nil)))
        XCTAssertNil(CTEventSender.events(for: .init(backspaceCount: 2, replacement: "안녕", tail: CTKey(code: "Unknown", shift: false))))
    }
}
#endif
