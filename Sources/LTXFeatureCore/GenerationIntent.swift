// GenerationIntent.swift — what a feature kit ASKS for. Foundation-only by design: the intent is
// the wire format between mini apps and whatever backs `FeatureGenerating` (local engine, remote
// service, test stub), so it carries media as Data/URL, never framework types.

import Foundation

/// A role-tagged conditioning attachment. Roles come from the adapter's declared
/// `ConditioningSlot`s; the backend routes them into the IC injection path (or the base model's
/// own conditioning, e.g. `init_image`).
public struct ConditioningAttachment: Sendable, Equatable {
    public enum Payload: Sendable, Equatable {
        /// Encoded image bytes (PNG/JPEG/HEIC) — decoded backend-side.
        case image(Data)
        /// A set of images with optional per-image descriptions (e.g. ingredients subject
        /// panels; descriptions feed the adapter's prompt convention).
        case imageSet([Data], descriptions: [String?])
        /// A media file by URL (video/audio) — backends stream/decode as needed.
        case video(URL)
        case audio(URL)
    }
    public let role: String
    public let payload: Payload
    /// Conditioning strength override; nil = the slot's/adapter's default.
    public let strength: Double?
    /// User-supplied description of this attachment (slots with `describable: true`) — consumed
    /// by the adapter's `promptConvention` when assembling the final prompt.
    public let description: String?

    public init(role: String, payload: Payload, strength: Double? = nil, description: String? = nil) {
        self.role = role
        self.payload = payload
        self.strength = strength
        self.description = description
    }
}

/// A complete generation ask from a feature kit.
public struct GenerationIntent: Sendable, Equatable {
    public var prompt: String
    public var negativePrompt: String?
    /// Selected adapter (registry id); nil = base model.
    public var adapterId: String?
    /// LoRA weight strength override; nil = the adapter's `defaultStrength`.
    public var adapterStrength: Double?
    public var attachments: [ConditioningAttachment]
    public var width: Int
    public var height: Int
    public var frames: Int
    public var fps: Double
    public var seed: UInt64?

    public init(prompt: String, negativePrompt: String? = nil,
                adapterId: String? = nil, adapterStrength: Double? = nil,
                attachments: [ConditioningAttachment] = [],
                width: Int = 704, height: Int = 512, frames: Int = 121, fps: Double = 24,
                seed: UInt64? = nil) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.adapterId = adapterId
        self.adapterStrength = adapterStrength
        self.attachments = attachments
        self.width = width
        self.height = height
        self.frames = frames
        self.fps = fps
        self.seed = seed
    }

    public func attachment(role: String) -> ConditioningAttachment? {
        attachments.first { $0.role == role }
    }
}

/// The result handed back to the feature kit.
public struct GeneratedVideo: Sendable, Equatable {
    /// Container bytes (MP4; H.264 + AAC when the adapter/base produces audio).
    public let data: Data
    public let width: Int
    public let height: Int
    public let frames: Int
    public let fps: Double

    public init(data: Data, width: Int, height: Int, frames: Int, fps: Double) {
        self.data = data
        self.width = width
        self.height = height
        self.frames = frames
        self.fps = fps
    }
}

public enum FeatureSessionError: Error, LocalizedError {
    /// The backend can't serve this adapter yet (e.g. IC conditioning before IC-LORA-PLAN P4).
    case adapterNotYetSupported(String, reason: String)
    case missingRequiredAttachment(adapter: String, role: String)
    case licenseNotAcknowledged(String)

    public var errorDescription: String? {
        switch self {
        case .adapterNotYetSupported(let id, let reason):
            return "Adapter '\(id)' isn't supported by this session yet: \(reason)"
        case .missingRequiredAttachment(let adapter, let role):
            return "Adapter '\(adapter)' requires a '\(role)' attachment."
        case .licenseNotAcknowledged(let id):
            return "Adapter '\(id)' is license-gated and requires explicit acknowledgment."
        }
    }
}
