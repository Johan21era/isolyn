// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Isolyn",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "IsolynEngine", targets: ["IsolynEngine"]),
        .executable(name: "IsolynApp", targets: ["IsolynApp"])
    ],
    targets: [
        .target(
            name: "IsolynEngine",
            path: "Sources/IsolynEngine",
            publicHeadersPath: "include",
            // EntropySource calls SecRandomCopyBytes (Security.framework)
            // directly on Apple platforms as of the rewrite to per-draw OS
            // CSPRNG calls -- explicit here rather than relying on it being
            // pulled in transitively, since this is a plain C++ target, not
            // a Swift one.
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.macOS, .iOS]))
            ]
        ),
        // The narrow Swift/C++ boundary -- see docs/BRIDGE_ARCHITECTURE.md.
        // A separate target from IsolynEngine on purpose: its
        // publicHeadersPath exposes ONLY include/IsolynBridge.hpp, a
        // small POD-only contract, NOT IsolynEngine's full header set
        // (GameState.hpp, MatchController.hpp, etc. stay internal to
        // this target's .cpp -- IsolynApp never sees them). No product
        // entry above: this is internal plumbing between IsolynEngine
        // and IsolynApp, not meant to be imported independently.
        .target(
            name: "IsolynEngineBridge",
            dependencies: ["IsolynEngine"],
            path: "Sources/IsolynEngineBridge",
            publicHeadersPath: "include"
        ),
        // The UI/UX layer. Now depends on IsolynEngineBridge (not
        // IsolynEngine directly -- see above) with .interoperabilityMode(
        // .Cxx) enabled, exactly as anticipated when this target was
        // first written self-contained. Swift code under this target
        // that calls into isolyn::bridge::* (Sources/IsolynApp/Engine/)
        // has NOT been verified by an actual Swift/Xcode compile in any
        // session that has produced this codebase, including this one --
        // no session has ever had a Swift toolchain available (see
        // HANDOFF.md). Hand-reviewed carefully against the real
        // IsolynBridge.hpp signatures instead; treat as unverified until
        // it has actually been built in Xcode.
        .executableTarget(
            name: "IsolynApp",
            dependencies: ["IsolynEngineBridge"],
            path: "Sources/IsolynApp",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        // Deterministic, compiler-verifiable tests for the Swift/UI
        // layer -- the environment/time-phase engine specifically.
        // @testable-imports IsolynApp, so internal types are reachable.
        // NOTE: this target has NOT been re-verified against the
        // .interoperabilityMode(.Cxx) change above in any session (no
        // Swift toolchain has ever been available) -- Cxx interop mode
        // is a per-target Swift compiler setting, so enabling it on
        // IsolynApp should not by itself change how this test target
        // (which does not depend on IsolynEngineBridge) builds, but that
        // reasoning has not been compiler-checked and should be the
        // first thing confirmed when this is next opened in Xcode.
        .testTarget(
            name: "IsolynAppTests",
            dependencies: ["IsolynApp"],
            path: "Tests/IsolynAppTests",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)

