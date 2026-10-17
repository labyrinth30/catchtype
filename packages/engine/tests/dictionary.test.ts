import { describe, test, expect } from 'bun:test';
import { buildDict, hasWord, hasPrefix, weightOf, dictSize } from '../src/dictionary';

describe('dictionary', () => {
  const dict = buildDict('en', [
    ['the', 100], ['of', 90], ['cat', 40], ['cathedral', 10], ['catnip', 5],
  ]);

  test('hasWord', () => {
    expect(hasWord(dict, 'cat')).toBe(true);
    expect(hasWord(dict, 'CAT')).toBe(true); // 영어는 대소문자 무관
    expect(hasWord(dict, 'dog')).toBe(false);
  });

  test('hasPrefix — 이분 탐색 접두어 검색', () => {
    expect(hasPrefix(dict, 'cat')).toBe(true);   // 자기 자신이든 접두어든
    expect(hasPrefix(dict, 'ca')).toBe(true);
    expect(hasPrefix(dict, 'cath')).toBe(true);
    expect(hasPrefix(dict, 'cu')).toBe(false);
  });

  test('weightOf — 값이 클수록 흔한 단어(빈도류 규약)', () => {
    const wThe = weightOf(dict, 'the')!;
    const wCat = weightOf(dict, 'cat')!;
    const wCatnip = weightOf(dict, 'catnip')!;
    expect(wThe).toBeGreaterThan(wCat);
    expect(wCat).toBeGreaterThan(wCatnip);
    expect(wThe).toBe(1); // 최빈도 = 1
    expect(weightOf(dict, 'zzz')).toBeUndefined();
  });

  test('빈도 규약: 값 클수록 가중치 큼 (역방향 값 저장 방지)', () => {
    // 100(the) vs 10(cathedral): 가중치 차이의 방향 검증
    expect(weightOf(dict, 'the')!).toBeGreaterThan(weightOf(dict, 'cathedral')!);
  });

  test('중복 단어는 최대 빈도 유지', () => {
    const d = buildDict('en', [['w1', 5], ['w1', 99]]);
    expect(d.words.get('w1')).toBe(99);
  });

  test('한국어 사전: 대소문자 정규화 없음', () => {
    const ko = buildDict('ko', [['감사', 500]]);
    expect(hasWord(ko, '감사')).toBe(true);
    expect(dictSize(ko)).toBe(1);
  });
});
