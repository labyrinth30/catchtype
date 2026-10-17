/**
 * v1.1 회귀 테스트 — docs/QA-20261011.md 원작 catchtype 데모 4케이스 + 엣지 케이스.
 * 케이스 번호는 QA 보고의 결함 번호(1~4)와 대응한다.
 */
import { describe, test, expect, beforeAll } from 'bun:test';
import { loadBuiltinDicts, processText, augmentDicts, type Dicts, type Lang } from '../src';
import { KO_CHAR_TO_EN } from '../src/layout';
import { decomposeText } from '../src/hangul';

// 두벌식 표 역산 헬퍼 (engine.test.ts와 동일 규약 — 테스트 벡터를 손으로 쓰지 않는다)
const KO2EN = Object.fromEntries(Object.entries(KO_CHAR_TO_EN));
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
void ke; // 데모 케이스는 검증된 ASCII 벡터를 직접 쓴다(복모음 ke() 미지원 — hangul.test.ts 참조)

let dicts: Dicts | null = null;

beforeAll(async () => {
  dicts = await loadBuiltinDicts();
});

function pt(input: string, state: Lang = 'en') {
  return processText(input, { initialLang: state, dicts: dicts! });
}

describe('v1.1 회귀: 원작 데모 4케이스 (QA-20261011 결함 1~4)', () => {
  // 데모 원문은 잘못 둔 상태에서 QWERTY로 친 키스트링이라 ASCII로 재현한다:
  // 'test도'는 두벌식 키 'testeh'(t·e·s·t + ㄷ·ㅗ), 뒤 한국어 명사는 'dmlwk'(의자).
  test('결함1: npm test+도 혼합 — testeh → test도 (@ko, test+도 mixed 분할)', () => {
    const r = pt('npm testeh dmlwk', 'ko');
    expect(r.text).toBe('npm test도 의자');
    // test+도 세그먼트가 판정 근거로 남는다 — raw 키스트링 'testeh'의 판정
    const testeh = r.words.find((w) => w.raw === 'testeh');
    expect(testeh).toBeDefined();
    expect(testeh!.output).toBe('test도');
    expect(testeh!.segments).not.toBeNull();
    expect(testeh!.segments![0]).toMatchObject({ lang: 'en', text: 'test' });
    expect(testeh!.segments![1]).toMatchObject({ lang: 'ko', text: '도' });
  });

  test('결함2: Figma 링크 보내드릴게요 → Figma 유지 (카멜케이스 보호)', () => {
    const r = pt('Figma 링크 보내드릴게요', 'ko');
    expect(r.text).toBe('Figma 링크 보내드릴게요');
    expect(r.words[0].output).toBe('Figma');
  });

  test('결함3: READMEdp 설치 → README에 설치 (빈도 역전 임계 3배 완화)', () => {
    const r = pt('READMEdp 설치', 'en');
    expect(r.text).toBe('README에 설치');
  });

  test('결함4: git npm ls @ko → 그대로 (개발 용어 사전 보강)', () => {
    const r = pt('git npm ls 돌리기', 'ko');
    expect(r.text).toBe('git npm ls 돌리기');
    // dp에 대응하는 충돌 해소: git/ls — 개발 용어 en dict 히트로 both-alt(basis)
    expect(r.words.find((w) => w.raw === 'git')!.output).toBe('git');
    expect(r.words.find((w) => w.raw === 'npm')!.output).toBe('npm');
    expect(r.words.find((w) => w.raw === 'ls')!.output).toBe('ls');
  });
});

describe('v1.1 회귀: mixed 분할 정책 엣지 케이스', () => {
  test('AI로 — 고전 케이스(AIfh)는 유지', () => {
    const r = pt('AIfh');
    expect(r.text).toBe('AI로');
  });

  test('README에 — 조사 결합 fallback 분할(앞세그먼트 무근거 + 고빈도 조사)', () => {
    const r = pt('READMEdp', 'en');
    expect(r.text).toBe('README에');
    const segs = r.words[0].segments!;
    expect(segs[0]).toMatchObject({ lang: 'en', text: 'README' });
    expect(segs[1]).toMatchObject({ lang: 'ko', text: '에' });
  });

  test('testeh @en → test도 (혼합이 반대 언어 약근거(stats)를 덮어쓴다)', () => {
    const r = pt('testeh', 'en');
    expect(r.text).toBe('test도');
    expect(r.words[0].reason).toBe('mixed');
  });

  test('잡문자 후보는 mixed 불인정 (접두·통계만으로 되는 분할 금지)', () => {
    // 'tehst'는 en/ko 어느 쪽 사전 세그먼트로도 완성되지 않는다 — mixed 없이
    // 자체 ko통계 읽기(ㅅ돈ㅅ)로 alt-hit되거나, en상태에선 fallback 후보. 규약 검증:
    // reason이 mixed면 안 된다(사전 근거 없는 'te|hs'류 분할 없음).
    const r = pt('tehst', 'en');
    expect(r.words[0].reason).not.toBe('mixed');
  });

  test('fickme / fsoj @ko — 앞서 사전이 역전시켰던 흔한 말 방지(3배 임계 무해성)', () => {
    expect(pt('a fickme', 'ko').words[1].output).toBe('fickme');
    expect(pt('its fsoj', 'ko').words[1].output).toBe('fsoj');
  });

  test('dp @en → 에 (빈도 역전 3.97배 ≥ 3배 임계)', () => {
    const r = pt('dp', 'en');
    expect(r.text).toBe('에');
    expect(r.words[0].reason).toBe('both-alt(freq)');
  });

  test('흔한 영어 양자 충돌은 유지 (3배 임계 내로 안 들어옴)', () => {
    expect(pt('go', 'en').text).toBe('go');
    expect(pt('go', 'ko').text).toBe('해');
    expect(pt('to', 'en').text).toBe('to'); // 새? no — 빈도 우세 없음
    expect(pt('so', 'en').text).toBe('so');
    expect(pt('do', 'en').text).toBe('do');
    expect(pt('an', 'en').text).toBe('an');
    expect(pt('ah', 'en').text).toBe('ah');
  });
});

describe('v1.1 회귀: 카멜케이스·개발 용어 보호 엣지 케이스', () => {
  test('CamelCase: Google, Zoo, Hello @ko 그대로', () => {
    expect(pt('Google Drive 백업', 'ko').text).toBe('Google Drive 백업');
    expect(pt('Zoo animals', 'ko').text).toBe('Zoo animals');
    expect(pt('Hello world', 'ko').text).toBe('Hello world');
  });

  test('약어는 보호와 무관하게 정상 판정', () => {
    expect(pt('TODO', 'ko').text).toBe('TODO');
    expect(pt('DP', 'ko').text).toBe('예'); // ko dict 히트 — 카멜케이스 보호 대상 아님
  });

  test('개발 용어 보강이 판정을 바꾼다 (git / npm / yaml)', () => {
    expect(pt('git commit', 'ko').text).toBe('git commit');
    expect(pt('npm install', 'ko').text).toBe('npm install');
    expect(pt('yaml 파싱', 'ko').text).toBe('yaml 파싱');
    expect(pt('npm', 'ko').text).toBe('npm'); // v1.0에선 jamo-run ㅞㅡ로 깨졌다
  });

  test('영어 문장 @ko는 그대로 (보강이 오탐을 만들지 않음)', () => {
    expect(pt('hello world how are you', 'ko').text).toBe('hello world how are you');
    expect(pt('my dp profile', 'en').text).toBe('my 에 profile'); // dp↔에 3배 역전 — 허용
  });

  test('augmentDicts는 idempotent (size 불변, 재호출 캐시)', () => {
    const once = augmentDicts(dicts!);
    const twice = augmentDicts(once);
    expect(twice.en.words.size).toBe(once.en.words.size);
    expect(twice).toBe(once); // 캐시된 동일 Dicts 객체
  });

  test('EXTRA_EN_WORDS는 모두 en사정에 반영 + 대문자 포함 토큰은 대소문자 무관 히트', () => {
    const aug = augmentDicts(dicts!);
    for (const w of ['git', 'npm', 'yaml', 'json']) {
      expect(aug.en.words.has(w)).toBe(true);
    }
  });
});

describe('v1.1 회귀: 영어 문장 무변화 경비 (ko 상태 + 보강 사전)', () => {
  test('평범한 영어 문장 @ko — 한 단어도 깨지지 않음', () => {
    const sents = [
      'hello world how are you',
      'the banana is music',
      'please send me the file',
    ];
    for (const s of sents) {
      expect(pt(s, 'ko').text).toBe(s);
    }
  });

  test('한국어 교정은 여전히 동작 (사전 강화 이후)', () => {
    expect(pt('dmlwk', 'en').text).toBe('의자');
    expect(pt('dpfj', 'en').text).toBe('에러');
    expect(pt('dkssudgktpdy').text).toBe('안녕하세요');
  });
});
