// AdapterSelection.swift — the observable state the panels edit and the host reads. Emits plain
// LTXFeatureCore values; the host (or a feature kit) turns it into a GenerationIntent.

import Foundation
import LTXFeatureCore
import Observation

@Observable
public final class AdapterSelection {
    public var entry: AdapterEntry?
    public var strength: Double = 1.0
    /// role → picked payload (file URLs / image data), keyed by ConditioningSlot.role.
    public var attachments: [String: ConditioningAttachment] = [:]
    /// role → user-typed description (slots with `describable: true`) — feeds `promptConvention`.
    public var slotDescriptions: [String: String] = [:]
    /// For one-of groups: the role the user chose to fill (drives which control is shown).
    public var chosenAlternative: [String: String] = [:]
    /// License-gated entries need this flipped by an explicit user action before use.
    public var licenseAcknowledged = false

    public init() {}

    public func select(_ entry: AdapterEntry?) {
        self.entry = entry
        strength = entry?.defaultStrength ?? 1.0
        attachments = [:]
        slotDescriptions = [:]
        chosenAlternative = [:]
        licenseAcknowledged = false
    }

    /// The attachments in intent shape, honoring one-of choices, with typed descriptions merged.
    public var intentAttachments: [ConditioningAttachment] {
        guard let entry else { return [] }
        return entry.slotGroups.flatMap { key, slots -> [ConditioningAttachment] in
            let picked: [ConditioningAttachment]
            if slots.count > 1, let chosen = chosenAlternative[key] {
                picked = attachments[chosen].map { [$0] } ?? []
            } else {
                picked = slots.compactMap { attachments[$0.role] }
            }
            return picked.map { att in
                guard let text = slotDescriptions[att.role],
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return att }
                return ConditioningAttachment(role: att.role, payload: att.payload,
                                              strength: att.strength, description: text)
            }
        }
    }

    /// The FINAL prompt for the request: the adapter's `promptConvention` applied over the active
    /// slots' descriptions (slot order) with `action` = the app's main prompt box. No adapter /
    /// no convention / no descriptions ⇒ `action` unchanged — the host can call this
    /// unconditionally instead of special-casing per adapter.
    public func assembledPrompt(action: String) -> String {
        guard let entry else { return action }
        let descriptions = intentAttachments.compactMap(\.description)
        return PromptConvention.assemble(convention: entry.promptConvention,
                                         descriptions: descriptions, action: action)
    }

    public var readyToGenerate: Bool {
        guard let entry else { return true }   // base model
        if entry.isLicenseGated && !licenseAcknowledged { return false }
        let intent = GenerationIntent(prompt: "", attachments: intentAttachments)
        return (try? IntentValidation.validate(intent, against: entry)) != nil
    }
}
