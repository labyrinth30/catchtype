#!/usr/bin/env bun
/**
 * rebuild-golden.ts — Swift GoldenTests.swift의 벡터를 TS 엔진 실행 결과로 재생성.
 *
 * 소스 진실은 TS 엔진(packages/engine). 엔진 규칙을 고친 뒤 이 스크립트를 돌리고
 * 출력을 Tests/CatchTypeCoreTests/GoldenTests.swift의 goldens 배열에 붙여넣는다.
 *
 * usage: cd packages/macos/Scripts && bun rebuild-golden.ts > /tmp/golden.txt
 */
import {
  loadBuiltinDicts, processText, augmentDicts, KO_CHAR_TO_EN,
} from '../../engine/src/index.ts';
import { decomposeText } from '../../engine/src/hangul.ts';

const KO2EN = KO_CHAR_TO_EN;
function ke(text: string): string {
  let out = '';
  for (const ch of text) {
    const seq = decomposeText(ch);
    if (seq.length === 1 && !(seq[0] in KO2EN) && !/^[가-힣]$/.test(ch)) {
      out += ch;
      continue;
    }
    for (const j of seq) out += KO2EN[j] ?? ch;
  }
  return out;
}

const dicts = augmentDicts(await loadBuiltinDicts());

const cases: Array<[string, string]> = [
  ['en', 'dkssudgktpdy'], ['en', 'dmlwk'], ['en', 'dpfj'],
  ['en', 'banana'], ['ko', 'banana'], ['ko', 'music'], ['ko', 'server'],
  ['en', 'go'], ['ko', 'go'],
  ['en', 'to'], ['en', 'so'], ['en', 'do'], ['en', 'an'], ['en', 'ah'],
  ['en', 'dp'], ['en', 'AIfh'], ['en', 'testeh'], ['ko', 'testeh'],
  ['en', 'READMEdp'], ['en', 'READMEdp 설치'], ['en', 'tehst'],
  ['ko', 'TODO'], ['ko', 'DP'], ['ko', 'npm'],
  ['ko', 'git npm ls 돌리기'], ['ko', 'Figma 링크 보내드릴게요'],
  ['en', 'Figma fldzm qhsoemflfrpdy'], ['en', 'GitHub에서 PR 날렸어'],
  ['en', 'Zoo에 갔어'], ['en', 'TODO 확인해줘'],
  ['en', 'notion에서 페이지 복사해줘'], ['en', 'Slack으로 공유해'],
  ['ko', 'Google Drive 백업'], ['ko', 'Zoo animals'], ['ko', 'Hello world'],
  ['ko', 'hello'], ['ko', 'hello world how are you'], ['en', 'hello world how are you'],
  ['ko', 'the banana is music'], ['ko', 'I love this song'],
  ['ko', 'asdf'], ['ko', 'zxcv'],
  ['en', 'gggg'], ['ko', 'gggg'], ['ko', 'aass'], ['en', 'qqqq'],
  ['en', 'zzqq'], ['ko', 'zzqq'],
  ['en', 'my dp profile'], ['en', 'Tr0ub4dor&3 next'], ['en', 'abc123'],
  ['en', '123 !@#'], ['ko', '123 !@#'],
  ['ko', 'a fickme'], ['ko', 'its fsoj'],
  ['ko', 'yaml 파싱'], ['ko', 'git commit'], ['ko', 'npm install'],
  ['ko', 'npm testeh dmlwk'],
  ['ko', 'hello world how are you'], ['ko', 'please send me the file'], ['en', 'please send me the file'],
  ['en', ''], ['ko', ke('안녕하세요')], ['en', 'hello'],
  ['en', ke('기다리다')], ['en', ke('사랑')], ['en', ke('나는')], ['en', ke('최고야')],
  ['en', ke('기다리고있습니다')], ['en', ke('재미없다')], ['en', ke('김치찌개맛있겠다')],
  ['en', ke('테스트입니다')], ['en', ke('값이 얼마야')], ['en', ke('걀')], ['en', ke('얘들아')],
  ['en', ke('감사합니다')],
  ['en', 'dkssudgktpdy ' + ke('최고야') + ' world'],
  ['ko', 'hello ' + ke('감사합니다')],
  ['en', 'completely ' + ke('감사합니까') + ' obvious'],
  ['en', '  ' + ke('공백테스트') + '\n  '],
];

const esc = (s: string) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');

for (const [state, input] of cases) {
  const r = processText(input, { initialLang: state as 'ko' | 'en', dicts });
  const words = r.words.map((w) => {
    const segs = w.segments
      ? `, segments: [.init(lang: "${w.segments[0].lang}", text: "${esc(w.segments[0].text)}", basis: "${w.segments[0].basis}"), .init(lang: "${w.segments[1].lang}", text: "${esc(w.segments[1].text)}", basis: "${w.segments[1].basis}")]`
      : ', segments: nil';
    return `        .init(raw: "${esc(w.raw)}", output: "${esc(w.output)}", lang: "${w.lang}", reason: "${w.reason}"${segs}),`;
  }).join('\n');
  const pw = r.passwordSuspect ? ', passwordSuspect: true' : '';
  console.log(`    Golden(state: "${state}", input: "${esc(input)}", text: "${esc(r.text)}", finalLang: "${r.finalLang}"${pw}, words: [`);
  if (words) console.log(words);
  console.log('    ]),');
}
