# Catchtype macOS — 첫 실행 체크리스트 (소유자용)

Mac에서 최초 설치 → 검증까지 순서대로. 소요 약 10분.

## 0. 사전 확인

- [ ] macOS 13 (Ventura) 이상: `sw_vers -productVersion`
- [ ] Xcode Command Line Tools: `xcode-select -p` (없으면 `xcode-select --install`)
- [ ] swift 확인: `swift --version` → 5.9 이상

## 1. 빌드

```bash
cd ~/catchtype/packages/macos     # repo clone 위치에 맞게
scripts/build.sh --release
```

- [ ] `swift build -c release` 가 오류 없이 끝나는가
- [ ] `swift build -c release --show-bin-path`로 나온 디렉토리에
      `catchtype`(CLI)과 `CatchType`(앱)이 있는가

> 첫 빌드는 사전 임베드 컴파일로 몇 분 걸린다. 이후 증분 빌드는 빠르다.

## 2. CLI 검증 (앱 없이 엔진만)

```bash
BIN=$(swift build -c release --show-bin-path)
echo 'dkssudgktpdy' | $BIN/catchtype               # → 안녕하세요
echo 'hello' | $BIN/catchtype --start ko           # 그대로 hello 출력
echo 'npm testeh dmlwk' | $BIN/catchtype --start ko # → npm test도 의자
printf 'Tr0ub4dor&3\n' | $BIN/catchtype --password-skip; echo "exit=$?"  # exit=3
```

- [ ] 네 줄 모두 예상 출력과 같은가 (특히 마지막 exit code 3)
- 실패하면 `--debug` 붙여 단어별 판정 근거를 확인하고 BUILD-TEST.md 참조.

## 3. 앱 설치 + 첫 실행 (권한)

```bash
scripts/install.sh
```

이 스크립트가:
1. release 빌드 확인
2. `catchtype` CLI를 `/usr/local/bin`에 심볼릭 (sudo 물음)
3. `CatchType.app` 을 `/Applications` 에 복사
4. LaunchAgent 등록 — 로그인 시 자동 시작 + 죽으면 재시작

- [ ] 설치 후 자동으로 앱이 뜬다. **손쉬운 사용 권한 얼럿이 나오면**:
      1. 시스템 설정이 자동으로 열린다 (개인정보 보호 및 보안 → 손쉬운 사용)
      2. `+` 버튼 → `/Applications/CatchType.app` 추가 → 토글 ON
      3. 앱 얼럿의 **"다시 확인"** 클릭
- [ ] 상태표시줄에 `⌨` 아이콘이 보이는가 (권한 없으면 `⚠` — 2번 반복)

## 4. 교정 실전 테스트 (Terminal)

Terminal.app 을 열고 (기본 타겟 앱):

| # | 상태를 먼저 | 타이핑 | 기대 결과 |
|---|---|---|---|
| 1 | 영문 모드로 전환 | `dkssudgktpdy` 스페이스 | `안녕하세요 ` |
| 2 | 한국어 모드로 전환 | `hello` 스페이스 | `hello ` (그대로 — 오탐 아님) |
| 3 | 영문 모드 | `npm testeh` 스페이스 | `npm test도 ` |
| 4 | 영문 모드 | `READMEdp` 스페이스 | `README에 ` |
| 5 | 아무 모드 | `Figma 링크` 입력 | `Figma` 그대로 유지 |
| 6 | 아무 모드 | `asdf` 스페이스 (@ko) | `ㅁㄴㅇㄹ` |

- [ ] 6개 케이스 통과 (스페이스가 교정 후 생기는 걸 포함)
- [ ] 입력 지연이 체감되지 않는가 (런 끝에서 한 번만 교정되므로 즉각)

## 5. 비밀번호 방어 테스트 (**중요**)

```bash
# Terminal 에서:
sudo ls          # password: 프롬프트 — 여기에 비밀번호 입력
# → sudo 에러 메시지 없이 정상 통과해야 함 (교정이 비밀번호를 건드리지 않았는지)
ssh anywhere     # (실패해도 됨) password: 프롬프트에서 비밀번호 입력 테스트
```

- [ ] sudo/ssh 비밀번호가 오타 없이 정확히 입력되는가 (교정 시스템 개입 X)
- [ ] 웹 브라우저 로그인 폼(비밀번호 필드)에서도 확인 권장

> 방어 구조: AX 비밀번호 필드 감시 + 터미널 프롬프트 hold + 엔진 3종-문자클래스
> 스킵. 셋 중 하나라도 작동하면 교정이 꺼진다. 그런데도 이상하면:
> 상태표시줄 메뉴에서 "비밀번호 필드 방어 (AX)", "터미널 프롬프트 방어" 확인.

## 6. 앱별 토글 확인

상태표시줄 `⌨` 클릭 → 메뉴:

- [ ] "대상 앱" 리스트에서 Terminal / iTerm2 / Warp / Ghostty / Alacritty / kitty / WezTerm 확인
- [ ] 예: Terminal 끄고 → Terminal에 타이핑 → 교정 안 됨 확인
- [ ] iTerm2 켜고 → iTerm2에서 타이핑 → 교정 됨 확인
- [ ] 비터미널 앱(메모장, 브라우저 주소창 등)에서도 **교정이 안 일어나는지** 반드시 확인
      — 기본 설정은 터미널만 타겟이므로 다른 앱은 무조건 통과여야 함

## 7. 상태 갱신·세션 언어

- [ ] 상태표시줄 메뉴의 "세션 언어"가 타이핑에 따라 한국어/영어로 바뀌는지
- [ ] "현재 앱: 교정 ON/OFF"가 포어그라운드 앱 전환에 따라 바뀌는지

## 8. 자동 시작·로그

- [ ] `launchctl list | grep catchtype` → 등록 확인
- [ ] 재부팅 후에도 앱이 자동으로 뜨는가
- [ ] 로그: `/tmp/catchtype.log`, `/tmp/catchtype.err.log`

## 문제 발생 시

| 증상 | 확인 |
|---|---|
| 아이콘이 `⚠` | 손쉬운 사용 권한 — 시스템 설정에서 CatchType 토글 확인 |
| 교정이 안 됨 | 현재 앱이 "대상 앱" 목록에 켜져 있는지 / 메뉴 "현재 앱: 교정 ON" |
| 타이핑이 이상해짐 | 상태표시줄에서 즉시 Terminal 토글 OFF → `scripts/uninstall.sh` |
| 비밀번호 오타 | **즉시 OFF** + issue 등록 — 이중 방어를 끄고 재현 단계 기록 |
| 앱이 계속 죽음 | `/tmp/catchtype.err.log` 확인 |

## 제거

```bash
scripts/uninstall.sh
```

설정 파일은 남는다: `~/Library/Application Support/CatchType/config.json`
(완전 초기화하려면 이 파일도 삭제)
