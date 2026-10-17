/**
 * 두벌식(표준 390) 자판 매핑 — KS X 5002 두벌식 표준 배열.
 *
 * QWERTY 글쇠 → 한글 자모(호환 자모 U+3131–U+3163).
 * 표준 두벌식에서 shift로 자모가 바뀌는 글쇠는 자음 쌍자모(ㅃㅉㄸㄲㅆ)와
 * ㅒ(Shift+O), ㅖ(Shift+P)뿐이고, 나머지 글쇠는 shift 여부와 무관하게
 * 같은 자모를 낸다. 이는 공개 표준 배열이며, 직접 정의했다.
 */

/** 정규화 키: code는 브라우저 event.code 계열 라벨(KeyA, Space, Enter...). */
export interface Key {
  code: string;
  shift: boolean;
}

export type Lang = 'ko' | 'en';

/** QWERTY 소문자 1글자 → 평자모(비 shift). 26자 전부 정의. */
export const EN_CHAR_TO_KO: Readonly<Record<string, string>> = {
  q: 'ㅂ', w: 'ㅈ', e: 'ㄷ', r: 'ㄱ', t: 'ㅅ',
  y: 'ㅛ', u: 'ㅕ', i: 'ㅑ', o: 'ㅐ', p: 'ㅔ',
  a: 'ㅁ', s: 'ㄴ', d: 'ㅇ', f: 'ㄹ', g: 'ㅎ',
  h: 'ㅗ', j: 'ㅓ', k: 'ㅏ', l: 'ㅣ',
  z: 'ㅋ', x: 'ㅌ', c: 'ㅊ', v: 'ㅍ', b: 'ㅠ', n: 'ㅜ', m: 'ㅡ',
};

/** shift 시 자모가 바뀌는 글쇠만. 없는 글쇠는 EN_CHAR_TO_KO와 동일. */
export const EN_SHIFT_TO_KO: Readonly<Record<string, string>> = {
  q: 'ㅃ', w: 'ㅉ', e: 'ㄸ', r: 'ㄲ', t: 'ㅆ',
  o: 'ㅒ', p: 'ㅖ',
};

/** 역방향: 자모 → QWERTY 글쇠(대소문자 포함). 테스트 벡터 생성·CLI 편의용. */
export const KO_CHAR_TO_EN: Readonly<Record<string, string>> = Object.fromEntries([
  ...Object.entries(EN_CHAR_TO_KO).map(([k, v]) => [v, k]),
  ...Object.entries(EN_SHIFT_TO_KO).map(([k, v]) => [v, k.toUpperCase()]),
]);

const isUpperAtoZ = (ch: string) => ch >= 'A' && ch <= 'Z';

/** 타이핑된 문자(대소문자 = shift 여부)를 정규화 Key로 변환. 영문자가 아니면 null. */
export function charToKey(ch: string): Key | null {
  if (ch.length !== 1 || !/[a-zA-Z]/.test(ch)) return null;
  return { code: `Key${ch.toUpperCase()}`, shift: isUpperAtoZ(ch) };
}

/** 두벌식으로 읽은 자모. 영문자 글쇠가 아니면 null. */
export function keyToJamo(k: Key): string | null {
  if (!k.code.startsWith('Key') || k.code.length !== 4) return null;
  const lower = k.code.slice(3).toLowerCase();
  if (!(lower in EN_CHAR_TO_KO)) return null;
  if (k.shift && lower in EN_SHIFT_TO_KO) return EN_SHIFT_TO_KO[lower];
  return EN_CHAR_TO_KO[lower];
}

/** 영어로 읽은 문자(대소문자 보존). KeyX 계열이 아니면 태그 형태가 필요하므로 규약 유지. */
export function keyToLatin(k: Key): string {
  const raw = k.code.startsWith('Key') && k.code.length === 4
    ? k.code.slice(3).toLowerCase()
    : k.code; // 라벨 규약: 이 경우는 charToKey 경로가 아니므로 원 라벨 보존
  return k.shift ? raw.toUpperCase() : raw;
}

/**
 * macOS CGEvent 가상 keycode(공개 헤더 Events.h의 kVK_ANSI_* 값) —
 * 패키지 macos 셸에서 엔진에 넘겨줄 때 쓰는 참조표. 브라우저 event.code 라벨 기준.
 * (Space 0x31, Return 0x24, Tab 0x30, Delete 0x33, Escape 0x35 포함)
 */
export const KVK_ANSI: Readonly<Record<string, number>> = {
  KeyA: 0x00, KeyS: 0x01, KeyD: 0x02, KeyF: 0x03, KeyH: 0x04, KeyG: 0x05,
  KeyZ: 0x06, KeyX: 0x07, KeyC: 0x08, KeyV: 0x09, KeyB: 0x0b,
  KeyQ: 0x0c, KeyW: 0x0d, KeyE: 0x0e, KeyR: 0x0f,
  KeyY: 0x10, KeyT: 0x11,
  Digit1: 0x12, Digit2: 0x13, Digit3: 0x14, Digit4: 0x15, Digit6: 0x16,
  Digit5: 0x17, Equal: 0x18, Digit9: 0x19, Digit7: 0x1b, Minus: 0x1a,
  Digit8: 0x1c, Digit0: 0x1d,
  KeyO: 0x1f, KeyU: 0x20, BracketLeft: 0x21, KeyI: 0x22, KeyP: 0x23,
  KeyL: 0x25, KeyJ: 0x26, Quote: 0x27, KeyK: 0x28, Semicolon: 0x29,
  Backslash: 0x2a, Comma: 0x2b, Slash: 0x2c, KeyN: 0x2d, KeyM: 0x2e,
  Period: 0x2f, Tab: 0x30, Space: 0x31, Enter: 0x24, Backspace: 0x33,
  Escape: 0x35,
};
