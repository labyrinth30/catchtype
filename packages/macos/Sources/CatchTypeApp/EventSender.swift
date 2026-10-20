#if os(macOS)
import CoreGraphics
import CatchTypeCore

enum CTEventSender {
    static let marker: Int64 = 0x4354434f52524543

    /// Allocate the entire transaction before sending any destructive backspaces.
    static func events(for correction: CTCorrection) -> [CGEvent]? {
        guard correction.backspaceCount > 0, correction.backspaceCount <= 256,
              !correction.replacement.isEmpty, correction.tail?.shift != true else { return nil }
        let source = CGEventSource(stateID: .privateState)
        var events: [CGEvent] = []
        func append(code: UInt16, text: String? = nil) -> Bool {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return false }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                if let text = text {
                    let chars = Array(text.utf16)
                    event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
                }
                events.append(event)
            }
            return true
        }
        for _ in 0..<correction.backspaceCount { guard append(code: 0x33) else { return nil } }
        for ch in correction.replacement { guard append(code: 0, text: String(ch)) else { return nil } }
        if let tail = correction.tail {
            guard let code = CT_KVK_ANSI[tail.code], append(code: code) else { return nil }
        }
        return events
    }

    static func send(_ correction: CTCorrection, proxy: CGEventTapProxy) -> Bool {
        guard let events = events(for: correction) else { return false }
        for event in events {
            event.tapPostEvent(proxy)
        }
        return true
    }
}
#endif
