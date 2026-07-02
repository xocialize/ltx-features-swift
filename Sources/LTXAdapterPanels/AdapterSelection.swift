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
    /// For one-of groups: the role the user chose to fill (drives which control is shown).
    public var chosenAlternative: [String: String] = [:]
    /// License-gated entries need this flipped by an explicit user action before use.
    public var licenseAcknowledged = false

    public init() {}

    public func select(_ entry: AdapterEntry?) {
        self.entry = entry
        strength = entry?.defaultStrength ?? 1.0
        attachments = [:]
        chosenAlternative = [:]
        licenseAcknowledged = false
    }

    /// The attachments in intent shape, honoring one-of choices.
    public var intentAttachments: [ConditioningAttachment] {
        guard let entry else { return [] }
        return entry.slotGroups.flatMap { key, slots -> [ConditioningAttachment] in
            if slots.count > 1, let chosen = chosenAlternative[key] {
                return attachments[chosen].map { [$0] } ?? []
            }
            return slots.compactMap { attachments[$0.role] }
        }
    }

    public var readyToGenerate: Bool {
        guard let entry else { return true }   // base model
        if entry.isLicenseGated && !licenseAcknowledged { return false }
        let intent = GenerationIntent(prompt: "", attachments: intentAttachments)
        return (try? IntentValidation.validate(intent, against: entry)) != nil
    }
}
