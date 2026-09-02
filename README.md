# ltx-features-swift

LTX feature "mini apps" as consumable SPM products. Apps import only what they use; features ship
one at a time as they become ready. Pipeline code stays in `ltx-2-mlx-swift` (parity-gated) —
feature kits express **intent** (adapter id + role-tagged attachments + prompt), never inference.

| Product | What | Links MLX? |
|---|---|---|
| `LTXFeatureCore` | protocols (`FeatureGenerating`, `AdapterResourceProviding`) + `GenerationIntent`/`ConditioningAttachment` + adapter registry (schema v2, vendored from [ltx-lora-registry](https://github.com/xocialize/ltx-lora-registry)) + shared `IntentValidation` | **No — Foundation-only.** The protocol seam: back it with the local engine, a remote service, or a test stub |
| `LTXEngineSession` | the default conformance: wraps an **app-owned** `MLXServeEngine` + registered `MLXLTX2` package + adapter weight cache | Yes (the only one) |
| `LTXAdapterPanels` | generic registry-driven SwiftUI panels — every adapter works here with zero per-adapter code (one-of groups, imageSet pickers, license-gate acknowledgment). Chrome iterates with the test app (BRIDGE-LTX-007) | No |
| `LTXIngredients` | first mini app: `SheetComposer` (subject panels + location band, black gutters, oversized 1456×825 → downscale at ingest), dual-part prompt assembly, workflow view | No |

Planned as ready: `LTXLipDub`, `LTXCameraTransfer` (license-gated).

## Rules of the architecture

1. **The app owns the engine.** `LTXEngineSession` receives it (and the `PackageID`) — kits never
   construct engines or load weights independently; one governor, one model store.
2. **Adapters are data.** New registry entries surface in `LTXAdapterPanels` with no code. A
   feature kit is only written when an adapter earns a curated experience.
3. **Backends are pluggable.** Everything a mini app needs is in `LTXFeatureCore`'s protocols —
   conformances outside this repo (remote render service, XPC, mocks) are first-class.

## Status (2026-07-02)

- Core + panels + Ingredients skeleton build; 8/8 tests (registry v2 decode, one-of validation,
  sheet-composer pixel-verified geometry, prompt convention).
- `LTXEngineSession.generate`: base t2v/i2v + plain adapters work now; IC adapters validate and
  resolve weights but throw `adapterNotYetSupported` until the MLXLTX2 conditioning intake lands
  (IC-LORA-PLAN P4) — the seam is shaped for it.

## Consuming this package (read before adding it to an Xcode project)

Add it by **branch** (`main`) or **revision**, not by version — and add `ltx-2-mlx-swift` the same
way (LTX Studio already takes the port as `branch: main`). Measured 2026-09-02 (AB-A-0052): a
`from:` requirement on this package, or on the port, is rejected by SwiftPM — *"required using a
stable-version but depends on an unstable-version package 'mlx-swift-lm'"* — because the port must
pin `mlx-swift-lm` by **revision** until upstream tags the Gemma-4 SPI (no tag ≥3.31.4 carries it;
a fork tag is barred by upstream's `unsafeFlags(["-w"])`, which SwiftPM forbids in version-pinned
packages). SwiftPM also requires every requirement on one package to AGREE, so this manifest takes
the port as `branch: "main"` to match the studio's existing requirement. Tags on this repo
(`v0.1.x`) still mark registry syncs and API states — pin the tag's **commit** as a revision if you
want reproducibility. Local development against the sibling checkout:
`swift package edit ltx-2-mlx-swift --path ../ltx-2-mlx-swift` (or Xcode's local-override).
Both revert to `from:` the day upstream `mlx-swift-lm` ships a tag with #530/#387.
