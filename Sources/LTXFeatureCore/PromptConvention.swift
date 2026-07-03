// PromptConvention.swift — registry-declared prompt assembly. An adapter's `promptConvention`
// names how slot descriptions + the user's action brief combine into the final prompt, so the
// GENERIC panels can serve convention-bearing adapters without per-adapter code (the same
// adapters-as-data rule as conditioning slots).

import Foundation

public enum PromptConvention {
    /// Ingredients dual-part — the EXACT format the reference usage feeds the adapter (verified
    /// against the `ltx-community/ltx-2.3-ingredients-distilled` Space): semicolon-joined
    /// free-form element descriptions, no panel labels, blank-line separator.
    public static let ingredientsDualPart = "ingredients-dual-part"

    /// Assemble the final prompt for `convention` from slot `descriptions` (in slot order,
    /// empties dropped) and the user's `action` brief. Unknown/nil convention, or no
    /// descriptions ⇒ the action passes through unchanged (enhancement-style never-block rule).
    public static func assemble(convention: String?, descriptions: [String], action: String) -> String {
        let elements = descriptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        switch convention {
        case ingredientsDualPart where !elements.isEmpty:
            return "Reference sheet: \(elements.joined(separator: "; "))\n\nGenerated video: \(action)"
        default:
            return action
        }
    }
}
