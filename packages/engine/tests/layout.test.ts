import { describe, test, expect } from 'bun:test';
import {
  EN_CHAR_TO_KO,
  EN_SHIFT_TO_KO,
  KO_CHAR_TO_EN,
  charToKey,
  keyToJamo,
  keyToLatin,
  KVK_ANSI,
} from '../src/layout';

describe('layout: 두벌식 mapping', () => {
  test('한글 자모 배열이 표준 두벌식과 일치', () => {
    expect(EN_CHAR_TO_KO['r']).toBe('ㄱ');
    expect(EN_CHAR_TO_KO['k']).toBe('ㅏ');
    expect(EN_CHAR_TO_KO['o']).toBe('ㅐ');
    expect(EN_CHAR_TO_KO['p']).toBe('ㅔ');
    expect(EN_CHAR_TO_KO['q']).toBe('ㅂ');
    expect(EN_SHIFT_TO_KO['r']).toBe('ㄲ');
    expect(EN_SHIFT_TO_KO['q']).toBe('ㅃ');
    expect(EN_SHIFT_TO_KO['o']).toBe('ㅒ');
    expect(EN_SHIFT_TO_KO['p']).toBe('ㅖ');
  });

  test('shift 없는 글쇠는 shift와 무관하게 같은 자모', () => {
    // 예: a=ㅁ. shift+a도 ㅁ (두벌식에서 이동 없는 글쇠)
    expect(keyToJamo(charToKey('a')!)).toBe('ㅁ');
    expect(keyToJamo(charToKey('A')!)).toBe('ㅁ');
  });

  test('KO_CHAR_TO_EN 역산 상호 일치 (탈대문자 포함)', () => {
    for (const [en, jamo] of Object.entries(EN_CHAR_TO_KO)) {
      expect(KO_CHAR_TO_EN[jamo]).toBe(en);
    }
    expect(KO_CHAR_TO_EN['ㄲ']).toBe('R');
    expect(KO_CHAR_TO_EN['ㅖ']).toBe('P');
  });

  test('charToKey / keyToLatin 라운드트립', () => {
    for (const ch of 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ') {
      const k = charToKey(ch);
      expect(k).not.toBeNull();
      expect(keyToLatin(k!)).toBe(ch);
    }
    expect(charToKey('1')).toBeNull();
    expect(charToKey('!')).toBeNull();
  });

  test('KVK_ANSI 주요 키코드가 macOS Events.h 표준값', () => {
    expect(KVK_ANSI['KeyA']).toBe(0x00);
    expect(KVK_ANSI['Space']).toBe(0x31);
    expect(KVK_ANSI['Enter']).toBe(0x24);
    expect(KVK_ANSI['Backspace']).toBe(0x33);
  });

  test('dkssudgktpdy 시퀀스가 안녕하세요 자모로 읽힘', () => {
    const seq = 'dkssudgktpdy'.split('').map((c) => keyToJamo(charToKey(c)!));
    expect(seq.join('')).toBe('ㅇㅏㄴㄴㅕㅇㅎㅏㅅㅔㅇㅛ');
  });
});
