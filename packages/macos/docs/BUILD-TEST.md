# Catchtype macOS 셸 — 빌드·테스트 가이드

Swift Package Package.swift 하나로 CLI(`catchtype`)와 상태바 앱(`CatchType`)을 모두
빌드한다. **Xcode 프로젝트 불필요** — `swift build`만으로 충분.

## 요구 사항

| 항목 | 값 |
|---|---|
| macOS | 13 Ventura 이상 |
| Swift | 5.9 이상 (Xcode Command Line Tools 또는 swift.org 툴체인) |
| 메모리 빌드 시 | 사전 60k 단어를 소스 임베드 — 첫 빌드 수 분 소요 |

툴체인이 없으면: `xcode-select --install`

## 빌드

```bash
cd packages/macos
swift build                 # debug
swift build -c release      # release (상용 권장 — 엔진 판정이 실시간 경로에 있음)
scripts/build.sh --release  # 위와 동일 (래퍼)
```

산출물 위치:

```bash
swift build -c release --show-bin-path
# .../almighty-apple-products/debug|release 아래
#   catchtype         ← CLI
#   CatchType         ← 상태바 앱 실행 파일
```

> **Linux CI 참고**: `Sources/CatchType/*.swift`는 `#if os(macOS)`로 감싸져 있어
> Linux에서도 `swift build`가 실패하지 않는다. 앱 로직은 macOS에서만 컴파일·링크된다.

## 테스트

```bash
cd packages/macos
swift test                   # macOS 전체 (Linux에서는 CatchTypeCore 테스트만 해당)
```

테스트 스위트 (TS 엔진 82개 테스트에 대응하는 Swift 포트 + 골든 회귀):

| 파일 | 내용 |
|---|---|
| `HangulTests` | 조합기 규칙 + **전체 11,172 완성형 roundtrip** |
| `LayoutTests` | 두벌식 표·shift·KVK keycode |
| `EngineTests` | 사전 질의·비밀번호 휴리스틱·augment 계약 |
| `GoldenTests` | **TS 엔진에서 뽑은 81개 실측 벡터와 비교** — 판정 리그레션 잠금 |

골든 벡터 재생성 (엔진 규칙 변경 후):

```bash
cd packages/macos/Scripts && bun rebuild-golden.ts   # TS 엔진 실행 → Swift 배열 리터럴 출력
# 출력 → Tests/CatchTypeCoreTests/GoldenTests.swift의 goldens 배열에 붙여넣기
```

사전 데이터 재생성 (TS 빌드 파이프라인과 동일):

```bash
cd packages/engine && bun scripts/build-data.ts
# 이후 Datasets.generated.swift 재생성 필요 — rebuild-datasets.ts (Scripts/) 참조
```

## 실행

### CLI (TS CLI와 동일 플래그)

```bash
.build/release/catchtype < input.txt
echo 'dkssudgktpdy' | .build/release/catchtype            # → 안녕하세요
echo 'npm testeh dmlwk' | .build/release/catchtype --start ko --debug
cat pw.txt | .build/release/catchtype --password-skip     # 비밀번호 토큰 있으면 exit 3
```

### 상태바 앱 (권한 필요)

```bash
.build/release/CatchType      # 직접 실행 — 첫 실행 시 손쉬운 사용 프롬프트
```

정식 설치(앱 번들 + LaunchAgent + CLI 심볼릭):

```bash
scripts/install.sh            # 자동: 빌드 + .app 패키징 + /Applications 복사 + launchctl
scripts/uninstall.sh          # 제거
```

## 패키지 구조

```
packages/macos/
├── Package.swift                    # swift-tools-version:5.9, macOS 13+
├── Sources/
│   ├── CatchTypeCore/               # 엔진 (TS engine v1.1 전수 이식)
│   │   ├── Hangul.swift             # 조합기
│   │   ├── Layout.swift             # 두벌식 매핑 + KVK_ANSI
│   │   ├── CTDictionary.swift       # 사전 (hasWord/hasPrefix/weightOf)
│   │   ├── Engine.swift             # 판정 규칙 v1.1.1 (mixed, 카멜케이스 보호 포함)
│   │   ├── Builtins.swift           # 내장 사전 로더 (프로세스 캐시)
│   │   └── Datasets.generated.swift # data/* 전수 소스 임베드 (재생성 스크립트: Scripts/)
│   ├── catchtype/main.swift         # CLI executable
│   └── CatchType/                   # 상태바 앱 (macOS 전용 — #if os(macOS))
│       ├── CatchTypeApp.swift       # NSApplication + CGEventTap 설치/콜백
│       ├── EventTapEngine.swift     # 런 수집 → 판정 → 재전송 상태 기계
│       ├── TargetApps.swift         # 앱별 토글 + config.json 저장
│       ├── PasswordGuard.swift      # 이중 방어: AX secure field + 프롬프트 휴리스틱
│       └── PermissionPrompt.swift   # 접근성 권한 요청 + 안내 얼럿
├── Tests/CatchTypeCoreTests/        # XCTest (Hangul/Layout/Engine/Golden)
├── Scripts/
│   ├── build.sh                     # 빌드 래퍼
│   ├── install.sh                   # 설치 (앱번들+LaunchAgent+CLI)
│   ├── uninstall.sh
│   └── rebuild-golden.ts            # 골든 벡터 재생성 (TS 엔진 → Swift)
└── docs/BUILD-TEST.md               # 이 파일
```

## macOS 셸 설계 노트 (docs/SPEC.md 보완)

### 이벤트 흐름

```
CGEventTap(.cgSessionTap, keyDown)
  → 타겟 앱 검사(config.app per-app toggle)
  → 이중 방어 (passwordGuard: AX secure field / promptGuard: hold window)
  → CTKey로 정규화 (KVK_ANSI + shift)
  → EventStreamCorrector.handleKey
      • 런 진행 중: 원본 통과 (아무 것도 안 함 — 타이핑 지연 없음)
      • 런 끝(Space/Enter/Tab or timeout or 매핑 없는 글쇠): 판정 1회
          - output == raw → 그대로 통과
          - output != raw → backspace N + 교정문 SEND (원본 소멸·변조)
```

**핵심 조정**: 단어 진행 중엔 절대 이벤트를 씹지 않는다 — prefix 근거로
"조용히 대기"가 아니라 아예 원본 통과. 교정은 단어가 끝난 뒤 한 번.
사용자가 인지하는 입력 지연이 0이고, 오판이 런 단위로 확정된다.

### SEND 방식

교정은 `CGEventSetIntegerIntegerField(.keyboardEventKeycode, …)`로
원본 keydown 이벤트를 첫 교정 글쇠로 '변조'하고, 나머지는
`CGEvent.post(tap: .cgHeadInsertEventTap)`로 추가 전송한다.
터미널 앱 호환성은 앱별 실험이 필요(SPEC.md open question 4) —
Warp/Ghostty는 pasteboard 삽입(⌘V 시뮬레이션)이 더 안전할 수 있다.

### 비밀번호 이중 방어

1. **AX secure field** (`AXSecureTextField` role or 'password/비밀번호' 태그)
   — 런 첫 글쇠에서만 조회(호출 비용) → 감지되면 그 앱 키 스트림 전체 우회
2. **프롬프트 휴리스틱** — 터미널 라인 `password:`/`PIN:` 패턴 → 8초 hold.
   hold는 `EventStreamCorrector.notePasswordPrompt(line:)` 로 갱신.
3. **엔진 자체 방어** — `looksLikePassword`(문자 클래스 3종) 토큰은 판정 스킵 + 플래그.

## 알려진 한계 / OPEN QUESTIONS

- **터미널 화면 라인 읽기**: 앱별 AX 구조가 달라 (a)까지는 공통, (b)의
  "화면에 프롬프트 뜸" 감시는 터미널별 실험 필요 — 현재는 키 스트림에서
  `password:` 라인이 타이핑되는 경우(드묾)만 감지. 실전 방어는 (a)+엔진 방어가 담당.
- **pasteboard 삽입**: SPEC.md에서 고려한 방식 — 미구현(SendEvent 우선).
- **input source 감시**: 세션 언어는 판정으로만 갱신. 시스템 한영 전환
  (⌘Space)을 직접 추적하면 더 정확 — 미구현.
