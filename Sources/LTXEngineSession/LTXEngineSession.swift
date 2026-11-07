// LTXEngineSession.swift — the local-engine conformance of the FeatureSession protocols.
// Wraps an APP-OWNED MLXServeEngine (never constructs one — the app keeps engine ownership per
// the MLXEngine integration convention) with the MLXLTX2 package registered on it. The ONLY
// ltx-features product that links the engine/MLX stack.
//
// Adapters ride the engine's typed contract (contract 1.53.0 + 1.55.0, AB-A-0197): the session
// registers MLXLTX2's catalog (ids `ltx:<registry id>`), turns an intent's adapter and attachments
// into an `AdapterRef` with role-bound `ConditioningInput`s, and the engine fetches the file at its
// pinned commit, checks its sha256, checks the slots and groups, and hands the package the result.
// Plain and IC adapters both run.

import Foundation
import LTXFeatureCore
import MLXLTX2
import MLXServeCore
import MLXToolKit

public actor LTXEngineSession {
    private let engine: MLXServeEngine
    private let packageId: PackageID
    public nonisolated let registry: AdapterRegistry
    private var acknowledged: Set<String> = []
    private var catalogRegistered = false

    /// - Parameters:
    ///   - engine: the app-owned engine, with the MLXLTX2 package ALREADY registered (the app
    ///     controls configuration/tier; the session only runs requests against it). Adapter files
    ///     land in the engine's models root.
    ///   - packageId: the registration handle for the LTX package.
    ///   - registry: adapter registry (defaults to the vendored copy).
    public init(engine: MLXServeEngine, packageId: PackageID,
                registry: AdapterRegistry? = nil) throws {
        self.engine = engine
        self.packageId = packageId
        self.registry = try registry ?? .bundled()
    }

    /// Pre-1.53 signature. The engine now owns adapter files (in its models root), so
    /// `cacheDirectory` is ignored.
    @available(*, deprecated, message: "adapter files live in the engine's models root; drop cacheDirectory")
    public init(engine: MLXServeEngine, packageId: PackageID,
                registry: AdapterRegistry? = nil, cacheDirectory: URL) throws {
        try self.init(engine: engine, packageId: packageId, registry: registry)
    }

    /// The engine catalog id for a registry id.
    nonisolated static func catalogID(_ id: String) -> String {
        id.contains(":") ? id : "\(LTXAdapters.namespace):\(id)"
    }

    /// Register MLXLTX2's catalog on the engine once (re-registering is idempotent there).
    private func ensureCatalog() async throws {
        guard !catalogRegistered else { return }
        try await engine.registerAdapters(LTXAdapters.catalog())
        catalogRegistered = true
    }
}

extension LTXEngineSession: AdapterResourceProviding {
    /// Fetch (first use) and verify the adapter through the engine; returns its file.
    public func adapterFileURL(id: String) async throws -> URL {
        guard registry.entry(id: id) != nil else { throw AdapterRegistryError.unknownAdapter(id) }
        try await ensureCatalog()
        let catalogID = Self.catalogID(id)
        guard let url = try await engine.prepareAdapters([catalogID])[catalogID] else {
            throw AdapterRegistryError.unknownAdapter(id)
        }
        return url
    }

    public func acknowledgeLicense(id: String) async { acknowledged.insert(id) }
    public func isLicenseAcknowledged(id: String) async -> Bool { acknowledged.contains(id) }
}

extension LTXEngineSession: FeatureGenerating {
    public func generate(_ intent: GenerationIntent) async throws -> GeneratedVideo {
        var adapters: [AdapterRef] = []
        if let adapterId = intent.adapterId {
            guard let entry = registry.entry(id: adapterId) else {
                throw AdapterRegistryError.unknownAdapter(adapterId)
            }
            if entry.isLicenseGated && !acknowledged.contains(adapterId) {
                throw FeatureSessionError.licenseNotAcknowledged(adapterId)
            }
            try IntentValidation.validate(intent, against: entry)
            try await ensureCatalog()
            // Every attachment except the base model's own init image binds to the adapter's slot
            // of the same role; the engine orders them and checks the groups.
            let conditioning = try intent.attachments
                .filter { $0.role != "init_image" }
                .flatMap(Self.conditioning)
            adapters = [AdapterRef(id: Self.catalogID(adapterId), strength: intent.adapterStrength,
                                   conditioning: conditioning)]
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
            adapters: adapters)
        let response = try await engine.run(request, package: packageId)
        guard let t2v = response as? T2VResponse else {
            throw FeatureSessionError.adapterNotYetSupported(
                intent.adapterId ?? "base", reason: "unexpected engine response type")
        }
        return GeneratedVideo(data: t2v.video.data,
                              width: intent.width, height: intent.height,
                              frames: intent.frames, fps: intent.fps)
    }

    /// One attachment as engine conditioning inputs (an image set is one input per image).
    static func conditioning(_ attachment: ConditioningAttachment) throws -> [ConditioningInput] {
        func input(_ media: ConditioningMedia) -> ConditioningInput {
            ConditioningInput(role: attachment.role, media: media, strength: attachment.strength)
        }
        func image(_ data: Data) -> MLXToolKit.Image {
            // The package decodes by content; the format only needs to be honest about JPEG.
            MLXToolKit.Image(format: data.starts(with: [0xFF, 0xD8]) ? .jpeg : .png, data: data)
        }
        switch attachment.payload {
        case .image(let data):
            return [input(.image(image(data)))]
        case .imageSet(let images, _):
            return images.map { input(.image(image($0))) }
        case .video(let url):
            let format: Video.Format = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
            return [input(.video(Video(format: format, data: try Data(contentsOf: url))))]
        case .audio(let url):
            return [input(.audio(Audio(format: .wav, data: try Data(contentsOf: url))))]
        }
    }
}
