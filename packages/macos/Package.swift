// swift-tools-version:5.9
//
// CatchtypeMac — CGEventTap 기반 백그라운드 상태바 앱.
// 무의존성(SPM target은 CatchTypeCore 하나): macOS 프레임워크만 사용.
// 빌드: swift build -c release  (macOS 13 이상, Real app은 scripts/install.sh 참조)

import PackageDescription

let package = Package(
    name: "catchtype-macos",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CatchTypeCore", targets: ["CatchTypeCore"]),
        .executable(name: "catchtype", targets: ["catchtype"]),
        .executable(name: "CatchType", targets: ["CatchType"]),
    ],
    targets: [
        // 순수 Swift 엔진 — 프로세스 내에서 데이터 온보딩(Golden 데이터셋 포함) 후 판정.
        .target(
            name: "CatchTypeCore",
            dependencies: []
        ),
        // 표준입력 텍스트 교정 CLI (의존성: 소스 빌드 데이터 사전 + CatchTypeCore).
        .executableTarget(
            name: "catchtype",
            dependencies: ["CatchTypeCore"]
        ),
        // CGEventTap 기반 상태바 앱 (의존성: CatchTypeCore + Apple 프레임워크).
        .executableTarget(
            name: "CatchType",
            dependencies: ["CatchTypeCore"]
        ),
        // XCTest 타깃: pubic 표면 API를 비교.
        .testTarget(
            name: "CatchTypeCoreTests",
            dependencies: ["CatchTypeCore"]
        ),
    ]
)
