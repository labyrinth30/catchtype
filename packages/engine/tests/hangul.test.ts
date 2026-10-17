import { describe, test, expect } from 'bun:test';
import {
  CHO, JUNG, JONG,
  composeSyllable,
  composeJamo,
  decomposeText,
  isHangulSyllable,
} from '../src/hangul';

describe('hangul: syllable compose', () => {
  test('composeSyllable basic', () => {
    expect(composeSyllable('ㅇ', 'ㅏ', 'ㄴ')).toBe('안');
    expect(composeSyllable('ㄱ', 'ㅏ')).toBe('가'); // 받침 생략
  });

  test('composeJamo 단일 자모 시퀀스: 기본 조합', () => {
    expect(composeJamo([...'ㅇㅏㄴ'])).toBe('안');
    expect(composeJamo([...'ㄱㅏㅁ'])).toBe('감');
    expect(composeJamo([...'ㅎㅏㄴㄱㅡㄹ'])).toBe('한글');
  });

  test('composeJamo 받침이 모음을 만나면 다음 음절 초성으로 회수', () => {
    expect(composeJamo([...'ㅎㅏㅅㅔㅇㅛ'])).toBe('하세요'); // 핫+ㅔ 아님
    expect(composeJamo([...'ㅇㅏㄴㄴㅕㅇ'])).toBe('안녕');
  });

  test('composeJamo 복모음 합성', () => {
    expect(composeJamo([...'ㅇㅗㅏ'])).toBe('와');
    expect(composeJamo([...'ㅂㅜㅓ'])).toBe('붜'); // ㅜ+ㅓ = ㅝ 합성
    expect(composeJamo([...'ㅎㅗㅣ'])).toBe('회');
    expect(composeJamo([...'ㅂㅜㅓㄱ'])).toBe('붝'); // 모음 글라이드 병합은 받침 없는 live syll에서도 일어남(IME 동작)
    expect(composeJamo([...'ㅂㅜㄱㅓ'])).toBe('부거'); // 받친 뒤 모음은 받침 회수로 새 음절
  });

  test('composeJamo 겹받침: 받친 뒤 모음 오면 앞받침 확정·나머지 초성화', () => {
    // ㄹㄱ (겹받침 ㄺ) + ㅏ → 'ㄹ'받침 확정 + ㄱ 초성 ㅏ
    expect(composeJamo([...'ㅇㅣㄹㄱㅣ'])).toBe('일기');
    expect(composeJamo([...'ㅇㅜㄹㅁㅏㄴ'])).toBe('울만'); // ㄹㅁ=ㄻ 없이 회수 → ㄹ받침+ㅁ초성
  });

  test('composeJamo 쌍자모 초성 합성', () => {
    expect(composeJamo([...'ㄱㄱㅏ'])).toBe('까');
    expect(composeJamo([...'ㅅㅅㅏ'])).toBe('싸');
  });

  test('composeJamo 자음 연속: 조합 불가하면 확정 후 새 초성', () => {
    expect(composeJamo([...'ㄱㅏㅂㅅ'])).toBe('값');
    expect(composeJamo([...'ㄱㅏㄴㅏ'])).toBe('가나'); // ㄴ 회수
  });

  test('자모 단독은 호환 자모로 유지', () => {
    expect(composeJamo([...'ㄱ'])).toBe('ㄱ');
    expect(composeJamo([...'ㅋㅋㄋ'])).toBe('ㅋㅋㄋ');
    expect(composeJamo([...'ㅋㅋ'])).toBe('ㅋㅋ'); // 이모티콘 그대로
  });
});

describe('hangul: decompose', () => {
  test('완성형 분해', () => {
    const j = [...'안'.replace('안','안')].length;
    const seq = decomposeText('한');
    expect(seq).toEqual([...('ㅎㅏㄴ')]);
    expect(decomposeText('가')).toEqual([...('ㄱㅏ')]);
  });

  test('라틴·숫자는 그대로', () => {
    expect(decomposeText('ab1!')).toEqual([...('ab1!')]);
  });

  test('복합 종성 완성형 직접 분해', () => {
    // '値' 아니고 '흙' — ㄹ 받침 ㄱ 겹받침
    expect(decomposeText('흙')).toEqual([...('ㅎㅡㄺ')]);
  });
});

describe('hangul: full roundtrip (all 11,172 complete syllables)', () => {
  test('compose(decompose(s)) === s for every syllable', () => {
    let failures = 0;
    for (let c = 0; c < CHO.length; c++) {
      for (let v = 0; v < JUNG.length; v++) {
        for (let t = 0; t < JONG.length; t++) {
          const s = composeSyllable(CHO[c]!, JUNG[v]!, JONG[t] ?? undefined);
          const back = composeJamo(decomposeText(s));
          if (back !== s) {
            failures++;
            if (failures <= 5) console.log('RT fail:', s, decomposeText(s).join(','), back);
          }
        }
      }
    }
    expect(failures).toBe(0);
  });
});

describe('hangul: misc', () => {
  test('isHangulSyllable', () => {
    expect(isHangulSyllable('가')).toBe(true);
    expect(isHangulSyllable('a')).toBe(false);
    expect(isHangulSyllable('ㄱ')).toBe(false);
  });
});
