// LTXEngineSession.swift — the local-engine conformance of the FeatureSession protocols.
// Wraps an APP-OWNED MLXServeEngine (never constructs one — the app keeps engine ownership per
// the MLXEngine integration convention) + the registered MLXLTX2 package + the adapter weight
// cache. The ONLY ltx-features product that links the engine/MLX stack.
//
// Capability today: base t2v/i2v + plain adapters (runtime LoRA via loraId/loraStrength
// metaData). IC adapters validate + resolve weights but throw `adapterNotYetSupported` until the
// MLXLTX2 conditioning intake lands (IC-LORA-PLAN P4) — the seam is already shaped for it.

import Foundation
import LTXFeatureCore
import MLXLTX2
import MLXServeCore
import MLXToolKit

public actor LTXEngineSession {
    private let engine: MLXServeEngine
    private let packageId: PackageID
    public nonisolated let registry: AdapterRegistry
    private let cache: LoRACache
    private var acknowledged: Set<String> = []

    /// - Parameters:
    ///   - engine: the app-owned engine, with the MLXLTX2 package ALREADY registered (the app
    ///     controls configuration/tier; the session only runs requests against it).
    ///   - packageId: the registration handle for the LTX package.
    ///   - registry: adapter registry (defaults to the vendored copy).
    ///   - cacheDirectory: adapter weight cache location (shared with the app's LoRA cache).
    public init(engine: MLXServeEngine, packageId: PackageID,
                registry: AdapterRegistry? = nil,
                cacheDirectory: URL) throws {
        self.engine = engine
        self.packageId = packageId
        self.registry = try registry ?? .bundled()
        self.cache = LoRACache(directory: cacheDirectory)
    }
}

extension LTXEngineSession: AdapterResourceProviding {
    public func adapterFileURL(id: String) async throws -> URL {
        guard let entry = registry.entry(id: id) else {
            throw AdapterRegistryError.unknownAdapter(id)
        }
        // Reuse the package's cache (id-named, atomic) via its v1 entry shape.
        let v1 = LoRAEntry(id: entry.id, displayName: entry.displayName, repo: entry.repo,
                           weightFile: entry.weightFile,
                           defaultStrength: Float(entry.defaultStrength),
                           trigger: entry.trigger, input: nil)
        return try await cache.ensure(v1)
    }

    public func acknowledgeLicense(id: String) async { acknowledged.insert(id) }
    public func isLicenseAcknowledged(id: String) async -> Bool { acknowledged.contains(id) }
}

extension LTXEngineSession: FeatureGenerating {
    public func generate(_ intent: GenerationIntent) async throws -> GeneratedVideo {
        var meta: MetaData = [:]
        if let adapterId = intent.adapterId {
            guard let entry = registry.entry(id: adapterId) else {
                throw AdapterRegistryError.unknownAdapter(adapterId)
            }
            if entry.isLicenseGated && !acknowledged.contains(adapterId) {
                throw FeatureSessionError.licenseNotAcknowledged(adapterId)
            }
            try IntentValidation.validate(intent, against: entry)
            if entry.effectiveKind == .ic {
                // Weights are ready (P0-verified, cache resolvable); the package-side
                // conditioning intake is IC-LORA-PLAN P4. Fail loud, not wrong.
                throw FeatureSessionError.adapterNotYetSupported(
                    adapterId, reason: "IC conditioning intake lands with IC-LORA-PLAN P4")
            }
            meta[LoRAMetaKeys.id] = .string(adapterId)
            meta[LoRAMetaKeys.strength] = .double(intent.adapterStrength ?? entry.defaultStrength)
        }

        // Base-model conditioning: an `init_image` attachment rides T2VRequest.initImage.
        var initImage: MLXToolKit.Image?
        if let att = intent.attachment(role: "init_image"), case .image(let data) = att.payload {
            initImage = MLXToolKit.Image(format: .png, data: data)
        }

        let request = T2VRequest(
            prompt: intent.prompt,
            negativePrompt: intent.negativePrompt,
            initImage: initImage,
            numFrames: intent.frames,
            fps: intent.fps,
            width: intent.width,
            height: intent.height,
            seed: intent.seed,
            metaData: meta)
        let response = try await engine.run(request, package: packageId)
        guard let t2v = response as? T2VResponse else {
            throw FeatureSessionError.adapterNotYetSupported(
                intent.adapterId ?? "base", reason: "unexpected engine response type")
        }
        return GeneratedVideo(data: t2v.video.data,
                              width: intent.width, height: intent.height,
                              frames: intent.frames, fps: intent.fps)
    }
}
