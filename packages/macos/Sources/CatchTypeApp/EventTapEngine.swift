#if os(macOS)
import Foundation
import CatchTypeCore

struct CTCorrection: Equatable {
    let backspaceCount: Int
    let replacement: String
    let tail: CTKey?
}

/// Only uninterrupted ASCII words are rewritten; cursor edits and opaque tokens pass through.
final class EventStreamCorrector {
    struct Config {
        var initialLang: CTLang = .en
        var wordTimeoutMs: Double = 1200
        var maxRewriteLength = 24
    }
    var config: Config
    private(set) var sessionLang: CTLang
    private let dicts = ctLoadAugmentedBuiltinDicts()
    private var raw = ""
    private var opaqueToken = false
    private var lastEventMs: Double = 0
    private var suppressed = false
    private var promptHoldUntil: Double = 0

    init(config: Config = Config()) {
        self.config = config
        sessionLang = config.initialLang
    }

    func setSuppressed(_ value: Bool) {
        if value { handlePossibleInterruption() }
        suppressed = value
    }

    func notePasswordPrompt(line: String, nowMs: Double) {
        guard CTPasswordGuard.terminalPromptLooksLikePassword(line) else { return }
        promptHoldUntil = nowMs + 8000
        handlePossibleInterruption()
    }

    func handleText(_ text: String, timestampMs: Double) -> CTCorrection? {
        guard !suppressed, timestampMs >= promptHoldUntil else {
            handlePossibleInterruption()
            return nil
        }
        // A timer delayed past the next real keystroke must not erase that new keystroke.
        if lastEventMs > 0, timestampMs - lastEventMs > config.wordTimeoutMs {
            handlePossibleInterruption()
        }
        lastEventMs = timestampMs
        guard text.count == 1, let ch = text.first, ctCharToKey(ch) != nil,
              raw.count < 256 else {
            raw = ""
            opaqueToken = true
            return nil
        }
        if !opaqueToken { raw += text }
        return nil
    }

    func handleKey(_ key: CTKey, timestampMs: Double) -> CTCorrection? {
        if ["Space", "Enter", "Tab"].contains(key.code) {
            defer {
                raw = ""
                opaqueToken = false
                lastEventMs = 0
            }
            guard !key.shift, !suppressed, timestampMs >= promptHoldUntil else { return nil }
            return commit(tail: key)
        }
        return handleText(ctKeyToLatin(key), timestampMs: timestampMs)
    }

    func expirePending(nowMs: Double) {
        if lastEventMs > 0, nowMs - lastEventMs > config.wordTimeoutMs {
            handlePossibleInterruption()
        }
    }

    func handlePossibleInterruption() {
        raw = ""
        // An interruption can leave the cursor inside a word; wait for a known boundary.
        opaqueToken = true
        lastEventMs = 0
    }

    private func commit(tail: CTKey?) -> CTCorrection? {
        guard !opaqueToken, !raw.isEmpty else { return nil }
        let result = ctProcessText(raw, initialLang: sessionLang, dicts: dicts)
        sessionLang = result.finalLang
        guard !result.passwordSuspect, result.text != raw,
              result.text.count <= config.maxRewriteLength else { return nil }
        return CTCorrection(backspaceCount: raw.count, replacement: result.text, tail: tail)
    }
}
#endif
