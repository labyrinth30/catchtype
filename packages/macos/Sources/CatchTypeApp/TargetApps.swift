#if os(macOS)
//
//  TargetApps.swift
//  CatchType
//
//  앱별 토글 — 터미널이 1등 시민(SPEC.md). 목록은 기본 터미널 세트 + 사용자 추가.
//  저장 위치: ~/Library/Application Support/CatchType/config.json
//

import AppKit

struct CTAppEntry: Codable, Equatable {
    var bundleID: String
    var name: String
    var enabled: Bool
}

struct CTAppConfig: Codable {
    var apps: [CTAppEntry] = CTAppConfig.defaultApps
    var initialLang: String = "en"          // 세션 시작 언어 (en|ko)
    var passwordGuard: Bool = true          // AX 비밀번호 필드 방어 on/off
    var terminalPromptGuard: Bool = true    // sudo/ssh 프롬프트 휴리스틱 on/off
    var wordTimeoutMs: Double = 1200
    var menuBarHint: Bool = true            // 상태바 아이콘에 현재 언어 표시
    var logFile: Bool = false               // 디버그 로깅

    static let defaultApps: [CTAppEntry] = [
        .init(bundleID: "com.apple.Terminal",      name: "Terminal",  enabled: true),
        .init(bundleID: "com.googlecode.iterm2",   name: "iTerm2",    enabled: true),
        .init(bundleID: "dev.warp.Warp-Stable",    name: "Warp",      enabled: true),
        .init(bundleID: "com.mitchellh.ghostty",   name: "Ghostty",   enabled: true),
        .init(bundleID: "org.alacritty",           name: "Alacritty", enabled: true),
        .init(bundleID: "net.kovidgoyal.kitty",    name: "kitty",     enabled: true),
        .init(bundleID: "com.github.wez.wezterm",  name: "WezTerm",   enabled: true),
    ]
}

enum CTConfigStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CatchType", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> CTAppConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return CTAppConfig() }
        let decoder = JSONDecoder()
        if let cfg = try? decoder.decode(CTAppConfig.self, from: data) { return cfg }
        // 부분 호환: apps 배열만 읽어 기본설정에 merge
        if let partial = try? decoder.decode([String: [CTAppEntry]].self, from: data),
           let apps = partial["apps"] {
            var cfg = CTAppConfig()
            cfg.apps = apps
            return cfg
        }
        return CTAppConfig()
    }

    static func save(_ cfg: CTAppConfig) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cfg) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 현재 포어그라운드 앱의 bundleID에 대응하는 활성 타겟 여부.
    static func isTargeted(_ cfg: CTAppConfig, bundleID: String) -> Bool {
        cfg.apps.first { $0.bundleID == bundleID }?.enabled ?? false
    }
}

/// 현재 포어그라운드 앱의 bundle ID 조회.
enum CTFrontApp {
    static var currentBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

#endif // os(macOS)
