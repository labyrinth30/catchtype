/**
 * 판정 엔진 — 순수 함수형, 런타임 I/O·네트워크 없음.
 *
 * 규칙(v1.1, docs/SPEC.md 우선순위 구현):
 *  1) 현재 언어로 읽은 읽기가 "말이 되면" 통과 (근거: 사전 일치 > 약어 > 자모 반복 > 통계)
 *  2) 아니면 반대 언어로 읽어 유효하면 그 단어만 반대 언어로 판정(상태 전환)
 *  3) 둘 다 유효하면 근거 등급이 높은 쪽 승; 같으면 현재 상태 유지.
 *     단, 둘 다 사전 일치이고 반대쪽 빈도 가중치가 3배 이상이면 반대쪽 승
 *     (흔한 영어 단어 vs 구석 한국어 단어 충돌을 실제 의도 쪽으로 되돌림).
 *  4) 둘 다 무효면 단어 내부 분할(mixed)을 시도: 앞/뒤 세그먼트 각각
 *     완성 근거(사전 일치·약어·자모반복)로 인정. 통계·접두어만으로는 세그먼트 불인정
 *     ('anㄴㅎ난테' 같은 잡문자 오판 방지), 두 세그먼트 언어 상이.
 *     - 뒤세그먼트 2키 이상(조사 결합형 허용: test+도, README+에), 앞세그먼트 2키면
 *       뒤세그먼트도 2키(고전 규칙 AIfh→AI+로 유지). 뒤세그먼트 3키 이상은 사전 일치만.
 *     - 세그먼트 순서는 [반대 언어, 현재 언어]를 먼저: verdict-forcing mixed
 *       ('testeh'→test+도, 'READMEdp'→README+에)는 반대 언어 결론을 내는 쪽이 우선.
 *  5) 그래도 무효면 그대로 통과(fallback — 오타/부호/고유명사. CamelCase가 en사전에
 *     없어도 대문자 시작 단어는 카멜케이스 보호로 fallback 통과 — 'Figma'가
 *     ko통계 읽기로 옮겨가는 오판 방지)
 *  비밀번호 의심 토큰(문자 클래스 3종 이상 혼용)은 판정하지 않고 통과 + 플래그.
 */
import {
  charToKey,
  keyToJamo,
  keyToLatin,
  type Key,
  type Lang,
} from './layout';
import { composeJamo, decomposeText } from './hangul';
import { type Dict, hasWord, hasPrefix, weightOf, buildDict } from './dictionary';

export { type Lang } from './layout';

/** 판정 근거. prefix는 "타이핑 도중이라 아직 유효"인 중간 상태만 해당. */
export type Basis = 'dict' | 'prefix' | 'acronym' | 'jamo-run' | 'stats' | 'none';

export interface Read {
  text: string;        // 해당 언어로 읽은 문자열
  basis: Basis;
  confidence: number;  // 0~1
  valid: boolean;
}

export interface SegmentInfo {
  raw: string;
  lang: Lang;
  text: string;
  basis: Exclude<Basis, 'prefix'>; // 세그먼트는 "완성 근거"만 인정
  confidence: number;
}

export interface WordDecision {
  raw: string;         // 입력(영문 키 문자열)
  output: string;      // 판정 결과 문자열
  lang: Lang;          // 이 단어의 확정 언어(세션 상태 갱신에 사용)
  switched: boolean;   // 세션 상태가 바뀌었는가
  reason: string;      // dict | acronym | jamo-run | stats | prefix | alt-hit | both-keep | both-alt | mixed | fallback | password-suspect
  confidence: number;
  segments: SegmentInfo[] | null;
  passwordSuspect: boolean;
}

export interface EngineResult {
  text: string;
  initialLang: Lang;
  finalLang: Lang;
  words: WordDecision[];
  passwordSuspect: boolean;
}

export interface Dicts {
  ko: Dict;
  en: Dict;
  /** 한국어 자모 바이그램 허용집합 (통계 판정용, 없으면 통계 경로 비활성) */
  koBigrams?: Set<string>;
}

/** 자모 반복 이모티콘 휴리스틱 (ㅋㅋ, ㅎㅎ, ㅠㅠ, ㅡㅡ, ㅜㅜ) */
const RUN_SET = new Set(['ㅋ', 'ㅎ', 'ㅠ', 'ㅡ', 'ㅜ']);
/**
 * 자판 런 폴백 판정 (한국어 상태 전용): en 쪽에 어떤 사전 근거도 없고
 * 전 글쇠가 두벌식 자모로 매핑될 때만 참. zzqq → ㅋㅋㅃ, asdf → ㅁㄴㅇㄹ 같은
 * 자판 연습·키보드 슬랩 표현을 잡는다. 영어 상태에서는 적용하지 않는다.
 */
const CONF = { dict: 0.95, acronym: 0.8, 'jamo-run': 0.7, prefix: 0.55, stats: 0.75 } as const;
/**
 * 충돌 시 빈도 가중치 역전 임계(3배): 'dp vs 에'(3.97배), 'rh vs 고'(3.98배) 같은
 * 단일 사전 충돌을 되돌리려면 4배로는 비좁다(원래 임계 통과 조건 wa >= wc*4에서
 * 0.008 미달로 놓침). 3배 임계로 내려도 사전 {fickme, fsoj} 검증에서
 * 흔한 영어 단어(빈도 상위)는 하나도 역전되지 않는다 — 역전은 소수(약 18쌍)에만 발생.
 */
const WEIGHT_FLIP_RATIO = 3;
/** 사전 보강용: 엔진이 판정에 쓰는 개발/토큰 용어(google-10000 누락분). v1.1. */
export const EXTRA_EN_WORDS: readonly string[] = [
  'git', 'npm', 'yaml', 'json', 'eslint', 'prettier', 'webpack',
  'typescript', 'javascript', 'bash', 'zsh', 'vim', 'nvim', 'sudo', 'curl',
  'docker', 'kubernetes', 'pytest', 'django', 'flask', 'golang', 'rust',
  'localhost', 'hostname', 'rebase', 'stash', 'fork', 'pypi', 'rubygems',
  'dotenv', 'vite', 'rollup', 'esbuild', 'bun', 'deno', 'jsx', 'tsx',
  'uuid', 'oauth', 'jwt', 'sdk', 'jdk', 'tokenizer', 'transpile',
];

/** 근거 등급 — 사전 일치가 최강, 통계가 최약(완성 근거 중). */
const BASIS_RANK: Record<Basis, number> = {
  dict: 5, acronym: 4, 'jamo-run': 3, stats: 2, prefix: 1, none: 0,
};

/**
 * 자모 반복(ㅋㅋ, ㅎㅎ…) 이외의 두벌식 고유 런: 두 언어로 읽었을 때 en 쪽은
 * 사전 히트도 접두어도 없고 ko 쪽은 자모로만 조합되는 경우(zzqq → ㅋㅌㅊㅍ,
 * asdf → ㅁㄴㅇㄹ). 자판 연습·키보드 슬랩 표현으로 실제 쓰인다.
 * en 읽기가 무효(사전 어느 경로도 못 맞춤) + ko 자모 전수 매핑 성공을 조건으로
 * 현재 한국어 상태에서만 통과시킨다 — 영어 상태에서는 en 쪽 근거가 우선.
 */
function isQwertyRunFallback(keys: readonly Key[], enRead: Read): boolean {
  if (enRead.basis !== 'none') return false;
  return keys.every((k) => keyToJamo(k) !== null);
}

/** ㅋㅎㅠㅜㅡ 반복 이모티콘 */
function isEmojiRun(text: string): boolean {
  if (text.length < 2) return false;
  const first = text[0]!;
  if (!RUN_SET.has(first)) return false;
  return [...text].every((ch) => ch === first);
}
const isJamoRun = isEmojiRun; // 기존 호환 이름 유지


/**
 * 통계 판정: 조합 전의 "타이핑된 자모 시퀀스"를 그대로 검사한다 (조합 출력을
 * 다시 분해하지 않는다 — ㄷㄷ→ㄸ 같은 쌍자모 합성이 분해 roundtrip을 깨기 때문).
 * 인접 자모 바이그램이 모두 코퍼스 허용집합에 속하면 "한글다운"으로 본다 (≥3 자모).
 * 사전에 없는 활용형(안녕하세요, 기다리고있습니다 등)을 잡기 위한 경로.
 */
function isPlausibleJamoSeq(jamo: readonly string[], bigrams?: Set<string>): boolean {
  if (!bigrams || bigrams.size === 0 || jamo.length < 3) return false;
  for (let i = 0; i + 1 < jamo.length; i++) {
    if (!bigrams.has(jamo[i]! + jamo[i + 1]!)) return false;
  }
  return true;
}

/** 영어 읽기: 대소문자 보존, 사전 비교는 소문자 */
function readEn(keys: readonly Key[], dict?: Dict, _bigrams?: Set<string>): Read {
  const text = keys.map(keyToLatin).join('');
  const low = text.toLowerCase();
  if (dict) {
    if (hasWord(dict, low)) return { text, basis: 'dict', confidence: CONF.dict, valid: true };
    if (hasPrefix(dict, low)) return { text, basis: 'prefix', confidence: CONF.prefix, valid: true };
  }
  if (/^[A-Z]{2,4}$/.test(text)) return { text, basis: 'acronym', confidence: CONF.acronym, valid: true };
  return { text, basis: 'none', confidence: 0, valid: false };
}

/** 한국어 읽기: 두벌식 자모 조합 → 완성형 문자열 */
function readKo(keys: readonly Key[], dict?: Dict, bigrams?: Set<string>): Read {
  const jamo: string[] = [];
  for (const k of keys) {
    const j = keyToJamo(k);
    if (j === null) return { text: '', basis: 'none', confidence: 0, valid: false };
    jamo.push(j);
  }
  const text = composeJamo(jamo);
  if (dict) {
    if (hasWord(dict, text)) return { text, basis: 'dict', confidence: CONF.dict, valid: true };
    if (hasPrefix(dict, text)) return { text, basis: 'prefix', confidence: CONF.prefix, valid: true };
  }
  if (isPlausibleJamoSeq(jamo, bigrams)) return { text, basis: 'stats', confidence: CONF.stats, valid: true };
  if (isJamoRun(text)) return { text, basis: 'jamo-run', confidence: CONF['jamo-run'], valid: true };
  return { text, basis: 'none', confidence: 0, valid: false };
}

function read(keys: readonly Key[], lang: Lang, dict?: Dict, bigrams?: Set<string>): Read {
  return lang === 'en' ? readEn(keys, dict, bigrams) : readKo(keys, dict, bigrams);
}

/**
 * 사전 보강(v1.1): EXTRA_EN_WORDS(개발 용어 등)를 en사전에 합쳐 Dicts 회선.
 * weightOf는 rank 기반이므로 보강 단어는 인공 순위로 넣어 흔한 단어와 충돌하지 않게 한다
 * (가중치 ~0.75 — 흔한 단어(1.0) 역전을 일으키지 않는 수준).
 * 자주 불리는 순수 함수이므로 입력 Dicts가 같으면 캐시한 결과를 돌려준다.
 */
let augCache: Dicts | null = null;
let augCacheRef: Dicts | null = null;
export function augmentDicts(dicts: Dicts): Dicts {
  // 캐시 규약: 같은 참조 입력·이미 보강된 입력·같은 크기 입력은 모두 캐시 결과를 반환한다
  // (augment∘augment = augment, 부수효과 없음). 크기가 다른 새 입력만 재계산한다.
  if (augCache && dicts === augCacheRef) return augCache;
  if (augCache && dicts === augCache) return augCache;
  if (augCache && dicts.en.words.size === augCache.en.words.size) return augCache;
  const entries: [string, number][] = [...dicts.en.words.entries()];
  const newOnes = EXTRA_EN_WORDS.filter((w) => !dicts.en.words.has(w));
  const rankBase = dicts.en.sorted.length;
  const rankScale = Math.max(1, Math.floor(rankBase / 4)); // 상위 25% 수준의 가중치
  newOnes.forEach((w, i) => entries.push([w, Math.max(1, rankBase + 1 - i * rankScale)]));
  const en = buildDict('en', entries);
  augCache = { ko: dicts.ko, en, koBigrams: dicts.koBigrams };
  augCacheRef = dicts;
  return augCache;
}

/** 완성된 세그먼트용 읽기 — 접두어·통계 근거는 불인정(아무 데나 자를 수 있게 됨) */
function readComplete(keys: readonly Key[], lang: Lang, dict?: Dict, bigrams?: Set<string>): Read {
  const r = read(keys, lang, dict, bigrams);
  if (r.basis === 'prefix' || r.basis === 'stats') {
    return { ...r, basis: 'none', confidence: 0, valid: false };
  }
  return r;
}

/**
 * 비밀번호 의심: 문자 클래스(대문자/소문자/숫자/기호) 3종 이상 혼용.
 * 2종 혼용은 평범한 문장·토큰('Catch22', 'abc123')과 구분이 안 되므로 판정을 계속한다.
 */
export function looksLikePassword(token: string): boolean {
  let classes = 0;
  if (/[A-Z]/.test(token)) classes++;
  if (/[a-z]/.test(token)) classes++;
  if (/[0-9]/.test(token)) classes++;
  if (/[^A-Za-z0-9]/.test(token)) classes++;
  return classes >= 3;
}

function mixedSegments(
  keys: readonly Key[],
  state: Lang,
  dicts: Dicts,
): { segments: SegmentInfo[]; confidence: number } | null {
  // v1.1 분할 정책:
  //  - 앞세그먼트 "완성 근거" 필수, 뒤세그먼트 2키 이상(조사 결합형 허용: test+도, README+에).
  //    단, 앞세그먼트가 2키이면 뒤세그먼트도 2키여야 한다(고전 규칙 유지: AIfh→AI+로).
  //  - 뒤세그먼트가 3키 이상이면 사전 일치만 인정 — 완전 접두 오분할('te|st'류) 차단.
  //  - 앞세그먼트는 반대 언어 "사전 prefix"도 인정한다: 'test'는 en사전 prefix이므로
  //    '<ko세그먼트> 도' 같은 반대 언어 사전 확정 부분 + 접두어 ko세그먼트 결합을 잡는다.
  //    (접두어·통계만으로 되는 분할은 금지 — 'anㄴㅎ난테' 잡문자 방지는 유지)
  //  - 세그먼트 순서는 [반대 언어, 현재 언어]를 먼저 스캔: 판정을 뒤집는 mixed
  //    ('testeh'→test+도, 'READMEdp'→README+에)가 [현재, 반대] 순서의 등점수 후보를 이기도록.
  let best: { segments: SegmentInfo[]; confidence: number } | null = null;
  let bestScore = -1;
  for (let i = 2; i <= keys.length - 2; i++) {
    for (const [l1, l2] of [
      [other(state), state],
      [state, other(state)],
    ] as [Lang, Lang][]) {
      const aRaw = keys.slice(0, i);
      const a = read(aRaw, l1, dicts[l1], dicts.koBigrams);
      if (!a.valid) continue;
      // 앞세그먼트가 "완성 근거"(dict·acronym)가 아니면(=prefix·stats만) 접두어 사용 조건 검사:
      // 반대 세그먼트는 반드시 사전 일치여야 한다 (아닐 시 이 분할은 불인정).
      const needsComplete = a.basis !== 'dict' && a.basis !== 'acronym';
      const bRaw = keys.slice(i);
      if (bRaw.length < 2) continue;
      // 앞세그먼트 2키면 뒤세그먼트도 2키여야 한다(고전 규칙: AIfh → AI+로).
      // 뒤세그먼트 3키 이상이면 앞세그먼트 3키 이상 + 사전 일치만 인정.
      if (i === 2 && bRaw.length > 2) continue;
      const b = read(bRaw, l2, dicts[l2], dicts.koBigrams);
      if (!b.valid) continue;
      if (needsComplete || bRaw.length >= 3) {
        // 둘 중 하나라도 "완전 확정" 조건 요구 시: 양쪽 모두 사전 일치여야 한다
        if (a.basis !== 'dict' || b.basis !== 'dict' || aRaw.length < 3 || bRaw.length > 2) continue;
      }
      const score = Math.min(a.confidence, b.confidence) * 100 + (a.confidence + b.confidence);
      if (score > bestScore) {
        bestScore = score;
        best = {
          segments: [
            { raw: keys.slice(0, i).map(keyToLatin).join(''), lang: l1, text: a.text, basis: a.basis as SegmentInfo['basis'], confidence: a.confidence },
            { raw: bRaw.map(keyToLatin).join(''), lang: l2, text: b.text, basis: b.basis as SegmentInfo['basis'], confidence: b.confidence },
          ],
          confidence: Math.min(a.confidence, b.confidence),
        };
      }
    }
  }
  if (best) return best;
  // v1.1 조사 결합 fallback분할: 앞세그먼트에 사전 근거가 없어도(README 등 fallback 통과
  // 접두 명사), 뒤세그먼트가 고빈도 한국어 조사(도/에/는/은/이/가/를/을/로 등, 2키,
  // 사전 일치 + 가중치 0.9 이상)일 때는 'READMEdp'→'README에' 혼합을 인정한다.
  // 앞세그먼트는 3키 이상, 언어는 현재 상태(그대로 통과), 뒤세그먼트는 반대 언어.
  for (let i = 3; i <= keys.length - 2; i++) {
    const bRaw = keys.slice(i);
    if (bRaw.length !== 2) continue;
    const altLang = other(state);
    const b = readComplete(bRaw, altLang, dicts[altLang], dicts.koBigrams);
    if (!b.valid || b.basis !== 'dict') continue;
    const w = weightOf(dicts[altLang], b.text);
    if (w === undefined || w < 0.9) continue;
    const aText = keys.slice(0, i).map(keyToLatin).join('');
    return {
      segments: [
        { raw: aText, lang: state, text: aText, basis: 'fallback' as SegmentInfo['basis'], confidence: 0 },
        { raw: bRaw.map(keyToLatin).join(''), lang: altLang, text: b.text, basis: b.basis as SegmentInfo['basis'], confidence: b.confidence },
      ],
      confidence: b.confidence,
    };
  }
  return null;
}

export function other(lang: Lang): Lang {
  return lang === 'ko' ? 'en' : 'ko';
}

/**
 * 충돌 해소: 둘 다 유효할 때 어느 쪽을 택할까.
 * 근거 등급이 높은 쪽 승 → 같으면 사전 일치 간 빈도 역전(3배) 검사 → 그래도 현상태.
 */
function resolveConflict(
  cur: Read,
  alt: Read,
  state: Lang,
  dicts?: Dicts,
): { pick: 'cur' | 'alt'; why: string } {
  const rc = BASIS_RANK[cur.basis];
  const ra = BASIS_RANK[alt.basis];
  if (ra > rc) return { pick: 'alt', why: 'both-alt(basis)' };
  if (ra < rc) return { pick: 'cur', why: 'both-keep(basis)' };
  if (cur.basis === 'dict' && dicts) {
    const wc = weightOf(dicts[state], cur.text);
    const wa = weightOf(dicts[other(state)], alt.text);
    if (wc !== undefined && wa !== undefined && wa >= wc * WEIGHT_FLIP_RATIO) {
      return { pick: 'alt', why: 'both-alt(freq)' };
    }
  }
  return { pick: 'cur', why: 'both-keep' };
}

/**
 * v1.1 카멜케이스/고유명 보호: 한국어 상태에서 대문자-시작 카멜케이스 토큰('Figma',
 * 'GitHub')을 쳤는데 en사전에(접두어조차) 없을 때, ko 읽기가 통계·자모런 근거로
 * 이기려 하면 오판이다 — 진짜 영어 고유명을 ko통계로 갈아치우는 실수.
 * 그런 토큰은 판정을 포기하고 그대로 통과(fallback)시킨다.
 * 조건: (a) raw가 대문자 1 + 소문자들 카멜케이스(약어 TODO·A와 구분), (b) 전 글쇠 라틴,
 * (c) en사전에 접두어 없음, (d) ko 읽기 근거가 stats 또는 jamo-run(사전 히트면 진짜
 * 단어이므로 제외 — 'Zoo'→'ㅈㅗㅗ'류 역시 사전 히트가 아니면 방해 안 함).
 */
function isCamelCaseProtected(keys: readonly Key[], cur: Read, raw: string, dict?: Dict): boolean {
  if (!/^[A-Z][a-z]+$/.test(raw)) return false;
  if (!dict) return false;
  if (hasPrefix(dict, raw.toLowerCase())) return false; // 사전 접두어도 없음
  if (cur.valid && cur.basis !== 'stats' && cur.basis !== 'jamo-run') return false;
  return cur.valid; // 이 보호는 ko(통계·자모런) 읽기가 이기려 할 때만 발동
}

/** 단어(영문자만으로 된 키 런) 하나를 판정. 세션 상태(state)를 받아 결정을 돌려준다. */
export function judgeWord(keys: readonly Key[], state: Lang, dicts?: Dicts): WordDecision {
  const raw = keys.map(keyToLatin).join('');
  const passthrough = (reason: string, lang: Lang, conf = 0): WordDecision => ({
    raw, output: raw, lang, switched: false, reason, confidence: conf, segments: null, passwordSuspect: false,
  });

  if (keys.length === 0) return passthrough('empty', state);

  if (looksLikePassword(raw)) {
    return { raw, output: raw, lang: state, switched: false, reason: 'password-suspect', confidence: 0, segments: null, passwordSuspect: true };
  }

  const cur = read(keys, state, dicts?.[state], dicts?.koBigrams);
  const alt = read(keys, other(state), dicts?.[other(state)], dicts?.koBigrams);

  // 카멜케이스 보호(v1.1): 한국어 상태에서 대문자 시작 단어가 en사전에 없어
  // ko통계가 이기려 할 때, en 무근거를 "고유명사"로 보고 그대로 통과시킨다.
  if (dicts && isCamelCaseProtected(keys, cur, raw, dicts.en)) {
    return passthrough('fallback', state);
  }

  // 자판 런 폴백: 한국어 상태 + en 쪽 완전 무근거 + 전 글쇠 자모 매핑 성공
  // (zzqq → ㅋㅌㅊㅍ, asdf → ㅁㄴㅇㄹ) — 어떤 유효 판정도 안 나왔을 때만 적용.
  if (
    state === 'ko' &&
    !cur.valid && !alt.valid &&
    isQwertyRunFallback(keys, cur) && isQwertyRunFallback(keys, alt)
  ) {
    const synthetic = readKo(keys, undefined, undefined);
    const text = composeJamo(keys.map((k) => keyToJamo(k)!));
    return {
      raw, output: text, lang: 'ko', switched: false,
      reason: 'jamo-run', confidence: synthetic.confidence || CONF['jamo-run'],
      segments: null, passwordSuspect: false,
    };
  }

  if (cur.valid && alt.valid) {
    const { pick, why } = resolveConflict(cur, alt, state, dicts);
    const chosen = pick === 'cur' ? cur : alt;
    const lang = pick === 'cur' ? state : other(state);
    return {
      raw, output: chosen.text, lang,
      switched: pick === 'alt',
      reason: why, confidence: chosen.confidence, segments: null, passwordSuspect: false,
    };
  }

  if (cur.valid) {
    return {
      raw, output: cur.text, lang: state, switched: false,
      reason: cur.basis, confidence: cur.confidence, segments: null, passwordSuspect: false,
    };
  }

  const mixed = dicts ? mixedSegments(keys, state, dicts) : null;

  // v1.1: 반대 언어 읽기가 최약 근거(통계)뿐이고, 사전 일치 세그먼트로 완성되는 혼합 분할이
  // 있으면 그쪽을 택한다 — 'testeh'(@en)는 ko통계 'ㅅㄷㄴㅅ도'보다 'test+도' 혼합이 옳다.
  // (사전 일치가 통계보다 근거 등급이 높다 — v1 우선순위 규칙 3과 같은 논리.)
  const weakAlt =
    alt.valid &&
    (alt.basis === 'stats' || alt.basis === 'jamo-run');
  if (weakAlt && mixed) {
    const allDict = mixed.segments.every((s) => s.basis === 'dict');
    const altLang = other(state);
    // 혼합이 반대 언어 결론(마지막 세그먼트가 alt 언어)일 때만 반대 읽기를 덮어쓴다
    const last = mixed.segments[mixed.segments.length - 1];
    if (allDict && last.lang === altLang) {
      return {
        raw,
        output: mixed.segments.map((s) => s.text).join(''),
        lang: altLang,
        switched: true,
        reason: 'mixed',
        confidence: mixed.confidence,
        segments: mixed.segments,
        passwordSuspect: false,
      };
    }
  }

  if (alt.valid) {
    return {
      raw, output: alt.text, lang: other(state), switched: true,
      reason: 'alt-hit', confidence: alt.confidence, segments: null, passwordSuspect: false,
    };
  }

  if (mixed) {
    const last = mixed.segments[mixed.segments.length - 1];
    return {
      raw,
      output: mixed.segments.map((s) => s.text).join(''),
      lang: last.lang,
      switched: last.lang !== state,
      reason: 'mixed',
      confidence: mixed.confidence,
      segments: mixed.segments,
      passwordSuspect: false,
    };
  }

  return passthrough('fallback', state);
}

function tokenize(input: string): string[] {
  // 공백 런을 보존하면서 비공백 토큰으로 분할
  return input.match(/\S+|\s+/g) ?? [];
}

/**
 * 전체 문장 처리. 공백/개행은 그대로 보존, 비공백 토큰은
 * - 비밀번호 의심 → 그대로 통과
 * - 그 외: 영문자 런은 판정, 나머지(숫자/부호) 런은 그대로 통과
 * 세션 언어 상태는 판정이 확정될 때만 갱신된다.
 */
export function processText(
  input: string,
  opts: { initialLang?: Lang; dicts?: Dicts; noAugment?: boolean } = {},
): EngineResult {
  const initialLang: Lang = opts.initialLang ?? 'en';
  let state = initialLang;
  let out = '';
  const words: WordDecision[] = [];
  let passwordSuspect = false;

  // v1.1: 사전 보강(개발 용어 등) 기본 적용. noAugment 로 원본 사전만 쓰는 보수 모드.
  const dicts = opts.dicts
    ? (opts.noAugment ? opts.dicts : augmentDicts(opts.dicts))
    : undefined;

  for (const token of tokenize(input)) {
    if (/^\s+$/.test(token)) {
      out += token;
      continue;
    }
    if (looksLikePassword(token)) {
      out += token;
      passwordSuspect = true;
      words.push({
        raw: token, output: token, lang: state, switched: false,
        reason: 'password-suspect', confidence: 0, segments: null, passwordSuspect: true,
      });
      continue;
    }
    // 토큰 내부를 영문자 런 / 비영문자 런으로 분리
    const runs = token.match(/[a-zA-Z]+|[^a-zA-Z]+/g) ?? [];
    for (const run of runs) {
      if (!/[a-zA-Z]/.test(run)) {
        out += run; // 숫자·부호: 두 언어 모두 통과
        continue;
      }
      const keys: Key[] = [];
      for (const ch of run) {
        const k = charToKey(ch);
        if (k) keys.push(k);
      }
      const decision = judgeWord(keys, state, dicts);
      out += decision.output;
      state = decision.lang;
      words.push(decision);
      if (decision.passwordSuspect) passwordSuspect = true;
    }
  }

  return { text: out, initialLang, finalLang: state, words, passwordSuspect };
}
