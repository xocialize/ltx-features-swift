// AdapterPanels.swift — the GENERIC registry-driven floor (BRIDGE-LTX-007): every adapter in the
// registry gets a working UI here with zero per-adapter code. Feature kits (LTXIngredients …)
// are curated experiences layered above this. Functional-first: chrome is deliberately plain
// until the Xcode agent's 300px panel style lands (007) — structure over styling.

import LTXFeatureCore
import SwiftUI
import UniformTypeIdentifiers

/// Standard 300px side-rail panel chrome — contributed by the Xcode agent (BRIDGE-LTX-007,
/// build-verified in LTXVideoTesting, light+dark): titled material card — header row (optional
/// SF Symbol + title + optional trailing accessory) over a hairline Divider, left-aligned
/// content, `.regularMaterial` in a 12pt rounded rect with a `.quaternary` hairline border.
/// The optional `accessory` closure hosts per-panel actions (reset / clear / help).
public struct FeaturePanelContainer<Content: View, Accessory: View>: View {
    private let title: String
    private let systemImage: String?
    @ViewBuilder private let accessory: () -> Accessory
    @ViewBuilder private let content: () -> Content

    public init(_ title: String, systemImage: String? = nil,
                @ViewBuilder accessory: @escaping () -> Accessory,
                @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(.secondary).imageScale(.medium)
                }
                Text(title).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                accessory()
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
    }
}

public extension FeaturePanelContainer where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

/// Adapter picker + strength + trigger + license gate.
public struct AdapterPanel: View {
    let registry: AdapterRegistry
    @Bindable var selection: AdapterSelection
    /// Show license-gated (eval-only) entries — the host decides (test app: yes).
    let includeGated: Bool

    public init(registry: AdapterRegistry, selection: AdapterSelection, includeGated: Bool = false) {
        self.registry = registry
        self.selection = selection
        self.includeGated = includeGated
    }

    public var body: some View {
        FeaturePanelContainer("Adapter") {
            Picker("Effect", selection: Binding(
                get: { selection.entry?.id ?? "" },
                set: { id in selection.select(registry.entry(id: id)) })) {
                Text("None (base model)").tag("")
                ForEach(registry.surfaced(includeGated: includeGated), id: \.id) { entry in
                    Text(entry.displayName).tag(entry.id)
                }
            }
            if let entry = selection.entry {
                HStack {
                    Text("Strength")
                    Slider(value: $selection.strength, in: 0 ... 2)
                    Text(String(format: "%.2f", selection.strength)).monospacedDigit()
                }
                if !entry.trigger.isEmpty {
                    Text("Trigger: \(entry.trigger)").font(.caption).foregroundStyle(.secondary)
                }
                if entry.isLicenseGated {
                    Toggle(isOn: $selection.licenseAcknowledged) {
                        Text("I acknowledge this adapter's license (\(entry.license ?? "restricted")) — evaluation use only")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

/// One control per declared conditioning slot; one-of groups render a mode picker first.
public struct ConditioningPanel: View {
    @Bindable var selection: AdapterSelection

    public init(selection: AdapterSelection) { self.selection = selection }

    public var body: some View {
        if let entry = selection.entry, !entry.slots.isEmpty {
            FeaturePanelContainer("Conditioning") {
                ForEach(entry.slotGroups, id: \.key) { group in
                    if group.slots.count > 1 {
                        oneOfGroup(group.key, group.slots)
                    } else {
                        SlotRow(slot: group.slots[0], selection: selection)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func oneOfGroup(_ key: String, _ slots: [ConditioningSlot]) -> some View {
        // Xcode-agent visual finding (BRIDGE-LTX-007): 3+ segments truncate at the 300px panel
        // width — segmented only for pairs, menu picker beyond that.
        let picker = Picker("Source", selection: Binding(
            get: { selection.chosenAlternative[key] ?? slots[0].role },
            set: { selection.chosenAlternative[key] = $0 })) {
            ForEach(slots, id: \.role) { Text(label(for: $0.role)).tag($0.role) }
        }
        if slots.count > 2 {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
        let chosen = selection.chosenAlternative[key] ?? slots[0].role
        if let slot = slots.first(where: { $0.role == chosen }) {
            SlotRow(slot: slot, selection: selection)
        }
    }

    private func label(for role: String) -> String {
        role.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }
}

/// A single slot's control, by media kind. File-URL payloads for video/audio; image data for
/// image/imageSet (imageSet shows per-image description fields — they feed prompt conventions).
struct SlotRow: View {
    let slot: ConditioningSlot
    @Bindable var selection: AdapterSelection
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                if slot.isRequired { Text("required").font(.caption2).foregroundStyle(.orange) }
                Spacer()
                Button(selection.attachments[slot.role] == nil ? "Choose…" : "Replace…") {
                    importing = true
                }
            }
            if let note = slot.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if case .imageSet(let images, _) = selection.attachments[slot.role]?.payload {
                Text("\(images.count) image(s) selected").font(.caption)
            } else if selection.attachments[slot.role] != nil {
                Text("Selected ✓").font(.caption).foregroundStyle(.green)
            }
            // Describable slots (registry `describable: true`): the text feeds the adapter's
            // promptConvention — e.g. the "Reference sheet:" half of the Ingredients prompt.
            if slot.isDescribable {
                TextField(slot.describeNote ?? "Describe this attachment…",
                          text: Binding(get: { selection.slotDescriptions[slot.role] ?? "" },
                                        set: { selection.slotDescriptions[slot.role] = $0 }),
                          axis: .vertical)
                    .lineLimit(2 ... 5)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: contentTypes,
                      allowsMultipleSelection: slot.media == .imageSet) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            selection.attachments[slot.role] = attachment(for: urls)
        }
    }

    private var title: String {
        slot.role.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }

    private var contentTypes: [UTType] {
        switch slot.media {
        case .video: return [.movie, .mpeg4Movie, .quickTimeMovie]
        case .audio: return [.audio]
        case .image, .imageSet: return [.image]
        }
    }

    private func attachment(for urls: [URL]) -> ConditioningAttachment? {
        switch slot.media {
        case .video: return ConditioningAttachment(role: slot.role, payload: .video(urls[0]),
                                                   strength: slot.defaultStrength)
        case .audio: return ConditioningAttachment(role: slot.role, payload: .audio(urls[0]))
        case .image:
            guard let data = try? Data(contentsOf: urls[0]) else { return nil }
            return ConditioningAttachment(role: slot.role, payload: .image(data))
        case .imageSet:
            let limited = urls.prefix(slot.maxCount ?? urls.count)
            let datas = limited.compactMap { try? Data(contentsOf: $0) }
            guard !datas.isEmpty else { return nil }
            return ConditioningAttachment(role: slot.role,
                                          payload: .imageSet(datas, descriptions: datas.map { _ in nil }))
        }
    }
}
