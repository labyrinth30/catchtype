# Catchtype macOS 셸 — 빌드·테스트 가이드

Swift Package Package.swift 하나로 CLI(`catchtype`)와 상태바 앱 실행 파일(`CatchTypeApp`)을 모두
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
#   CatchTypeApp      ← 상태바 앱 실행 파일
```

> **Linux CI 참고**: `Sources/CatchTypeApp/*.swift`는 `#if os(macOS)`로 감싸져 있어
> Linux에서도 `swift build`가 실패하지 않는다. 앱 로직은 macOS에서만 컴파일·링크된다.

## 테스트

```bash
cd packages/macos
swift test                   # macOS 전체 (Linux에서는 CatchTypeCore 테스트만 해당)
python3 scripts/selfcheck-install.py  # 임시 경로 + 모의 시스템 명령으로 설치/실패 복원/제거 검증
```

테스트 스위트 (TS 엔진 82개 테스트에 대응하는 Swift 포트 + 골든 회귀):

| 파일 | 내용 |
|---|---|
| `HangulTests` | 조합기 규칙 + **전체 11,172 완성형 roundtrip** |
| `LayoutTests` | 두벌식 표·shift·KVK keycode |
| `EngineTests` | 사전 질의·비밀번호 휴리스틱·augment 계약 |
| `EventStreamTests` | 공백 교정·입력 중단·시간 초과·비밀번호 토큰·Shift 조합키 |
| `EventSenderTests` | 한글 Unicode·삭제 순서·이벤트 태그·잘못된 전송 차단 |
| `InstanceLockTests` | 중복 실행 차단·락 해제·심볼릭 링크 거부 |
| `GoldenTests` | **TS 엔진에서 뽑은 81개 실측 벡터와 비교** — 판정 리그레션 잠금 |

골든 벡터 재생성 (엔진 규칙 변경 후):

```bash
cd packages/macos/scripts && bun rebuild-golden.ts   # TS 엔진 실행 → Swift 배열 리터럴 출력
# 출력 → Tests/CatchTypeCoreTests/GoldenTests.swift의 goldens 배열에 붙여넣기
```

사전 데이터 재생성 (TS 빌드 파이프라인과 동일):

```bash
cd packages/engine && bun scripts/build-data.ts
# 이후 Datasets.generated.swift 재생성 필요 — rebuild-datasets.ts (scripts/) 참조
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
.build/release/CatchTypeApp      # 직접 실행 — 첫 실행 시 손쉬운 사용 프롬프트
```

정식 설치(서명한 앱 번들 + LaunchAgent + 영구 CLI 설치):

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
│   │   └── Datasets.generated.swift # data/* 전수 소스 임베드 (재생성 스크립트: scripts/)
│   ├── CatchTypeCLI/main.swift         # CLI executable
│   └── CatchTypeApp/                   # 상태바 앱 (macOS 전용 — #if os(macOS))
│       ├── CatchTypeApp.swift       # NSApplication + CGEventTap 설치/콜백
│       ├── EventTapEngine.swift     # 런 수집 → 판정 → 재전송 상태 기계
│       ├── TargetApps.swift         # 앱별 토글 + config.json 저장
│       ├── PasswordGuard.swift      # 이중 방어: AX secure field + 프롬프트 휴리스틱
│       └── PermissionPrompt.swift   # 접근성 권한 요청 + 안내 얼럿
├── Tests/CatchTypeCoreTests/        # XCTest (Hangul/Layout/Engine/Golden)
├── scripts/
│   ├── build.sh                     # 빌드 래퍼
│   ├── install.sh                   # 설치 (앱번들+LaunchAgent+CLI)
│   ├── uninstall.sh
│   └── rebuild-golden.ts            # 골든 벡터 재생성 (TS 엔진 → Swift)
└── docs/BUILD-TEST.md               # 이 파일
```

## macOS 앱 동작과 검증 범위

현재 앱은 영문 키보드 입력 소스(`com.apple.keylayout.*`)에서 입력한 연속 ASCII 단어를
공백·Enter·Tab에서 교정한다. 한국어 IME 조합은 삭제할 문자 수를 보장할 수 없어 원문을 통과시킨다.
숫자·기호가 섞인 토큰, 단축키, 커서 이동, 클릭, 앱·포커스·입력 소스 변경은 수집 중인 단어를 버린다.
1.2초 시간 초과도 수집 상태만 비우며 타이머가 backspace를 보내지 않는다.

교정은 원본 구분자 keydown을 `nil`로 제거하고, `CGEvent.tapPostEvent`로 삭제 → Unicode 교정문 →
구분자의 down/up 쌍을 현재 콜백 뒤쪽에 전달한다. 전송할 이벤트를 모두 만든 뒤에만 삭제를 시작한다.
자체 이벤트는 태그로 제외하며 제거한 구분자의 원본 keyup도 제거한다.
Shift+Space/Enter/Tab과 Command/Control/Option/Fn 조합키는 변형 없이 통과한다.

비밀번호 보호:

- 시스템 Secure Event Input 활성 상태에서는 설정과 관계없이 교정을 중단한다.
- AX role/subrole 및 설명·제목에서 비밀번호 필드를 확인한다. 조회 실패 시 보호를 켠 앱은 교정을 중단한다.
- 터미널의 포커스된 AX 컨트롤 값에서 마지막 줄을 읽어 password/passphrase/PIN/암호 프롬프트를 감지하고
  8초 동안 중단한다. 프롬프트가 남아 있으면 각 키 입력에서 보호 시간을 연장한다.
- 숫자·기호 토큰은 단어 끝까지 그대로 통과하고 엔진 passwordSuspect도 검사한다.
- 화면 값이나 입력 문자열은 로그에 기록하지 않는다.

인스턴스 락은 직접 실행과 LaunchAgent 실행을 포함해 사용자당 하나의 이벤트 교정기만 허용한다.

자동 테스트 통과는 실제 터미널 앱 호환성이나 비밀번호 무결성의 증거가 아니다.
실타이핑·sudo/ssh·로그인 자동 시작·재부팅은 FIRST-RUN-MACOS.md에 따라 별도 확인한다.
터미널별 AX 지원이 달라 안전하게 교정이 꺼질 수 있으며, IME의 역방향 교정과 유휴 타이머 교정은 지원하지 않는다.
