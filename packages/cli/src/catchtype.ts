#!/usr/bin/env bun
/**
 * catchtype CLI — 잘못된 상태로 두벌식/QWERTY 섞어 친 입력을 교정한다.
 *
 * usage:
 *   echo "dkssudgktpdy" | catchtype           # → 안녕하세요
 *   echo "AIfh hello"   | catchtype --start ko
 *   catchtype --debug   < input.txt           # 단어별 판정 근거 출력
 *   catchtype --password-skip < passwords.txt  # 비밀번호 의심 토큰 통과 플래그
 *
 * flags:
 *   --start <ko|en>   시작 언어 상태 (기본 en)
 *   --debug           단어별 판정 JSON을 stderr로
 *   --password-skip   비밀번호 의심 토큰을 그대로 통과하고 exit code 3
 *                     (기본 동작이기도 함 — 플래그는 문서화/확인용)
 *   --help
 */
import { loadBuiltinDicts, processText, type Lang } from '@catchtype/engine';

function parseArgs(argv: string[]): {
  start: Lang;
  debug: boolean;
  passwordSkip: boolean;
  help: boolean;
} {
  const opts = { start: 'en' as Lang, debug: false, passwordSkip: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === '--start') opts.start = (argv[++i] === 'ko' ? 'ko' : 'en') as Lang;
    else if (a === '--debug') opts.debug = true;
    else if (a === '--password-skip') opts.passwordSkip = true;
    else if (a === '--help' || a === '-h') opts.help = true;
  }
  return opts;
}

async function main(): Promise<void> {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(
      'catchtype — 한/영 상태 자동 교정 CLI\n' +
      'usage: catchtype [--start ko|en] [--debug] [--password-skip] < input\n',
    );
    return;
  }

  const input = await new Response(Bun.stdin.stream()).text();
  const dicts = await loadBuiltinDicts();
  const result = processText(input, { initialLang: opts.start, dicts });

  if (opts.debug) {
    for (const w of result.words) {
      console.error(
        JSON.stringify({
          raw: w.raw,
          output: w.output,
          lang: w.lang,
          switched: w.switched,
          reason: w.reason,
          confidence: Number(w.confidence.toFixed(2)),
          segments: w.segments,
        }),
      );
    }
    console.error(JSON.stringify({ initialLang: result.initialLang, finalLang: result.finalLang }));
  }

  process.stdout.write(result.text);
  if (opts.passwordSkip && result.passwordSuspect) {
    console.error('\n[catchtype] password-suspect tokens passed through unjudged');
    process.exit(3);
  }
}

 await main();
