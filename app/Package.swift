// swift-tools-version: 6.2
import Foundation
import PackageDescription
let testsPath = "Tests/AmbaplayAppTests"
let payloadPath = "Sources/AmbaplayApp/Resources/payload"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let hasTests = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(testsPath).path)

// make app-payload stages the payload, so a checkout that has not been built does
// not have it. A declared resource that is missing is a build error, while an app
// missing the payload is a condition InstallPayload already reports.
let hasPayload = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(payloadPath).path)
let package = Package(
    name: "AmbaplayApp",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "AmbaplayApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "AmbaplayUI"],
            path: "Sources/AmbaplayApp",
            resources: (hasPayload ? [.copy("Resources/payload")] : []) + [
                .process("Resources/Localization"),
                .copy("Resources/payload.manifest"),
                .copy("Resources/valve-packages.manifest"),
                .copy("Resources/detour2.bin"),
                .copy("Resources/detour2-fex.bin"),
                .copy("Resources/detour32.bin"),
                .copy("Resources/detour32-fex.bin"),
                .copy("Resources/detour64-fex.bin"),
                .copy("Resources/detour2-cx26.bin"),
                .copy("Resources/detour32-cx26.bin"),
                .copy("Resources/detour2-41069.bin"),
                .copy("Resources/detour32-41069.bin"),
                .copy("Resources/detour2-fex-41069.bin"),
                .copy("Resources/detour32-fex-41069.bin"),
                .copy("Resources/detour64-fex-41069.bin"),
                .copy("Resources/detour2-winehq-11.15.bin"),
                .copy("Resources/detour32-winehq-11.15.bin"),
                .copy("Resources/winemac-winehq-11.15.so"),
                .copy("Resources/detour2-winecx-11.15.bin"),
                .copy("Resources/detour32-winecx-11.15.bin"),
                .copy("Resources/winemac-winecx-11.15.so"),
                .copy("Resources/winebus-winecx-11.15.so"),
                .copy("Resources/detour2-winecx-11.17.bin"),
                .copy("Resources/detour32-winecx-11.17.bin"),
                .copy("Resources/winemac-winecx-11.17.so"),
                .copy("Resources/winebus-winecx-11.17.so"),
                .copy("Resources/winebus-winecx-11.17.sys"),
                .copy("Resources/ws2_32-winecx-11.17.dll"),
                .copy("Resources/kernel32-winecx-11.17.dll"),
                .copy("Resources/kernelbase-winecx-11.17.dll"),
                .copy("Resources/crypt32-winecx-11.17.dll"),
                .copy("Resources/wintrust-winecx-11.17.dll"),
                .copy("Resources/nvapi64-shim.dll"),
                .copy("Resources/win32u-winecx-11.17.so"),
                .copy("Resources/wined3d-winecx-11.17.dll"),
                .copy("Resources/winecoreaudio-winecx-11.17.so"),
                .copy("Resources/d3dx11_43-winecx-11.17.dll"),
                .copy("Resources/d3dx11_43-winecx-11.17-i386.dll"),
                .copy("Resources/d3dx11_42-winecx-11.17.dll"),
                .copy("Resources/d3dx11_42-winecx-11.17-i386.dll"),
                .copy("Resources/libSDL2-2.0.0.dylib"),
                .copy("Resources/detour2-41073.bin"),
                .copy("Resources/detour32-41073.bin"),
                .copy("Resources/detour2-fex-41073.bin"),
                .copy("Resources/detour32-fex-41073.bin"),
                .copy("Resources/detour64-fex-41073.bin"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ] + (hasTests ? [
        .testTarget(
            name: "AmbaplayAppTests",
            dependencies: ["AmbaplayApp"],
            path: testsPath
        ),
    ] : []) + [
        .target(
            name: "AmbaplayUI",
            path: "Sources/AmbaplayUI",
            resources: [.copy("Resources/Fonts")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AmbaplayInstallerCore",
            path: "Sources/AmbaplayInstallerCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AmbaplayInstaller",
            dependencies: ["AmbaplayUI", "AmbaplayInstallerCore"],
            path: "Sources/AmbaplayInstaller",
            resources: [.process("Resources/Localization")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AmbaplayInstallerCoreTests",
            dependencies: ["AmbaplayInstallerCore"],
            path: "Tests/AmbaplayInstallerCoreTests"
        ),
    ]
)
