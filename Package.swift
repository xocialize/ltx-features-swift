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
        .package(path: "../ltx-2-mlx-swift"),
        .package(url: "https://github.com/xocialize/mlx-engine-swift", from: "0.9.1"),
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
