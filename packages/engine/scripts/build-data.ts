/**
 * 사전·통계 데이터 빌드 스크립트 — raw 공개 데이터를 engine이 쓰는 형식으로 정규화.
 * 재실행 가능(idempotent). 런타임(엔진/CLI)은 이 스크립트를 절대 호출하지 않는다.
 *
 * 출처 (수동 다운로드 → data/raw/ 저장, 이 스크립트는 그 파일만 읽음):
 *  - en: data/raw/en_raw.txt  = google-10000-english (no-swears)
 *      https://github.com/first20hours/google-10000-english  (MIT 라이선스 저장소)
 *  - ko: data/raw/ko_raw.txt  = FrequencyWords ko_50k
 *      https://github.com/hermitdave/FrequencyWords (MIT) — OpenSubtitles 2018
 *      코퍼스 기반 빈도 (CC BY-SA / TOS 준수, 저장소 README 참조)
 *
 * 출력:
 *  - data/en_words.txt : 단어 \t 순위
 *  - data/ko_words.txt : 단어 \t 빈도
 *  - data/ko_bigrams.txt : 자모 바이그램(코퍼스에서 연속 등장, 최소빈도 이상)
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { decomposeText } from '../src/hangul';

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, '..', 'data');
const rawDir = join(dataDir, 'raw');

const HANGUL_ONLY = /^[가-힣]+$/; // 완성형 음절만
const LATIN_ONLY = /^[a-z]+$/;
const BIGRAM_MIN_COUNT = 30; // 코퍼스 노이즈(오탈자, 외래어 표기) 컷

// 사전 값 규약: 값은 항상 "빈도류" (클수록 흔한 단어). EN은 순위를 역산해
// (총단어수 - 순위 + 1)로 저장한다 — 두 언어 사전이 같은 방향 의미를 갖게.
function buildEn(): string {
  const lines = readFileSync(join(rawDir, 'en_raw.txt'), 'utf8').split('\n');
  const seen = new Set<string>();
  const words: string[] = [];
  for (const raw of lines) {
    const w = raw.trim().toLowerCase();
    if (!w || seen.has(w)) continue;
    if (!LATIN_ONLY.test(w)) continue;
    if (w.length < 2) continue; // 1글자는 약어 판정 경로에 맡긴다
    seen.add(w);
    words.push(w);
  }
  const total = words.length;
  // 순위 1(최빈도) → 값 total, 순위 total → 값 1 (클수록 흔함)
  return words.map((w, i) => `${w}\t${total - i}`).join('\n') + '\n';
}

function buildKo(): string {
  const lines = readFileSync(join(rawDir, 'ko_raw.txt'), 'utf8').split('\n');
  const out: string[] = [];
  const seen = new Set<string>();
  const bigrams = new Map<string, number>();
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    // FrequencyWords 형식은 '단어 빈도' 공백 구분(탭 아님) — 탭도 허용
    const sep = Math.max(line.lastIndexOf('\t'), line.lastIndexOf(' '));
    if (sep === -1) continue;
    const w = line.slice(0, sep);
    const f = Number(line.slice(sep + 1));
    if (!HANGUL_ONLY.test(w) || !Number.isFinite(f) || f <= 0) continue;
    if (!seen.has(w)) {
      seen.add(w);
      out.push(`${w}\t${f}`);
    }
    // 빈도 가중 바이그램 수집(어순 빈도가 아니라 자모 연쇄 허용집합이 목적)
    const jamo = decomposeText(w);
    for (let i = 0; i + 1 < jamo.length; i++) {
      const bg = jamo[i]! + jamo[i + 1]!;
      bigrams.set(bg, (bigrams.get(bg) ?? 0) + f);
    }
  }
  const bgOut: string[] = [];
  for (const [bg, count] of bigrams) {
    if (count >= BIGRAM_MIN_COUNT) bgOut.push(bg);
  }
  bgOut.sort();
  writeFileSync(join(dataDir, 'ko_bigrams.txt'), bgOut.join('\n') + '\n');
  console.log(`ko_bigrams.txt: ${bgOut.length} bigrams (min count ${BIGRAM_MIN_COUNT})`);
  return out.join('\n') + '\n';
}

mkdirSync(dataDir, { recursive: true });
const en = buildEn();
const ko = buildKo();
writeFileSync(join(dataDir, 'en_words.txt'), en);
writeFileSync(join(dataDir, 'ko_words.txt'), ko);
console.log(`en_words.txt: ${en.split('\n').length - 1} entries`);
console.log(`ko_words.txt: ${ko.split('\n').length - 1} entries`);
