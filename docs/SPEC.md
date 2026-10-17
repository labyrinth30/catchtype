# Catchtype 프로젝트 (가칭)

한/영 상태 잘못 둔 채 친 키를 치는 도중에 자동으로 고쳐주는 도구. 원작(catchtype.com)을 아이디어 참고용으로 삼되 **모두 새로 구현한다**.

## 아키텍처

```
packages/engine/    ← 핵심 판단 로직 (순수 TS, 의존성 없음)  ✅ 구현 완료
packages/macos/     ← CGEventTap 쉘 (Swift) — 엔진을 임베드 후 후킹 (미구현)
packages/cli/       ← 터미널 테스트용 (엔진 검증)  ✅ 구현 완료
packages/web/       ← 데모 페이지 (선택, 나중에)
```

## 엔진 사양 (v1) — 구현 완료 (2026-10-17)

### 입력 — 구현: `packages/engine/src/layout.ts`
- 좌우변식(두벌식) 키 코드 시퀀스: 정규화 Key `{code: 'KeyA'|'Space'|…, shift}` (브라우저 `event.code` 계열)
- `charToKey`(타이핑 문자) / `keyToJamo`(두벌식 자모) / `keyToLatin`(영문) 변환
- `KVK_ANSI`: macOS CGEvent 가상 keycode ↔ event.code 참조표 (macOS 셸용)
- 현재 언어 상태 추정값 (`ko` | `en`) — `processText`가 세션 내 확정 판단으로 자동 갱신

### 두벌식 조합기 — 구현: `packages/engine/src/hangul.ts`
- 표준 IME 조합 규칙 순수 함수 구현: 받침 회수(ㅎㅏㅅㅔ→하세요), 복모음 합성(ㅜ+ㅓ→ㅝ —
  받침 없는 live syllable에서도 병합, 실 IME 동작), 겹받침 분해(ㄺ+ㅏ→ㄹ확정+ㄱ초성),
  쌍자모 합성(ㄱㄱ→ㄲ), 복합 종성 직접 수용(decompose 역산용)
- **프로퍼티 테스트: 전체 11,172 완성형 음절 roundtrip (compose∘decompose = id) 통과**

### 판단 규칙 (실시간, 단어 단위) — 구현: `packages/engine/src/engine.ts`
- 키 런(영문자 토큰)마다 en 읽기와 ko 읽기를 동시 판정
- 근거(basis) 등급: `dict`(사전 일치, 0.95) > `acronym`(2~4자 대문자, 0.8) >
  `jamo-run`(ㅋㅎㅠㅜㅡ 반복, 0.7) > `stats`(자모 바이그램 코퍼스 허용집합, 0.75) > `prefix`(타이핑 중, 0.55)
- **v1 우선순위에서 실제 구현으로 바뀐 부분**: "현재 언어로 말이 되면 무조건 통과"는
  false positive가 커서, **충돌 시 근거 등급 우선(basis-trumps-state)** 으로 조정:
  1) 한쪽만 유효 → 그쪽으로 (상태 전환 신호 동반)
  2) 둘 다 유효 → 근거 등급 고혹; 같으면 **빈도 가중치 3배 역전 시에만** 반대쪽 승, 아니면 현상태 유지
     - **v1.1**: 4배 → 3배 완화. 'dp vs 에'(3.97배)·'rh vs 고'(3.98배) 같은 충돌이 0.008~0.02
       미달로 놓치던 것을 되돌림. 전체 en사전 대상 스캔에서 역전 추가 쌍은 소수(약 26쌍,
       전부 빈도 순위 하위 잡음 단어)이고 흔한 영어 단어는 하나도 영향 없음.
  3) 둘 다 무효 → 단어 내부 분할(mixed): 앞/뒤 세그먼트가 각각 **완성 근거**(사전·약어·자모반복,
     통계·접두어는 불인정 — 'anㄴㅎ난테' 잡문자 방지), 2키 이상, 언어 상이일 때만. 예: `AIfh` → `AI로`
     - **v1.1 조사 결합 분할**: 뒤세그먼트가 2키 고빈도 조사(도/에/…, 사전 일치 + 가중치 0.9↑)면
       앞세그먼트에 완성 근거가 없어도 분할 인정 (`testeh`→`test+도`, `READMEdp`→`README+에`).
       앞세그먼트 2키일 때는 뒤세그먼트도 2키여야 한다(고전 규칙 유지). 세그먼트 스캔 순서는
       [반대 언어, 현재 언어]를 먼저 — 판정을 뒤집는 mixed가 등점수 경합에서 이긴다.
     - 반대 언어 전체 읽기가 최약 근거(통계)뿐이고 all-dict mixed가 있으면 mixed가 이긴다
       (사전 일치 > 통계 — 근거 등급 논리와 일관).
  4) 그래도 무효 → fallback 통과 (오타/고유명사)
     - **v1.1 카멜케이스 보호**: 한국어 상태에서 대문자 시작 카멜케이스('Figma')가 en사전에
       (접두어조차) 없고 ko 읽기가 통계·자모런 근거로 이기려 하면 fallback 통과 —
       고유명을 ko통계로 갈아치우는 오탐 차단. 약어(TODO·DP)와 ko사전 히트는 제외.
- 자판 런 폴백 (한국어 상태 전용): en 쪽 완전 무근거 + 전 글쇠 자모 매핑 성공이면
  두벌식 자모로 읽어 통과 (`asdf`→`ㅁㄴㅇㄹ`, `zzqq`→`ㅋㅋㅃ` — 키보드 슬랩/연습 표현)
- 비밀번호 안전: 문자 클래스 3종 이상 혼용 토큰은 판정하지 않고 그대로 통과 + `passwordSuspect` 플래그.
  2종 혼용('Catch22', 'abc123')은 평범한 문장과 구분 불가하여 판정 계속 — **오차 허용 명시**
- 통계 판정은 **조합 전 타이핑 자모 시퀀스**에 대해 검사 (조합 출력 재분해는 쌍자모 합성(ㄷㄷ→ㄸ)이
  roundtrip을 깨뜨려 오판 유발 — 구현 중 발견한 트레이드오프)

### 판단 자료 — 구현: `packages/engine/data/` + `scripts/build-data.ts`
- 한국어: FrequencyWords ko_50k (OpenSubtitles 2018) → 49,313 단어 + 자모 바이그램 825종(빈도≥30)
  - **한계**: 부제어근 코퍼스라 활용형·조사 결합형이 대부분. 표준어 사전(national institute dict)이
    더 정확하겠지만 라이선스 확인 필요 — 현재는 stats 바이그램 경로가 활용형을 커버
- 영어: google-10000-english (no-swears) → 9,868 단어
  - **v1.1 개발 용어 보강**: `EXTRA_EN_WORDS`(engine.ts, 45개 — git/npm/yaml/json/typescript 등
    google-10000 누락 개발 용어)를 `augmentDicts()`로 런타임 병합. `processText`는 기본 적용
    (`noAugment: true`로 끌 수 있음), `judgeWord` 직접 호출자는 보강본을 직접 넘겨야 한다.
    보강 단어 가중치는 인공 순위(상위 25% 수준)라 흔한 단어와 빈도 역전을 일으키지 않는다.
- 사전 값 규약: **값이 클수록 흔한 단어** (EN은 순위를 역산 저장). 처음엔 순위 그대로 저장했다가
  빈도 역전 판정이 전부 반대로 나오는 버그가 있었음 — 규약 문서화 후 수정
- 출처·라이선스: `packages/engine/data/LICENSES.md` (raw 소스는 `data/raw/`에 보관, 커밋 대상)
- 데이터 재생성: `cd packages/engine && bun scripts/build-data.ts` (네트워크 필요 없음, raw 파일 필요)

### 출력 — 구현
- `processText(input, {initialLang, dicts})` → `{text, initialLang, finalLang, words[], passwordSuspect}`
- 단어별 판정 근거(`reason`: dict/acronym/jamo-run/stats/alt-hit/both-keep/both-alt/mixed/fallback/password-suspect) + confidence — 디버그용
- `finalLang` = 세션 최종 상태 (macOS 앱이 시스템 입력 소스 전환에 사용)

### CLI — 구현: `packages/cli/src/catchtype.ts`
```
echo "dkssudgktpdy" | catchtype            # → 안녕하세요
catchtype --start ko < input.txt           # 시작 상태 지정
catchtype --debug < input.txt              # 단어별 판정 JSON (stderr)
catchtype --password-skip < pw.txt         # 비밀번호 통과 시 exit 3
```

## macOS 앱 요구사항 (미구현 — 설계 방침)

- **터미널 앱이 1등 시민**: CGEventTap은 앱 종류 무관 동작하므로 기본 타겟을 터미널로 한다.
  - 대상 터미널 리스트(기본: Terminal, iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm)를
    설정으로 노출 — 켜기/끄기 토글, 앱별 on/off
  - **예외처리**: 비밀번호 프롬프트(sudo/ssh/su)는 (a) 앱 이름 방어 + (b) 프롬프트 휴리스틱
    (`password:`, `PIN:` 라인 감지 시 일시 중지) 이중 방어. 엔진의 passwordSuspect 플래그도 함께 사용
  - 터미널에서는 확정 문자열을 CGEvent键盘 이벤트로 SEND하는 대신, 가능하면
    **파스티전 pasteboard 삽입**(⌘V 시뮬레이션)도 고려 — 터미널별 호환성 실험 필요
- Swift + CGEventTap (입력 감시 및 수정), Accessibility 권한 요청
- "비밀번호 필드" 동작 금지: `AXUIElement` 계층 확인 (원작 방식 — 개념 참고)
- 백그라운드 상주, 최초 실행 Accessibility 권한 안내 얼럿
- 확정 문자열을 앱에 직접 SEND 하기 위해 `CGEvent` 키 이벤트 생성 —
  `KVK_ANSI` 참조표(engine이 export)로 keycode 변환

## 테스트 전략 — 구현 (bun test, 75개)

- 엔진 단위: layout(두벌식 표·shift·역산), hangul(조합 규칙 + 11,172음절 roundtrip),
  dictionary(이분 탐색·빈도 가중), engine(판정 시나리오), regression-v11(v1.1 결함 회귀),
  cli(spawnSync end-to-end)
- 판정 시나리오: dkssudgktpdy→안녕하세요, AIfh→AI로(혼합), 사전 없는 활용형(통계 경로),
  이모티콘 자모, 충돌 우열(banana/music/server/go), 상태 전환 신호, 비밀번호 스킵,
  오탐 방어(영어 문장은 한국어 상태에서도 그대로 통과), 공백/개행/부호 보존
- **v1.1 회귀(regression-v11.test.ts)**: QA-20261011 원작 데모 4케이스(test+도 mixed,
  Figma 카멜케이스 보호, README+에 빈도 역전, git/npm/ls 사전 보강) + 엣지(2키/2키 고전
  분할 유지, 조사 결합 fallback분할, 잡문자 분할 금지, 흔한 영어 충돌 유지, augment idempotent)
- 테스트 벡터는 손으로 쓰지 않고 layout 역산표(`KO2EN`)로 인코딩 — 벡터 오타 방지
- macOS는 맥북에서: Codex CLI에게 맡기고, 실제 타이핑 테스트는 소유자(사람) 수행

## 배포/팀 규칙

- 이 repo는 GitHub에 push (공용 repo)
- deploy는 별도(개인 앱 배포이므로 서버에 상주시키지 않음); 웹 데모만 `/catchtype/` 라우트로 (nginx 기존 블록에 삽입)

## 남은 결정 사항 (open questions)

1. **ko 사전 품질**: 자막 코퍼스 기반이라 구어체에 치우침. 정제된 한국어 어휘목록
   (국립국어원 등)으로 교체할지 — 라이선스 확인 후 결정
2. **빈도 역전 임계(4배)**: 실사용 데이터로 보정 필요. 사용자별 사전 학습(개인 단어 추가)도 고려
3. **prefix 근거의 실시간 활용**: 현재는 단어 완성 단위 판정. CGEventTap 실시간 스트림에서는
   타이핑 도중 prefix 근거로 "조용히 대기"하는 단계적 판정이 필요 (macOS 셸 구현 시 설계)
4. **터미널 SEND 방식**: CGEvent 키 재생 vs pasteboard 삽입 — 앱별 호환성 실험 후 결정
