//
//  catchtype.swift (CLI executable)
//  catchtype-macos
//
//  잘못된 상태로 두벌식/QWERTY 섞어 친 입력을 교정하는 CLI.
//  packages/cli/src/catchtype.ts와 동일 플래그:
//
//  usage:
//    echo "dkssudgktpdy" | catchtype           # → 안녕하세요
//    echo "AIfh hello"   | catchtype --start ko
//    catchtype --debug   < input.txt           # 단어별 판정 근거 출력
//    catchtype --password-skip < passwords.txt  # 비밀번호 의심 토큰 통과 플래그
//
//  flags:
//    --start <ko|en>   시작 언어 상태 (기본 en)
//    --debug           단어별 판정 JSON을 stderr로
//    --password-skip   비밀번호 의심 토큰을 그대로 통과하고 exit code 3
//                      (기본 동작이기도 함 — 플래그는 문서화/확인용)
//    --augment / --no-augment   개발 용어 사전 보강(기본 on)
//    --help
//

import Foundation
import CatchTypeCore

struct CTCliOptions {
    var start: CTLang = .en
    var debug = false
    var passwordSkip = false
    var noAugment = false
    var help = false
}

func ctParseArgs(_ argv: [String]) -> CTCliOptions {
    var opts = CTCliOptions()
    var i = 0
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--start":
            i += 1
            if i < argv.count, argv[i] == "ko" { opts.start = .ko } else { opts.start = .en }
        case "--debug":
            opts.debug = true
        case "--password-skip":
            opts.passwordSkip = true
        case "--no-augment":
            opts.noAugment = true
        case "--augment":
            opts.noAugment = false
        case "--help", "-h":
            opts.help = true
        default:
            break // 알 수 없는 플래그는 무시(TS CLI와 동일)
        }
        i += 1
    }
    return opts
}

func ctCliHelp() -> String {
    """
    catchtype — 한/영 상태 자동 교정 CLI
    usage: catchtype [--start ko|en] [--debug] [--password-skip] [--no-augment] < input
    """
}

func ctDebugLines(_ result: CTEngineResult) -> [String] {
    var lines: [String] = []
    for w in result.words {
        var segsDesc = "null"
        if let segs = w.segments {
            segsDesc = "[" + segs.map { s in
                "{\"raw\":\"\(s.raw)\",\"lang\":\"\(s.lang.rawValue)\",\"text\":\"\(s.text)\",\"basis\":\"\(s.basis)\",\"confidence\":\(s.confidence)}"
            }.joined(separator: ",") + "]"
        }
        let conf = (w.confidence * 100).rounded() / 100
        lines.append("" +
            "{\"raw\":\"\(w.raw)\",\"output\":\"\(w.output)\",\"lang\":\"\(w.lang.rawValue)\"," +
            "\"switched\":\(w.switched ? "true" : "false"),\"reason\":\"\(w.reason)\"," +
            "\"confidence\":\(conf),\"segments\":\(segsDesc)}")
    }
    lines.append("{\"initialLang\":\"\(result.initialLang.rawValue)\",\"finalLang\":\"\(result.finalLang.rawValue)\"}")
    return lines
}

func ctMain() -> Int32 {
    let argv = Array(CommandLine.arguments.dropFirst())
    let opts = ctParseArgs(argv)
    if opts.help {
        FileHandle.standardOutput.write(Data(ctCliHelp().appending("\n").utf8))
        return 0
    }

    guard let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) else {
        FileHandle.standardError.write(Data("[catchtype] stdin is not valid UTF-8\n".utf8))
        return 2
    }

    let dicts = ctLoadBuiltinDicts()
    // TS 규약: processText는 기본 적용 — CLI도 동일 (augmentDicts 자동).
    let result = ctProcessText(input, initialLang: opts.start, dicts: dicts, noAugment: opts.noAugment)

    if opts.debug {
        for line in ctDebugLines(result) {
            FileHandle.standardError.write(Data(line.appending("\n").utf8))
        }
    }

    FileHandle.standardOutput.write(Data(result.text.utf8))
    if opts.passwordSkip && result.passwordSuspect {
        FileHandle.standardError.write(Data("\n[catchtype] password-suspect tokens passed through unjudged\n".utf8))
        return 3
    }
    return 0
}

// 진입점 — 상태바 앱과 독립 실행하는 CLI 전용 타깃.
_ = { exit(ctMain()) }()
