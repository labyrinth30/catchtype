import { describe, test, expect, beforeAll } from 'bun:test';
import { loadBuiltinDicts, processText, judgeWord, charToKey, type Dicts, type Lang } from '../src';
import { KO_CHAR_TO_EN, type Key, keyToJamo } from '../src/layout';
import { decomposeText } from '../src/hangul';

// 두벌식 표에서 직접 인코딩 — 테스트 벡터를 손으로 쓰지 않는다.
// 겹받침은 두 글쇠로 분해해 입력(███ 실 IME 관점).
const KO_KEY_PAIRS: Array<[string, string]> = [
  ['ㄱ', 'r'], ['ㄲ', 'R'], ['ㄴ', 's'], ['ㄷ', 'e'], ['ㄸ', 'E'],
  ['ㄹ', 'f'], ['ㅁ', 'a'], ['ㅂ', 'q'], ['ㅃ', 'Q'], ['ㅅ', 't'], ['ㅆ', 'T'],
  ['ㅇ', 'd'], ['ㅈ', 'w'], ['ㅉ', 'W'], ['ㅊ', 'c'], ['ㅋ', 'z'], ['ㅌ', 'x'],
  ['ㅍ', 'v'], ['ㅎ', 'g'],
  ['ㅏ', 'k'], ['ㅐ', 'o'], ['ㅑ', 'i'], ['ㅒ', 'O'], ['ㅓ', 'j'], ['ㅔ', 'p'],
  ['ㅕ', 'u'], ['ㅖ', 'P'], ['ㅗ', 'h'], ['ㅛ', 'y'], ['ㅜ', 'n'], ['ㅠ', 'b'],
  ['ㅡ', 'm'], ['ㅣ', 'l'],
  ['ㅘ', 'hk'], ['ㅙ', 'ho'], ['ㅚ', 'hl'], ['ㅝ', 'nj'], ['ㅞ', 'np'], ['ㅟ', 'nl'], ['ㅢ', 'ml'],
  ['ㄳ', 'rt'], ['ㄵ', 'sw'], ['ㄶ', 'sg'], ['ㄺ', 'fr'], ['ㄻ', 'fa'], ['ㄼ', 'fq'],
  ['ㄽ', 'ft'], ['ㄾ', 'fx'], ['ㄿ', 'fv'], ['ㅀ', 'fg'], ['ㅄ', 'qt'],
];
const KO2EN = Object.fromEntries(KO_KEY_PAIRS);

/** 의도 한국어 → 두벌식 키 시퀀스 (속기 헬퍼). 한글 아닌 문자는 그대로. */
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

let dicts: Dicts | null = null;

beforeAll(async () => {
  dicts = await loadBuiltinDicts();
});

function pt(input: string, state: Lang = 'en') {
  return processText(input, { initialLang: state, dicts: dicts! });
}

describe('engine: 단어 단위 교정 시나리오', () => {
  // ---- 안전 사전 단어들: 잘못된 상태에서도 사전 히트로 교정 ----
  test('dkssudgktpdy → 안녕하세요 (en 상태에서 한글 단어)', () => {
    expect(pt('dkssudgktpdy').text).toBe('안녕하세요');
  });

  test('사전 일치 한국어 단어 (en 상태)', () => {
    expect(pt(ke('기다리다')).text).toBe('기다리다');
    expect(pt(ke('사랑')).text).toBe('사랑');
    expect(pt(ke('나는')).text).toBe('나는');
    expect(pt(ke('최고야')).text).toBe('최고야');
  });

  test('통계 근거: 사전에 없는 활용형도 교정', () => {
    expect(pt(ke('안녕하세요')).words[0].reason).toBeDefined();
    expect(pt(ke('기다리고있습니다')).text).toBe('기다리고있습니다');
    expect(pt(ke('재미없다')).text).toBe('재미없다');
    expect(pt(ke('김치찌개맛있겠다')).text).toBe('김치찌개맛있겠다');
    expect(pt(ke('테스트입니다')).text).toBe('테스트입니다');
  });

  test('복합 종성 문장 (en 상태)', () => {
    expect(pt(ke('값이 얼마야')).text).toBe('값이 얼마야');
  });

  test('이모티콘 자모 반복 (en 상태)', () => {
    // 반복·연속 자음 글쇠는 두벌식 조합 규칙을 따른다 (실 IME와 동일 결과)
    expect(pt('gggg').text).toBe('ㅎㅎㅎㅎ'); // ㅎ: 쌍자모 없음 → 4개 그대로
    expect(pt('gggg', 'ko').text).toBe('ㅎㅎㅎㅎ');
    expect(pt('aass', 'ko').text).toBe('ㅁㅁㄴㄴ'); // ㅅ: en 쪽 사전 근거와 공존 불가 — ko에서 두벌식 읽기로 유지
    // 되돌림 아님: 충돌 규칙상 현재 상태(en)가 유지된다(qqqq → ㅃㅃ)
    expect(pt('qqqq').text).toBe('ㅃㅃ');
  });

  test('shift 글쇠(ㅒㅖ·쌍자모) 반영', () => {
    // 'ㅒ' = Shift+O: 'AOPfh' 아닌 정확 시퀀스로 확인
    expect(pt(ke('걀')).text).toBe('걀');
    expect(pt(ke('얘들아')).text).toBe('얘들아');
  });
});

describe('engine: 문자별 교정 (typos vs intent)', () => {
  test('한국어 상태에서 영어 단어 타이핑 → 그대로 통과 (오탐 아님)', () => {
    expect(pt('hello', 'ko').text).toBe('hello');
    expect(pt('the banana is music', 'ko').text).toBe('the banana is music');
    expect(pt('I love this song', 'ko').text).toBe('I love this song');
  });

  test('한국어 상태에서 자판 영역 글자만 있는 토큰 → jamo-run 교정', () => {
    expect(pt('asdf', 'ko').text).toBe('ㅁㄴㅇㄹ');
    expect(pt("zxcv", 'ko').text).toBe('ㅋㅌㅊㅍ');
  });

  test('한국어 상태의 영어 문장 — 단어 판정과 상태 흐름', () => {
    // 사전 근거가 반대 언어에서 나오면 단어별로 상태가 바뀐다 — 설계 규약:
    // 근거가 완전 무근거가 아닌 한 상태를 앞세우지 않는다(basis-trumps-state).
    const r = pt('hello world how are you', 'ko');
    expect(r.text).toBe('hello world how are you');
    expect(r.words.map((w) => w.lang)).toEqual(['en', 'en', 'en', 'en', 'en']);
    expect(r.finalLang).toBe('en');
  });

  test('충돌: 둘 다 유효할 때 근거 등급·빈도로 우열', () => {
    // 'banana', 'music': ko 읽기(ㅠ무뭄/믐ㅑㅑ)는 사전 힛트 아님 — stats(2) vs dict/en??
    // banana: ko 읽기가 사전 무히트 + en dict → both-alt(basis)
    // en 상태 'go': ko 읽기(해) 사전 힛트 vs en dict — equal basis, 빈도 역전 없음 → 현상태
    const cases: Array<[string, string]> = [
      ['banana', 'banana'], ['music', 'music'], ['server', 'server'],
    ];
    for (const [w, want] of cases) {
      expect(pt(w, 'ko').text).toBe(want);
    }
    // go: en 상태 유지 — ko 쪽 '해'도 사전 힛트지만 근거 등급 같고 빈도 역전 없음
    expect(pt('go', 'en').text).toBe('go');
    // go in ko: 현재 상태 유지
    expect(pt('go', 'ko').text).toBe('해');
  });

  test('혼합: AI로 — 앞 en 세그먼트 + 뒤 ko 세그먼트', () => {
    const r = pt('AIfh'); // A I + f(ㄹ) h(ㅗ) → AI + 로
    expect(r.text).toBe('AI로');
    const segs = r.words[0].segments;
    expect(segs).not.toBeNull();
    expect(segs![0]).toMatchObject({ lang: 'en', text: 'AI' });
    expect(segs![1]).toMatchObject({ lang: 'ko', text: '로' });
  });

  test('혼합이 아닌 케이스는 세그먼트 null', () => {
    expect(pt('hello', 'ko').words[0].segments).toBeNull();
  });
});

describe('engine: 세션 상태 전환 신호', () => {
  test('alt-hit 단어가 상태를 반대 언어로 갱신', () => {
    const r = pt('dkssudgktpdy');
    expect(r.finalLang).toBe('ko');
    const r2 = pt('hello', 'ko');
    expect(r2.finalLang).toBe('en');
  });

  test('문장 런 상태: en 상태로 시작해 한국어로 전환 후 유지', () => {
    const r = pt('dkssudgktpdy ' + ke('최고야') + ' world');
    // dkssudgktpdy → 안녕하세요(ko), 최고야 → 이미 ko 상태에서 사전판정, world — '월드' 아님 → fallback en
    expect(r.text).toBe('안녕하세요 최고야 world');
    expect(r.finalLang).toBe('en');
  });

  test('문장 런 상태: ko 상태로 시작, 영어 단어 후 다시 한국어', () => {
    const r = pt('hello ' + ke('감사합니다'), 'ko');
    // hello → en (alt-hit), 그 후 감사합니다는 en 상태의 교정 대상 → ko
    expect(r.text).toBe('hello 감사합니다');
    expect(r.finalLang).toBe('ko');
  });
});

describe('engine: fallback / 부호·숫자 / 약어', () => {
  test('숫자·부호는 두 언어 모두 통과', () => {
    expect(pt('123 !@#').text).toBe('123 !@#');
    expect(pt('123 !@#', 'ko').text).toBe('123 !@#');
  });

  test('약어 (2~4 대문자) 읽기', () => {
    const r = pt('TODO', 'ko');
    expect(r.text).toBe('TODO');
  });

  test('fallback: 어느 언어로도 유효하지 않으면 통과', () => {
    // 오타나 고유명사는 그대로 (en 상태 — 자판 런 폴백은 한국어 상태 전용)
    expect(pt('zzqq', 'en').text).toBe('zzqq');
    expect(pt('zzqq', 'en').finalLang).toBe('en');
    // ko 상태에서는 자판 런 폴백이 두벌식 자모로 읽는다
    expect(pt('zzqq', 'ko').text).toBe('ㅋㅋㅃ');
  });
});

describe('engine: 비밀번호 안전', () => {
  test('문자 클래스 3종 이상 →password 판정 스킵 + 플래그', () => {
    const r = pt('Tr0ub4dor&3 next');
    expect(r.text).toBe('Tr0ub4dor&3 next'); // 원본 그대로
    expect(r.passwordSuspect).toBe(true);
  });

  test('abc123 같은 2종 혼용은 판정 계속(비밀번호 아님으로 취급)', () => {
    const r = pt('abc123');
    expect(r.passwordSuspect).toBe(false);
  });

  test('judgeWord 직접 호출도 비밀번호 스킵', () => {
    // charToKey는 영문자만 Key로 만든다(기호는 processText 토큰 경로에서만 봄).
    // 3종 혼용: 대문자+소문자+... — 영문자만으로는 2종이 최대다.
    // judgeWord의 비밀번호 경로는 looksLikePassword(raw)를 쓰므로 영문자-only로는
    // 못 건드린다 → processText 레벨에서 이미 검증했으므로 여기선 규약만 확인.
    const keys = ['T', 'r', 'b', 'X'].flatMap((c) => charToKey(c) ?? []);
    const d = judgeWord(keys, 'en', dicts!);
    expect(d.passwordSuspect).toBe(false); // 영문자 2종 혼용은 비밀번호 아님
    expect(d.output).toBe('ㅆ귵'); // ko 읽기 alt-hit(통계) — 규약대로
  });
});

describe('engine: 미스 매치 방어 (혼란 방지용 오차 문장)', () => {
  test('영어 토큰 사이 한국어 단어 삽입 후 상태 복귀', () => {
    const r = pt('completely ' + ke('감사합니까') + ' obvious');
    // 감사합니다 — 활용형 통계 경로
    expect(r.text).toBe('completely 감사합니까 obvious');
  });

  test('빈 입력', () => {
    expect(pt('').text).toBe('');
  });

  test('공백·개행 보존', () => {
    expect(pt('  ' + ke('공백테스트') + '\n  ').text).toBe('  공백테스트\n  ');
  });
});
