// AdapterRegistry.swift — full schema-v2 decode of ltx-lora-registry (the feature layer owns the
// complete schema; MLXLTX2's LoRARegistry keeps only its minimal runtime subset — both read the
// same JSON, unknown keys ignore cleanly). Source of truth: github.com/xocialize/ltx-lora-registry.

import Foundation

/// A declared attachment slot — the generic conditioning surface. The UI renders one control per
/// slot (by `media`); the pipeline routes on `role`. Slots sharing a `group` are alternatives
/// (one-of), e.g. ingredients: a finished sheet OR subject images the app composes.
public struct ConditioningSlot: Codable, Sendable, Equatable {
    public enum Media: String, Codable, Sendable {
        case video, audio, image, imageSet
    }
    public let role: String
    public let media: Media
    public let required: Bool?
    public let maxCount: Int?
    public let group: String?
    public let ingest: String?
    public let defaultStrength: Double?
    public let note: String?
    /// The slot wants a user-supplied text description (feeds the adapter's `promptConvention`,
    /// e.g. the "Reference sheet:" half of the Ingredients dual-part prompt).
    public let describable: Bool?
    public let describeNote: String?

    public var isRequired: Bool { required ?? false }
    public var isDescribable: Bool { describable ?? false }
}

/// One adapter (schema v2). v1 fields unchanged; `conditioning` is present iff `kind == .ic`.
public struct AdapterEntry: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case plain, ic }

    // v1
    public let id: String
    public let displayName: String
    public let repo: String
    public let weightFile: String
    public let defaultStrength: Double
    public let trigger: String
    public let input: String?
    // v2
    public let kind: Kind?
    public let status: String?
    public let license: String?
    public let licenseGated: Bool?
    public let gatedDownload: Bool?
    public let referenceDownscale: Int?
    public let stage2: String?
    public let surface: String?
    public let promptConvention: String?
    public let conditioning: [ConditioningSlot]?
    public let conditioningGroups: [String: String]?

    public var effectiveKind: Kind { kind ?? .plain }
    public var isLicenseGated: Bool { licenseGated ?? false }
    public var slots: [ConditioningSlot] { conditioning ?? [] }

    /// Slot groups in declaration order: grouped alternatives keyed by group name; ungrouped
    /// slots each form their own singleton group (key = role).
    public var slotGroups: [(key: String, slots: [ConditioningSlot])] {
        var order: [String] = []
        var byKey: [String: [ConditioningSlot]] = [:]
        for slot in slots {
            let key = slot.group ?? slot.role
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(slot)
        }
        return order.map { ($0, byKey[$0]!) }
    }

    /// HF resolve URL for the weight file (mirrors MLXLTX2.LoRACache convention).
    public var weightURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(weightFile)")!
    }
}

/// The decoded registry + lookups.
public struct AdapterRegistry: Codable, Sendable {
    public let schemaVersion: Int
    public let base: String
    public let adapters: [AdapterEntry]

    public func entry(id: String) -> AdapterEntry? { adapters.first { $0.id == id } }

    /// Adapters an app should surface by default: license-gated entries excluded unless
    /// `includeGated` (they require an explicit acknowledgment affordance).
    public func surfaced(includeGated: Bool = false) -> [AdapterEntry] {
        adapters.filter { includeGated || !$0.isLicenseGated }
    }

    /// The registry copy vendored into this package (synced from xocialize/ltx-lora-registry).
    public static func bundled() throws -> AdapterRegistry {
        guard let url = Bundle.module.url(forResource: "registry", withExtension: "json") else {
            throw AdapterRegistryError.bundledManifestMissing
        }
        return try JSONDecoder().decode(AdapterRegistry.self, from: Data(contentsOf: url))
    }

    /// Load from a local file or remote-fetched copy (the "registry updates without a package
    /// release" path — pin revisions at the call site).
    public static func load(from url: URL) throws -> AdapterRegistry {
        try JSONDecoder().decode(AdapterRegistry.self, from: Data(contentsOf: url))
    }
}

public enum AdapterRegistryError: Error, LocalizedError {
    case bundledManifestMissing
    case unknownAdapter(String)

    public var errorDescription: String? {
        switch self {
        case .bundledManifestMissing: return "Bundled adapter registry manifest not found."
        case .unknownAdapter(let id): return "No adapter with id '\(id)' in the registry."
        }
    }
}
