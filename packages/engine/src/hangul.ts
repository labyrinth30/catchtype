/**
 * 한글 조합기 — 두벌식 입력을 유니코드 완성형 음절로 조립.
 * 표준 한글 IME 조합 규칙(초성+중성+종성, 복모음, 겹받침)을 순수 함수로 구현.
 * 데이터 입출력 없음 — 엔진 코어의 일부.
 */

/** 초성 19 (유니코드 음절 인덱스 순) */
export const CHO = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
] as const;

/** 중성 21 */
export const JUNG = [
  'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ',
  'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ',
] as const;

/** 종성 28 (0 = 종성 없음) */
export const JONG = [
  null, 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ',
  'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ',
  'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
] as const;

/** 복모음 합성: [첫 중성, 둘째 중성] → 합성 중성 */
const JUNG_MERGE: Record<string, string> = {
  'ㅗㅏ': 'ㅘ', 'ㅗㅐ': 'ㅙ', 'ㅗㅣ': 'ㅚ',
  'ㅜㅓ': 'ㅝ', 'ㅜㅔ': 'ㅞ', 'ㅜㅣ': 'ㅟ',
  'ㅡㅣ': 'ㅢ',
};
/** 복모음 분해 역산 */
const JUNG_SPLIT: Record<string, [string, string]> = Object.fromEntries(
  Object.entries(JUNG_MERGE).map(([k, v]) => [v, k.split('') as [string, string]]),
);

/** 겹받침 합성: [받침, 자음] → 겹받침 */
const JONG_MERGE: Record<string, string> = {
  'ㄱㅅ': 'ㄳ', 'ㄴㅈ': 'ㄵ', 'ㄴㅎ': 'ㄶ',
  'ㄹㄱ': 'ㄺ', 'ㄹㅁ': 'ㄻ', 'ㄹㅂ': 'ㄼ', 'ㄹㅅ': 'ㄽ',
  'ㄹㅌ': 'ㄾ', 'ㄹㅍ': 'ㄿ', 'ㄹㅎ': 'ㅀ', 'ㅂㅅ': 'ㅄ',
};
/** 겹받침 분해 역산 */
const JONG_SPLIT: Record<string, [string, string]> = Object.fromEntries(
  Object.entries(JONG_MERGE).map(([k, v]) => [v, k.split('') as [string, string]]),
);

/** 쌍자모 합성 */
const CHO_MERGE: Record<string, string> = {
  'ㄱㄱ': 'ㄲ', 'ㄷㄷ': 'ㄸ', 'ㅂㅂ': 'ㅃ', 'ㅅㅅ': 'ㅆ', 'ㅈㅈ': 'ㅉ',
};

const CHO_IDX = new Map<string, number>(CHO.map((c, i) => [c, i]));
const JUNG_IDX = new Map<string, number>(JUNG.map((c, i) => [c, i]));
const JONG_IDX = new Map<string, number>(JONG.map((c, i) => [c!, i]).filter(([c]) => c !== null) as [string, number][]);

/** 종성이 될 수 있는 단일 받침 (겹받침은 합성으로만 생김) */
const JONG_SINGLE = new Set(['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ']);

export function isHangulSyllable(ch: string): boolean {
  const n = ch.codePointAt(0)!;
  return n >= 0xac00 && n <= 0xd7a3;
}

/** 초/중/종 인덱스로 완성형 음절 1글자 생성 */
export function composeSyllable(cho: string, jung: string, jong?: string): string {
  const c = CHO_IDX.get(cho);
  const j = JUNG_IDX.get(jung);
  if (c === undefined || j === undefined) throw new Error(`invalid cho/jung: ${cho}${jung}`);
  const g = jong === undefined ? 0 : JONG_IDX.get(jong);
  if (jong !== undefined && g === undefined) throw new Error(`invalid jong: ${jong}`);
  return String.fromCharCode(0xac00 + c * 588 + j * 28 + g!);
}

type Live =
  | { kind: 'cho'; ch: string }
  | { kind: 'jung'; ch: string }
  | { kind: 'syll'; cho: string; jung: string; jong?: string };

function flushLive(live: Live | null, out: string[]): void {
  if (!live) return;
  if (live.kind === 'cho' || live.kind === 'jung') out.push(live.ch); // 호환 자모 그대로
  else out.push(composeSyllable(live.cho, live.jung, live.jong));
}

/**
 * 호환 자모(두벌식 자모) 시퀀스를 조합 규칙에 따라 문자열로 조립.
 * 실 IME처럼: 조합 중인 마지막 요소만 미완으로 남기고 완성분은 확정.
 * 예) ['ㅇ','ㅏ','ㄴ','ㄴ','ㅕ','ㅇ'] → '안녕'
 *     ['ㄹ','ㅗ','ㄴ','ㅇ','ㅏ','ㄴ'] → '롤안' (ㄴ+ㅇㅏ: 받친 ㄴ이 회수되어 안)
 * 타이핑 시퀀스는 단일 자모만 나오지만, decompose()의 역산 재조립(recompose)을
 * 지원하기 위해 복합 종성(ㄳ ㄵ ㄶ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅄ)이 직접 들어오면
 * 현재 음절의 받침으로 수용한다 (실 IME 합성 결과와 동일한 최종 상태).
 */
export function composeJamo(seq: readonly string[]): string {
  const out: string[] = [];
  let live: Live | null = null;

  for (const jamo of seq) {
    const isVowel = JUNG_IDX.has(jamo);
    if (isVowel) {
      if (!live) {
        live = { kind: 'jung', ch: jamo };
      } else if (live.kind === 'cho') {
        live = { kind: 'syll', cho: live.ch, jung: jamo };
      } else if (live.kind === 'jung') {
        const merged: string | undefined = JUNG_MERGE[live.ch + jamo];
        if (merged) live = { kind: 'jung', ch: merged };
        else { flushLive(live, out); live = { kind: 'jung', ch: jamo }; }
      } else {
        // syll
        if (live.jong) {
          const split: [string, string] | undefined = JONG_SPLIT[live.jong];
          if (split) {
            // 겹받침 분해: 앞쪽 받침은 확정, 남은 자음이 새 음절 초성이 되어 모음과 합침
            out.push(composeSyllable(live.cho, live.jung, split[0]));
            live = { kind: 'syll', cho: split[1], jung: jamo };
          } else {
            // 단일 받침 회수: 모음이 들어오면 받침이 다음 음절의 초성으로 넘어간다.
            // 실 IME 동작 — 예) ㅎㅏㅅㅔ → 하|세 (핫ㅔ 아님)
            out.push(composeSyllable(live.cho, live.jung));
            live = { kind: 'syll', cho: live.jong, jung: jamo };
          }
        } else {
          const merged: string | undefined = JUNG_MERGE[live.jung + jamo];
          if (merged) live = { kind: 'syll', cho: live.cho, jung: merged };
          else { flushLive(live, out); live = { kind: 'jung', ch: jamo }; }
        }
      }
    } else {
      // 자음
      if (!live) {
        live = { kind: 'cho', ch: jamo };
      } else if (live.kind === 'cho') {
        const merged: string | undefined = CHO_MERGE[live.ch + jamo];
        if (merged) live = { kind: 'cho', ch: merged };
        else { flushLive(live, out); live = { kind: 'cho', ch: jamo }; }
      } else if (live.kind === 'jung') {
        flushLive(live, out);
        live = { kind: 'cho', ch: jamo };
      } else {
        // syll
        if (!live.jong) {
          if (JONG_SINGLE.has(jamo) || JONG_IDX.has(jamo)) live = { kind: 'syll', cho: live.cho, jung: live.jung, jong: jamo };
          else { flushLive(live, out); live = { kind: 'cho', ch: jamo }; }
        } else {
          const merged: string | undefined = JONG_MERGE[live.jong + jamo];
          if (merged) live = { kind: 'syll', cho: live.cho, jung: live.jung, jong: merged };
          else { flushLive(live, out); live = { kind: 'cho', ch: jamo }; }
        }
      }
    }
  }
  flushLive(live, out);
  return out.join('');
}

/**
 * 문자열을 자모 시퀀스로 분해. 완성형 음절은 초/중/종으로, 호환 자모는 그대로,
 * 그 외 문자(라틴, 숫자 등)는 그대로 둔다.
 */
export function decomposeText(text: string): string[] {
  const out: string[] = [];
  for (const ch of text) {
    const n = ch.codePointAt(0)!;
    if (n >= 0xac00 && n <= 0xd7a3) {
      const idx = n - 0xac00;
      const cho = CHO[Math.floor(idx / 588)];
      const jung = JUNG[Math.floor((idx % 588) / 28)];
      const jong = JONG[idx % 28];
      out.push(cho!, jung!);
      if (jong) out.push(jong!);
    } else {
      out.push(ch);
    }
  }
  return out;
}

/** 분해된 시퀀스가 완성형 음절만으로 재조립 가능한지(= roundtrip) 검사용 */
export function recomposeDecomposed(seq: readonly string[]): string {
  return composeJamo(seq);
}
