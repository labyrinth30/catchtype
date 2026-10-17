/**
 * 사전 모듈 — 순수 자료구조. 런타임 I/O 없음(데이터 로딩은 builtin.ts가 담당).
 * 판정에 필요한 질의: 완전 일치(hasWord), 접두어 존재(hasPrefix),
 * 빈도 가중치(weightOf — 두 언어가 모두 "말이 될 때" 우열 판정용).
 */
import type { Lang } from './layout';

export interface Dict {
  readonly lang: Lang;
  /** word → 빈도(또는 순위) */
  readonly words: Map<string, number>;
  /** 오름차순 정렬된 단어 배열(접두어 이분 탐색용) */
  readonly sorted: string[];
  /** word → 0~1 정규 빈도 가중치(최빈도 단어 = 1). 값 내림차순 순위 기반. */
  readonly weights: Map<string, number>;
}

function norm(lang: Lang, w: string): string {
  return lang === 'en' ? w.toLowerCase() : w;
}

export function buildDict(lang: Lang, entries: Iterable<readonly [string, number]>): Dict {
  const words = new Map<string, number>();
  for (const [raw, freq] of entries) {
    const w = norm(lang, raw);
    if (!w) continue;
    const prev = words.get(w);
    if (prev === undefined || freq > prev) words.set(w, freq);
  }
  const sorted = [...words.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  // 규약: 값이 클수록 흔한 단어. 내림차순 순위 기반 0~1 가중치.
  const byFreq = [...words.entries()].sort((a, b) => b[1] - a[1]);
  const n = byFreq.length;
  const weights = new Map<string, number>();
  byFreq.forEach(([w], i) => weights.set(w, (n - i) / n));
  return { lang, words, sorted, weights };
}

export function hasWord(d: Dict, w: string): boolean {
  return d.words.has(norm(d.lang, w));
}

/** 사전에 w를 접두어로 갖는 단어가 존재하는가(타이핑 도중 판정용) */
export function hasPrefix(d: Dict, w: string): boolean {
  const t = norm(d.lang, w);
  if (!t) return false;
  let lo = 0;
  let hi = d.sorted.length;
  while (lo < hi) {
    const mid = (lo + hi) >>> 1;
    if (d.sorted[mid] < t) lo = mid + 1;
    else hi = mid;
  }
  return lo < d.sorted.length && d.sorted[lo].startsWith(t);
}

/** 빈도 가중치(0~1). 없는 단어는 undefined. */
export function weightOf(d: Dict, w: string): number | undefined {
  return d.weights.get(norm(d.lang, w));
}

export function dictSize(d: Dict): number {
  return d.words.size;
}
