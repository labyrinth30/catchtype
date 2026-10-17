import { describe, test, expect } from 'bun:test';
import { loadBuiltinDicts } from '../src/builtin';
import { processText } from '../src/engine';

describe('v1.1.1 CamelCase 보호 — 두 상태 모두', async () => {
  const dicts = await loadBuiltinDicts();
  const run = (s: string, lang: 'ko' | 'en') => processText(s, { initialLang: lang, dicts }).text;

  test('@en: Figma 데모 문장', () => {
    expect(run('Figma fldzm qhsoemflfrpdy', 'en')).toBe('Figma 링크 보내드릴게요');
  });
  test('@ko: Figma 유지', () => {
    expect(run('Figma 링크 보내드릴게요', 'ko')).toBe('Figma 링크 보내드릴게요');
  });
  test('@en: GitHub + 한글 혼합', () => {
    expect(run('GitHub에서 PR 날렸어', 'en')).toBe('GitHub에서 PR 날렸어');
  });
  test('@en: 사전 있는 대문자 단어 Zoo 유지', () => {
    expect(run('Zoo에 갔어', 'en')).toBe('Zoo에 갔어');
  });
  test('@en: 약어 TODO 유지 (카멜케이스 아님)', () => {
    expect(run('TODO 확인해줘', 'en')).toBe('TODO 확인해줘');
  });
  test('@en: notion 소문자 고유명 유지', () => {
    expect(run('notion에서 페이지 복사해줘', 'en')).toBe('notion에서 페이지 복사해줘');
  });
  test('@en: Slack 유지', () => {
    expect(run('Slack으로 공유해', 'en')).toBe('Slack으로 공유해');
  });
});
