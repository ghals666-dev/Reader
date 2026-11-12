// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "ReaderEngine", targets: ["ReaderEngine"]),
        .executable(name: "reader-cli", targets: ["reader-cli"]),
        .executable(name: "ReaderApp", targets: ["ReaderApp"]),
    ],
    targets: [
        // 순수 로직: 단 감지, 머리글 제거, 문단 병합, 출력 조립 (Foundation만 사용)
        .target(name: "ReaderCore"),
        // PDFKit + Vision: PDF에서 줄 단위 텍스트와 좌표를 뽑는다
        .target(name: "ReaderEngine", dependencies: ["ReaderCore"]),
        .executableTarget(name: "reader-cli", dependencies: ["ReaderEngine"]),
        .executableTarget(name: "ReaderApp", dependencies: ["ReaderEngine"]),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
        .testTarget(name: "ReaderEngineTests", dependencies: ["ReaderEngine", "ReaderCore"]),
    ]
)
