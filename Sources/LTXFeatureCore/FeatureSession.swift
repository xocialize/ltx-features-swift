// FeatureSession.swift — the protocol-oriented seam (operator requirement 2026-07-02): feature
// kits depend ONLY on these protocols, never on a concrete backend. `LTXEngineSession` provides
// the local-engine conformance; hosts outside this repo can conform with a remote service, an
// XPC helper, or a test stub — LTXFeatureCore itself is Foundation-only.

import Foundation

/// Runs a generation intent. The backend owns model lifecycle, memory, and (for the engine
/// conformance) tier policy — feature kits only express what they want.
public protocol FeatureGenerating: Sendable {
    func generate(_ intent: GenerationIntent) async throws -> GeneratedVideo
}

/// Provides adapter metadata + weight files. `acknowledgeLicense` must be called (per launch or
/// persisted, backend's choice) before a `licenseGated` adapter may be used.
public protocol AdapterResourceProviding: Sendable {
    var registry: AdapterRegistry { get }
    /// Local file for an adapter's weights, downloading/caching on first use.
    func adapterFileURL(id: String) async throws -> URL
    /// Record the user's explicit acknowledgment for a license-gated adapter.
    func acknowledgeLicense(id: String) async
    func isLicenseAcknowledged(id: String) async -> Bool
}

/// What a mini app takes: one object that can do both. Backed by `LTXEngineSession` locally.
public typealias FeatureSession = FeatureGenerating & AdapterResourceProviding

/// Shared validation: every declared-required slot (or at least one slot of each required
/// one-of group) must have an attachment. Backends call this before dispatch so all
/// conformances fail identically.
///
/// Group semantics (registry convention): a group NAMED in `conditioningGroups` is a REQUIRED
/// one-of — its members are individually optional (they're alternatives), but at least one must
/// be supplied. Finer combo rules (e.g. "location only" isn't a valid sheet source) harden with
/// the P4 intake.
public enum IntentValidation {
    public static func validate(_ intent: GenerationIntent, against entry: AdapterEntry) throws {
        let requiredGroups = Set(entry.conditioningGroups?.keys ?? [String: String]().keys)
        for (key, slots) in entry.slotGroups {
            let satisfied = slots.contains { intent.attachment(role: $0.role) != nil }
            let required = slots.contains { $0.isRequired } || requiredGroups.contains(key)
            if required && !satisfied {
                throw FeatureSessionError.missingRequiredAttachment(
                    adapter: entry.id, role: slots.count == 1 ? slots[0].role : key)
            }
        }
    }
}
