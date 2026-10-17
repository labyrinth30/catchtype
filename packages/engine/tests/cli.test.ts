import { describe, test, expect } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const CLI = join(here, '..', '..', 'cli', 'src', 'catchtype.ts');

function run(input: string, args: string[] = []): { stdout: string; stderr: string; code: number } {
  const p = spawnSync(process.execPath, [CLI, ...args], {
    input,
    encoding: 'utf8',
    env: { ...process.env },
  });
  return { stdout: p.stdout, stderr: p.stderr, code: p.status ?? -1 };
}

describe('cli', () => {
  test('한글 잘못 친 영문 시퀀스를 교정', () => {
    const r = run('dkssudgktpdy\n');
    expect(r.stdout).toBe('안녕하세요\n');
    expect(r.code).toBe(0);
  });

  test('한영 혼합 문장', () => {
    const r = run('AIfh ehdhkwnj\n', ['--start', 'en']);
    expect(r.stdout).toBe('AI로 도와줘\n');
  });

  test('영어 상태 유지 케이스', () => {
    const r = run('hello world\n', ['--start', 'ko']);
    expect(r.stdout).toBe('hello world\n');
  });

  test('--debug가 단어별 판정을 stderr로', () => {
    const r = run('dkssudgktpdy\n', ['--debug']);
    expect(r.stdout).toBe('안녕하세요\n');
    expect(r.stderr).toContain('"reason"');
    expect(r.stderr).toContain('finalLang');
  });

  test('--start ko로 시작', () => {
    const r = run('go\n', ['--start', 'ko']);
    expect(r.stdout).toBe('해\n');
  });

  test('비밀번호 토큰은 그대로 통과', () => {
    const r = run('Tr0ub4dor&3\n');
    expect(r.stdout).toBe('Tr0ub4dor&3\n');
  });
});
