// swift-tools-version: 6.2
import PackageDescription

// ltx-features-swift — LTX feature "mini apps" as consumable SPM products (IC-LORA-PLAN §UI,
// operator direction 2026-07-02). Apps consume only the products they want:
//
//   LTXFeatureCore     protocols + types + adapter registry (schema v2) — FOUNDATION-ONLY.
//                      The protocol-oriented seam: hosts back `FeatureGenerating` /
//                      `AdapterResourceProviding` with the local engine (LTXEngineSession),
//                      a remote service, or a test stub — no MLX dependency here.
//   LTXEngineSession   the default conformance: wraps an APP-OWNED MLXServeEngine + the
//                      MLXLTX2 package + the adapter weight cache. The ONLY product that
//                      links the engine/MLX stack.
//   LTXAdapterPanels   registry-driven SwiftUI panels (generic floor: every adapter works
//                      here with zero per-adapter code). Chrome per BRIDGE-LTX-007.
//   LTXIngredients     first mini app: sheet-builder composer + ingredients workflow.
//                      (LTXLipDub / LTXCameraTransfer targets added as they become ready.)
//
// Pipeline code stays in ltx-2-mlx-swift (parity-gated); feature kits express INTENT
// (adapter id + role-tagged attachments + prompt) — never inference.
let package = Package(
    name: "ltx-features-swift",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LTXFeatureCore", targets: ["LTXFeatureCore"]),
        .library(name: "LTXEngineSession", targets: ["LTXEngineSession"]),
        .library(name: "LTXAdapterPanels", targets: ["LTXAdapterPanels"]),
        .library(name: "LTXIngredients", targets: ["LTXIngredients"]),
    ],
    dependencies: [
        // URL, NOT a path dep (AB-A-0052, 2026-09-02): a path dependency makes this package
        // UNCONSUMABLE remotely — SwiftPM has no `../ltx-2-mlx-swift` beside a fetched checkout and
        // the graph fails (the same class as AB-T-0073 on the port's own mlx-swift-lm dep).
        // 🚨 BRANCH, NOT `from: "0.14.0"` — measured 2026-09-02: a stable-version requirement on the
        // port is REJECTED ("required using a stable-version but depends on an unstable-version
        // package 'mlx-swift-lm'") because the port must pin mlx-swift-lm by REVISION until upstream
        // tags the Gemma-4 SPI (no tag ≥3.31.4 carries it; a fork tag is barred by upstream's
        // `unsafeFlags(["-w"])`, which SwiftPM forbids in version-pinned deps). An unstable requirement
        // is the only consumable form, and SwiftPM demands every requirement on one package AGREE —
        // LTX Studio already takes the port as `branch: "main"`, so this matches it. Consumers add
        // this package by branch/revision too (Xcode "Branch" rule); a `from:` on it fails the same
        // way. Revert both to `from:` the day upstream mlx-swift-lm ships a tag with #530/#387.
        // Local development against the sibling checkout: `swift package edit ltx-2-mlx-swift --path
        // ../ltx-2-mlx-swift` (or Xcode's local-override) — the URL form costs nothing in-tree.
        .package(url: "https://github.com/xocialize/ltx-2-mlx-swift", branch: "main"),
        // Floor raised to what ltx-2-mlx-swift 0.14.0 itself requires; the two unify at ≥0.47.0.
        .package(url: "https://github.com/xocialize/mlx-engine-swift", from: "0.47.0"),
    ],
    targets: [
        .target(
            name: "LTXFeatureCore",
            resources: [.process("Resources")]   // vendored registry.json (synced from ltx-lora-registry)
        ),
        .target(
            name: "LTXEngineSession",
            dependencies: [
                "LTXFeatureCore",
                .product(name: "MLXLTX2", package: "ltx-2-mlx-swift"),
                .product(name: "MLXServeCore", package: "mlx-engine-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
            ]
        ),
        .target(name: "LTXAdapterPanels", dependencies: ["LTXFeatureCore"]),
        .target(name: "LTXIngredients", dependencies: ["LTXFeatureCore", "LTXAdapterPanels"]),
        .testTarget(
            name: "LTXFeaturesTests",
            dependencies: ["LTXFeatureCore", "LTXIngredients"]
        ),
    ]
)
