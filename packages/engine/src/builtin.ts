/**
 * 내장 데이터 로더(번들 데이터 읽기). 엔진 코어는 I/O가 없고, 이 모듈만
 * 파일 읽기를 써서 packages/engine/data/ 의 사전·통계를 Engine 판정 자료로 만든다.
 * 데이터 생성/출처/라이선스: scripts/build-data.ts 와 data/LICENSES.md
 */
import { buildDict, type Dict } from './dictionary';
import type { Dicts } from './engine';

function parseTsv(text: string): [string, number][] {
  const entries: [string, number][] = [];
  for (const line of text.split('\n')) {
    if (!line) continue;
    const tab = line.indexOf('\t');
    if (tab === -1) continue;
    const w = line.slice(0, tab);
    const f = Number(line.slice(tab + 1));
    entries.push([w, Number.isFinite(f) ? f : 0]);
  }
  return entries;
}

function parseBigrams(text: string): Set<string> {
  const out = new Set<string>();
  for (const line of text.split('\n')) {
    if (line) out.add(line);
  }
  return out;
}

async function readData(name: string): Promise<string> {
  const url = new URL(`../data/${name}`, import.meta.url);
  const b = (globalThis as { Bun?: { file(p: URL): { text(): Promise<string> } } }).Bun;
  if (!b) {
    throw new Error(
      'loadBuiltinDicts needs Bun (bun test / bun run). ' +
      'For other runtimes, read data files yourself and call buildDict().',
    );
  }
  return b.file(url).text();
}

let cache: Dicts | null = null;

/** data/ 번들을 읽어 판정 자료(Dicts) 구성. 캐싱됨. */
export async function loadBuiltinDicts(): Promise<Dicts> {
  if (cache) return cache;
  const [enText, koText, bgText] = await Promise.all([
    readData('en_words.txt'),
    readData('ko_words.txt'),
    readData('ko_bigrams.txt').catch(() => ''),
  ]);
  const bigrams = bgText ? parseBigrams(bgText) : undefined;
  cache = {
    en: buildDict('en', parseTsv(enText)),
    ko: buildDict('ko', parseTsv(koText)),
    koBigrams: bigrams,
  };
  return cache;
}
