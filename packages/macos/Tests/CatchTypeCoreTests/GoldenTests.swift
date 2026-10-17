//
//  GoldenTests.swift
//  CatchTypeCoreTests
//
//  골든 벡터 회귀 — TS engine(processText, v1.1.1)을 bun으로 실제 실행해 뽑은
//  81개 검증 벡터(processText 입출력 + 단어 reason + mixed segments)를 그대로 비교.
//  벡터 재생성: packages/macos/Scripts/rebuild-golden.ts (bun) → 이 파일의 goldens 배열 갱신.
//
//  소스 진실(source of truth)은 TS 엔진 — 이 테스트는 Swift 포트가 동일 판정을
//  내는지 잠그는 회귀 장치. 벡터를 손으로 고치지 말고 TS 실행 결과로 갱신한다.
//

import XCTest
@testable import CatchTypeCore

fileprivate struct GoldenSegment: Equatable {
    var lang: String
    var text: String
    var basis: String
}

fileprivate struct GoldenWord: Equatable {
    var raw: String
    var output: String
    var lang: String
    var reason: String
    var segments: [GoldenSegment]?
}

fileprivate struct Golden {
    var state: String
    var input: String
    var text: String
    var finalLang: String
    var passwordSuspect: Bool
    var words: [GoldenWord]

    init(state: String, input: String, text: String, finalLang: String,
         passwordSuspect: Bool = false, words: [GoldenWord]) {
        self.state = state
        self.input = input
        self.text = text
        self.finalLang = finalLang
        self.passwordSuspect = passwordSuspect
        self.words = words
    }
}

final class GoldenTests: XCTestCase {
    fileprivate static let goldens: [Golden] = [
    Golden(state: "en", input: "dkssudgktpdy", text: "안녕하세요", finalLang: "ko", words: [
        .init(raw: "dkssudgktpdy", output: "안녕하세요", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "dmlwk", text: "의자", finalLang: "ko", words: [
        .init(raw: "dmlwk", output: "의자", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "dpfj", text: "에러", finalLang: "ko", words: [
        .init(raw: "dpfj", output: "에러", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "banana", text: "banana", finalLang: "en", words: [
        .init(raw: "banana", output: "banana", lang: "en", reason: "both-keep(basis)", segments: nil)
    ]),
    Golden(state: "ko", input: "banana", text: "banana", finalLang: "en", words: [
        .init(raw: "banana", output: "banana", lang: "en", reason: "both-alt(basis)", segments: nil)
    ]),
    Golden(state: "ko", input: "music", text: "music", finalLang: "en", words: [
        .init(raw: "music", output: "music", lang: "en", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "ko", input: "server", text: "server", finalLang: "en", words: [
        .init(raw: "server", output: "server", lang: "en", reason: "both-alt(basis)", segments: nil)
    ]),
    Golden(state: "en", input: "go", text: "go", finalLang: "en", words: [
        .init(raw: "go", output: "go", lang: "en", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "ko", input: "go", text: "해", finalLang: "ko", words: [
        .init(raw: "go", output: "해", lang: "ko", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "en", input: "to", text: "to", finalLang: "en", words: [
        .init(raw: "to", output: "to", lang: "en", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "en", input: "so", text: "so", finalLang: "en", words: [
        .init(raw: "so", output: "so", lang: "en", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "en", input: "do", text: "do", finalLang: "en", words: [
        .init(raw: "do", output: "do", lang: "en", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "en", input: "an", text: "an", finalLang: "en", words: [
        .init(raw: "an", output: "an", lang: "en", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "en", input: "ah", text: "ah", finalLang: "en", words: [
        .init(raw: "ah", output: "ah", lang: "en", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "en", input: "dp", text: "에", finalLang: "ko", words: [
        .init(raw: "dp", output: "에", lang: "ko", reason: "both-alt(freq)", segments: nil)
    ]),
    Golden(state: "en", input: "AIfh", text: "AI로", finalLang: "ko", words: [
        .init(raw: "AIfh", output: "AI로", lang: "ko", reason: "mixed", segments: [.init(lang: "en", text: "AI", basis: "dict"), .init(lang: "ko", text: "로", basis: "dict")])
    ]),
    Golden(state: "en", input: "testeh", text: "test도", finalLang: "ko", words: [
        .init(raw: "testeh", output: "test도", lang: "ko", reason: "mixed", segments: [.init(lang: "en", text: "test", basis: "dict"), .init(lang: "ko", text: "도", basis: "dict")])
    ]),
    Golden(state: "ko", input: "testeh", text: "ㅅㄷㄴㅅ도", finalLang: "ko", words: [
        .init(raw: "testeh", output: "ㅅㄷㄴㅅ도", lang: "ko", reason: "stats", segments: nil)
    ]),
    Golden(state: "en", input: "READMEdp", text: "README에", finalLang: "ko", words: [
        .init(raw: "READMEdp", output: "README에", lang: "ko", reason: "mixed", segments: [.init(lang: "en", text: "README", basis: "fallback"), .init(lang: "ko", text: "에", basis: "dict")])
    ]),
    Golden(state: "en", input: "READMEdp 설치", text: "README에 설치", finalLang: "ko", words: [
        .init(raw: "READMEdp", output: "README에", lang: "ko", reason: "mixed", segments: [.init(lang: "en", text: "README", basis: "fallback"), .init(lang: "ko", text: "에", basis: "dict")])
    ]),
    Golden(state: "en", input: "tehst", text: "ㅅ돈ㅅ", finalLang: "ko", words: [
        .init(raw: "tehst", output: "ㅅ돈ㅅ", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "ko", input: "TODO", text: "TODO", finalLang: "en", words: [
        .init(raw: "TODO", output: "TODO", lang: "en", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "ko", input: "DP", text: "예", finalLang: "ko", words: [
        .init(raw: "DP", output: "예", lang: "ko", reason: "both-keep", segments: nil)
    ]),
    Golden(state: "ko", input: "npm", text: "npm", finalLang: "en", words: [
        .init(raw: "npm", output: "npm", lang: "en", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "ko", input: "git npm ls 돌리기", text: "git npm ls 돌리기", finalLang: "en", words: [
        .init(raw: "git", output: "git", lang: "en", reason: "both-alt(basis)", segments: nil),
        .init(raw: "npm", output: "npm", lang: "en", reason: "dict", segments: nil),
        .init(raw: "ls", output: "ls", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "Figma 링크 보내드릴게요", text: "Figma 링크 보내드릴게요", finalLang: "ko", words: [
        .init(raw: "Figma", output: "Figma", lang: "ko", reason: "fallback", segments: nil)
    ]),
    Golden(state: "en", input: "Figma fldzm qhsoemflfrpdy", text: "Figma 링크 보내드릴게요", finalLang: "ko", words: [
        .init(raw: "Figma", output: "Figma", lang: "en", reason: "fallback", segments: nil),
        .init(raw: "fldzm", output: "링크", lang: "ko", reason: "alt-hit", segments: nil),
        .init(raw: "qhsoemflfrpdy", output: "보내드릴게요", lang: "ko", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "GitHub에서 PR 날렸어", text: "GitHub에서 PR 날렸어", finalLang: "en", passwordSuspect: true, words: [
        .init(raw: "GitHub에서", output: "GitHub에서", lang: "en", reason: "password-suspect", segments: nil),
        .init(raw: "PR", output: "PR", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "Zoo에 갔어", text: "Zoo에 갔어", finalLang: "en", passwordSuspect: true, words: [
        .init(raw: "Zoo에", output: "Zoo에", lang: "en", reason: "password-suspect", segments: nil)
    ]),
    Golden(state: "en", input: "TODO 확인해줘", text: "TODO 확인해줘", finalLang: "en", words: [
        .init(raw: "TODO", output: "TODO", lang: "en", reason: "acronym", segments: nil)
    ]),
    Golden(state: "en", input: "notion에서 페이지 복사해줘", text: "notion에서 페이지 복사해줘", finalLang: "en", words: [
        .init(raw: "notion", output: "notion", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "Slack으로 공유해", text: "Slack으로 공유해", finalLang: "en", passwordSuspect: true, words: [
        .init(raw: "Slack으로", output: "Slack으로", lang: "en", reason: "password-suspect", segments: nil)
    ]),
    Golden(state: "ko", input: "Google Drive 백업", text: "Google Drive 백업", finalLang: "en", words: [
        .init(raw: "Google", output: "Google", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "Drive", output: "Drive", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "Zoo animals", text: "Zoo animals", finalLang: "en", words: [
        .init(raw: "Zoo", output: "Zoo", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "animals", output: "animals", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "Hello world", text: "Hello world", finalLang: "en", words: [
        .init(raw: "Hello", output: "Hello", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "world", output: "world", lang: "en", reason: "both-keep(basis)", segments: nil)
    ]),
    Golden(state: "ko", input: "hello", text: "hello", finalLang: "en", words: [
        .init(raw: "hello", output: "hello", lang: "en", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "ko", input: "hello world how are you", text: "hello world how are you", finalLang: "en", words: [
        .init(raw: "hello", output: "hello", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "world", output: "world", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "how", output: "how", lang: "en", reason: "dict", segments: nil),
        .init(raw: "are", output: "are", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "you", output: "you", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "hello world how are you", text: "hello world how are you", finalLang: "en", words: [
        .init(raw: "hello", output: "hello", lang: "en", reason: "dict", segments: nil),
        .init(raw: "world", output: "world", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "how", output: "how", lang: "en", reason: "dict", segments: nil),
        .init(raw: "are", output: "are", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "you", output: "you", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "the banana is music", text: "the banana is music", finalLang: "en", words: [
        .init(raw: "the", output: "the", lang: "en", reason: "both-alt(basis)", segments: nil),
        .init(raw: "banana", output: "banana", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "is", output: "is", lang: "en", reason: "dict", segments: nil),
        .init(raw: "music", output: "music", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "I love this song", text: "I love this song", finalLang: "en", words: [
        .init(raw: "I", output: "I", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "love", output: "love", lang: "en", reason: "dict", segments: nil),
        .init(raw: "this", output: "this", lang: "en", reason: "dict", segments: nil),
        .init(raw: "song", output: "song", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "asdf", text: "ㅁㄴㅇㄹ", finalLang: "ko", words: [
        .init(raw: "asdf", output: "ㅁㄴㅇㄹ", lang: "ko", reason: "stats", segments: nil)
    ]),
    Golden(state: "ko", input: "zxcv", text: "ㅋㅌㅊㅍ", finalLang: "ko", words: [
        .init(raw: "zxcv", output: "ㅋㅌㅊㅍ", lang: "ko", reason: "jamo-run", segments: nil)
    ]),
    Golden(state: "en", input: "gggg", text: "ㅎㅎㅎㅎ", finalLang: "ko", words: [
        .init(raw: "gggg", output: "ㅎㅎㅎㅎ", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "ko", input: "gggg", text: "ㅎㅎㅎㅎ", finalLang: "ko", words: [
        .init(raw: "gggg", output: "ㅎㅎㅎㅎ", lang: "ko", reason: "jamo-run", segments: nil)
    ]),
    Golden(state: "ko", input: "aass", text: "ㅁㅁㄴㄴ", finalLang: "ko", words: [
        .init(raw: "aass", output: "ㅁㅁㄴㄴ", lang: "ko", reason: "stats", segments: nil)
    ]),
    Golden(state: "en", input: "qqqq", text: "ㅃㅃ", finalLang: "ko", words: [
        .init(raw: "qqqq", output: "ㅃㅃ", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "zzqq", text: "zzqq", finalLang: "en", words: [
        .init(raw: "zzqq", output: "zzqq", lang: "en", reason: "fallback", segments: nil)
    ]),
    Golden(state: "ko", input: "zzqq", text: "ㅋㅋㅃ", finalLang: "ko", words: [
        .init(raw: "zzqq", output: "ㅋㅋㅃ", lang: "ko", reason: "jamo-run", segments: nil)
    ]),
    Golden(state: "en", input: "my dp profile", text: "my 에 profile", finalLang: "en", words: [
        .init(raw: "my", output: "my", lang: "en", reason: "dict", segments: nil),
        .init(raw: "dp", output: "에", lang: "ko", reason: "both-alt(freq)", segments: nil),
        .init(raw: "profile", output: "profile", lang: "en", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "Tr0ub4dor&3 next", text: "Tr0ub4dor&3 next", finalLang: "en", passwordSuspect: true, words: [
        .init(raw: "Tr0ub4dor&3", output: "Tr0ub4dor&3", lang: "en", reason: "password-suspect", segments: nil),
        .init(raw: "next", output: "next", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "abc123", text: "abc123", finalLang: "en", words: [
        .init(raw: "abc", output: "abc", lang: "en", reason: "both-keep(basis)", segments: nil)
    ]),
    Golden(state: "en", input: "123 !@#", text: "123 !@#", finalLang: "en", words: [

    ]),
    Golden(state: "ko", input: "123 !@#", text: "123 !@#", finalLang: "ko", words: [

    ]),
    Golden(state: "ko", input: "a fickme", text: "a fickme", finalLang: "en", words: [
        .init(raw: "a", output: "a", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "fickme", output: "fickme", lang: "en", reason: "fallback", segments: nil)
    ]),
    Golden(state: "ko", input: "its fsoj", text: "its fsoj", finalLang: "en", words: [
        .init(raw: "its", output: "its", lang: "en", reason: "both-alt(basis)", segments: nil),
        .init(raw: "fsoj", output: "fsoj", lang: "en", reason: "fallback", segments: nil)
    ]),
    Golden(state: "ko", input: "yaml 파싱", text: "yaml 파싱", finalLang: "en", words: [
        .init(raw: "yaml", output: "yaml", lang: "en", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "ko", input: "git commit", text: "git commit", finalLang: "en", words: [
        .init(raw: "git", output: "git", lang: "en", reason: "both-alt(basis)", segments: nil),
        .init(raw: "commit", output: "commit", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "npm install", text: "npm install", finalLang: "en", words: [
        .init(raw: "npm", output: "npm", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "install", output: "install", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "npm testeh dmlwk", text: "npm test도 의자", finalLang: "ko", words: [
        .init(raw: "npm", output: "npm", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "testeh", output: "test도", lang: "ko", reason: "mixed", segments: [.init(lang: "en", text: "test", basis: "dict"), .init(lang: "ko", text: "도", basis: "dict")]),
        .init(raw: "dmlwk", output: "의자", lang: "ko", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "hello world how are you", text: "hello world how are you", finalLang: "en", words: [
        .init(raw: "hello", output: "hello", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "world", output: "world", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "how", output: "how", lang: "en", reason: "dict", segments: nil),
        .init(raw: "are", output: "are", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "you", output: "you", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "ko", input: "please send me the file", text: "please send me the file", finalLang: "en", words: [
        .init(raw: "please", output: "please", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "send", output: "send", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "me", output: "me", lang: "en", reason: "dict", segments: nil),
        .init(raw: "the", output: "the", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "file", output: "file", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "please send me the file", text: "please send me the file", finalLang: "en", words: [
        .init(raw: "please", output: "please", lang: "en", reason: "dict", segments: nil),
        .init(raw: "send", output: "send", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "me", output: "me", lang: "en", reason: "dict", segments: nil),
        .init(raw: "the", output: "the", lang: "en", reason: "both-keep(basis)", segments: nil),
        .init(raw: "file", output: "file", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "", text: "", finalLang: "en", words: [

    ]),
    Golden(state: "ko", input: "dkssudgktpdy", text: "안녕하세요", finalLang: "ko", words: [
        .init(raw: "dkssudgktpdy", output: "안녕하세요", lang: "ko", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "hello", text: "hello", finalLang: "en", words: [
        .init(raw: "hello", output: "hello", lang: "en", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "rlekflek", text: "기다리다", finalLang: "ko", words: [
        .init(raw: "rlekflek", output: "기다리다", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "tkfkd", text: "사랑", finalLang: "ko", words: [
        .init(raw: "tkfkd", output: "사랑", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "sksms", text: "나는", finalLang: "ko", words: [
        .init(raw: "sksms", output: "나는", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "c최rhdi", text: "c최고야", finalLang: "ko", words: [
        .init(raw: "c", output: "c", lang: "en", reason: "prefix", segments: nil),
        .init(raw: "rhdi", output: "고야", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "rlekflrhdlTtmqslek", text: "기다리고있습니다", finalLang: "ko", words: [
        .init(raw: "rlekflrhdlTtmqslek", output: "기다리고있습니다", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "woaldj없ek", text: "재미어없다", finalLang: "ko", words: [
        .init(raw: "woaldj", output: "재미어", lang: "ko", reason: "alt-hit", segments: nil),
        .init(raw: "ek", output: "다", lang: "ko", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "rlaclWlroaktdlTrpTek", text: "김치찌개맛있겠다", finalLang: "ko", words: [
        .init(raw: "rlaclWlroaktdlTrpTek", output: "김치찌개맛있겠다", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "xptmxmdlqslek", text: "테스트입니다", finalLang: "ko", words: [
        .init(raw: "xptmxmdlqslek", output: "테스트입니다", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "rk값dl djfakdi", text: "가값이 얼마야", finalLang: "ko", words: [
        .init(raw: "rk", output: "가", lang: "ko", reason: "alt-hit", segments: nil),
        .init(raw: "dl", output: "이", lang: "ko", reason: "both-keep", segments: nil),
        .init(raw: "djfakdi", output: "얼마야", lang: "ko", reason: "dict", segments: nil)
    ]),
    Golden(state: "en", input: "rif", text: "걀", finalLang: "ko", words: [
        .init(raw: "rif", output: "걀", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "dOemfdk", text: "얘들아", finalLang: "ko", words: [
        .init(raw: "dOemfdk", output: "얘들아", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "rkatkgkqslek", text: "감사합니다", finalLang: "ko", words: [
        .init(raw: "rkatkgkqslek", output: "감사합니다", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "dkssudgktpdy c최rhdi world", text: "안녕하세요 c최고야 world", finalLang: "en", words: [
        .init(raw: "dkssudgktpdy", output: "안녕하세요", lang: "ko", reason: "alt-hit", segments: nil),
        .init(raw: "c", output: "c", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "rhdi", output: "고야", lang: "ko", reason: "alt-hit", segments: nil),
        .init(raw: "world", output: "world", lang: "en", reason: "both-alt(basis)", segments: nil)
    ]),
    Golden(state: "ko", input: "hello rkatkgkqslek", text: "hello 감사합니다", finalLang: "ko", words: [
        .init(raw: "hello", output: "hello", lang: "en", reason: "alt-hit", segments: nil),
        .init(raw: "rkatkgkqslek", output: "감사합니다", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "completely rkatkgkqslRk obvious", text: "completely 감사합니까 obvious", finalLang: "en", words: [
        .init(raw: "completely", output: "completely", lang: "en", reason: "dict", segments: nil),
        .init(raw: "rkatkgkqslRk", output: "감사합니까", lang: "ko", reason: "alt-hit", segments: nil),
        .init(raw: "obvious", output: "obvious", lang: "en", reason: "alt-hit", segments: nil)
    ]),
    Golden(state: "en", input: "  rhdqorxptmxm\n  ", text: "  공백테스트\n  ", finalLang: "ko", words: [
        .init(raw: "rhdqorxptmxm", output: "공백테스트", lang: "ko", reason: "alt-hit", segments: nil)
    ]),
]

    /// TS engine processText 규약 그대로: augmentDicts 포함(ctProcessText 기본 noAugment=false).
    func testAllGoldenVectors() {
        let dicts = ctLoadBuiltinDicts()
        var mismatches: [String] = []
        for (idx, g) in Self.goldens.enumerated() {
            let result = ctProcessText(
                g.input,
                initialLang: g.state == "ko" ? .ko : .en,
                dicts: dicts
            )
            var problems: [String] = []
            if result.text != g.text { problems.append("text: \(result.text) != \(g.text)") }
            if result.finalLang.rawValue != g.finalLang {
                problems.append("finalLang: \(result.finalLang.rawValue) != \(g.finalLang)")
            }
            if result.passwordSuspect != g.passwordSuspect {
                problems.append("passwordSuspect: \(result.passwordSuspect) != \(g.passwordSuspect)")
            }
            // 단어 레벨 비교: reason·segments (TS words/raw 순서 일치)
            if result.words.count != g.words.count {
                problems.append("word count: \(result.words.count) != \(g.words.count)")
            } else {
                for (w, gw) in zip(result.words, g.words) {
                    if w.raw != gw.raw { problems.append("raw mismatch: \(w.raw) != \(gw.raw)") }
                    if w.output != gw.output { problems.append("output: \(w.output) != \(gw.output) (\(gw.raw))") }
                    if w.lang.rawValue != gw.lang { problems.append("lang: \(w.lang.rawValue) != \(gw.lang) (\(gw.raw))") }
                    if w.reason != gw.reason { problems.append("reason: \(w.reason) != \(gw.reason) (\(gw.raw))") }
                    // segments 비교
                    let segs = w.segments.map { $0.map { "\($0.lang.rawValue):\($0.text):\($0.basis)" }.joined(separator: "+") }
                    let gsegs = gw.segments.map { $0.map { "\($0.lang):\($0.text):\($0.basis)" }.joined(separator: "+") }
                    if segs != gsegs { problems.append("segments: \(segs ?? "nil") != \(gsegs ?? "nil") (\(gw.raw))") }
                }
            }
            if !problems.isEmpty {
                mismatches.append("[\(idx)] [\(g.state)] '\(g.input)': " + problems.joined(separator: "; "))
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count)/\(Self.goldens.count) golden mismatch:\n" + mismatches.joined(separator: "\n"))
    }

    func testGoldenCount() {
        XCTAssertEqual(Self.goldens.count, 81)
    }
}