// IngredientsFeature.swift — the first mini app: reference-sheet consistency on the Ingredients
// IC-LoRA. Curated experience above the generic panels: subject-image picking with per-image
// descriptions, live sheet preview (SheetComposer, P2b), dual-part prompt assembly per the
// adapter's `promptConvention`, and intent submission through any `FeatureSession`.
//
// STATUS: functional skeleton — generation throws `adapterNotYetSupported` until the MLXLTX2 IC
// conditioning intake lands (IC-LORA-PLAN P4); the sheet composer + prompt assembly + panels are
// live now so UX iteration (BRIDGE-LTX-007) doesn't wait on the pipeline.

import LTXAdapterPanels
import LTXFeatureCore
import SwiftUI

/// Assembles the Ingredients dual-part prompt in the EXACT format the reference usage feeds the
/// adapter (verified against the community Space `ltx-community/ltx-2.3-ingredients-distilled`,
/// `build_prompt`): `"Reference sheet: {elements}\n\nGenerated video: {action}"` — free-form
/// element descriptions joined with semicolons, NO panel numbering, blank-line separator.
/// (Also a PromptEnhanceKit template hook — IC-LORA-PLAN P7.)
public enum IngredientsPrompt {
    public static func assemble(panelDescriptions: [String?], locationDescription: String?,
                                actionBrief: String) -> String {
        var elements = panelDescriptions.compactMap { $0 }
        if let loc = locationDescription { elements.append(loc) }
        guard !elements.isEmpty else { return "Generated video: \(actionBrief)" }
        return PromptConvention.assemble(convention: PromptConvention.ingredientsDualPart,
                                         descriptions: elements, action: actionBrief)
    }
}

@Observable
public final class IngredientsModel {
    public var subjects: [(data: Data, description: String?)] = []
    public var location: (data: Data, description: String?)?
    public var actionBrief = ""
    public var sheetPreview: Data?
    public var status = ""

    public init() {}

    /// Compose (oversized) sheet from the current inputs — called on any input change.
    public func refreshSheet() {
        sheetPreview = try? SheetComposer.compose(
            subjectData: subjects.map(\.data), locationData: location?.data)
    }

    /// The role-tagged intent for any FeatureSession backend.
    public func intent(width: Int = 704, height: Int = 512, frames: Int = 121) -> GenerationIntent {
        var attachments: [ConditioningAttachment] = []
        if let sheet = sheetPreview {
            attachments.append(ConditioningAttachment(role: "reference_sheet", payload: .image(sheet)))
        }
        let prompt = IngredientsPrompt.assemble(
            panelDescriptions: subjects.map(\.description),
            locationDescription: location?.description,
            actionBrief: actionBrief)
        return GenerationIntent(prompt: prompt, adapterId: "ingredients",
                                attachments: attachments,
                                width: width, height: height, frames: frames)
    }
}

/// The mini app's root view — hosts embed this wherever the workflow calls for it.
public struct IngredientsFeature: View {
    @State private var model = IngredientsModel()
    let session: any FeatureSession

    public init(session: any FeatureSession) {
        self.session = session
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FeaturePanelContainer("Ingredients — Reference Sheet") {
                Text("Pick up to 6 subject/prop images and an optional location. Descriptions feed the prompt.")
                    .font(.caption).foregroundStyle(.secondary)
                // Slot pickers iterate with BRIDGE-LTX-007 chrome; preview below is live already.
                if let preview = model.sheetPreview, let ns = NSImage(data: preview) {
                    Image(nsImage: ns)
                        .resizable().aspectRatio(contentMode: .fit)
                        .border(.separator)
                }
                TextField("What happens in the video…", text: $model.actionBrief, axis: .vertical)
                    .lineLimit(2 ... 4)
                Button("Generate") {
                    Task {
                        do {
                            _ = try await session.generate(model.intent())
                            model.status = "Done"
                        } catch {
                            model.status = "\(error.localizedDescription)"
                        }
                    }
                }
                .disabled(model.sheetPreview == nil || model.actionBrief.isEmpty)
                if !model.status.isEmpty { Text(model.status).font(.caption) }
            }
        }
    }
}
