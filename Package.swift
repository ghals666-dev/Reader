// swift-tools-version: 5.9
import PackageDescription

// 순수 로직(ReaderCore)은 어디서나 빌드된다. Linux CI에서도 테스트할 수 있다.
var products: [Product] = [
    .library(name: "ReaderCore", targets: ["ReaderCore"]),
]
var targets: [Target] = [
    // 단 감지, 머리글 제거, 문단 병합, 출력 조립 (Foundation만 사용)
    .target(name: "ReaderCore"),
    .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
]

// PDFKit·Vision·SwiftUI를 쓰는 부분은 macOS에서만 빌드한다.
#if os(macOS)
products += [
    .library(name: "ReaderEngine", targets: ["ReaderEngine"]),
    .executable(name: "reader-cli", targets: ["reader-cli"]),
    .executable(name: "ReaderApp", targets: ["ReaderApp"]),
]
targets += [
    .target(name: "ReaderEngine", dependencies: ["ReaderCore"]),
    .executableTarget(name: "reader-cli", dependencies: ["ReaderEngine"]),
    .executableTarget(name: "ReaderApp", dependencies: ["ReaderEngine"]),
    .testTarget(name: "ReaderEngineTests", dependencies: ["ReaderEngine", "ReaderCore"]),
]
#endif

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
