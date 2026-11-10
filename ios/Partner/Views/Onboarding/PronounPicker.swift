import SwiftUI

enum Pronouns {
    /// Shown first — the options most apps (Hinge, Bumble, Instagram) lead with.
    static let common = ["she/her", "he/him", "they/them", "she/they", "he/they", "any pronouns"]
    /// Shown under "More options".
    static let more = ["ze/zir", "ze/hir", "xe/xem", "ey/em", "fae/faer", "it/its", "ask me"]
    static let preferNotToSay = "Prefer not to say"
    static let maxSelections = 4

    /// Pronouns are stored as one comma-separated string on `Person`.
    static func parse(_ stored: String) -> [String] {
        stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func join(_ list: [String]) -> String { list.joined(separator: ", ") }

    /// What to show on a profile — nothing if the person prefers not to say.
    static func display(_ stored: String) -> String? {
        let list = parse(stored).filter { $0 != preferNotToSay }
        return list.isEmpty ? nil : join(list)
    }
}

/// Chip-style pronoun picker: pick up to 4, add your own, or prefer not to say.
struct PronounPicker: View {
    @Binding var pronouns: String
    @State private var showMore = false
    @State private var custom = ""
    @FocusState private var customFocused: Bool

    private var selected: [String] { Pronouns.parse(pronouns) }
    private var customOptions: [String] {
        selected.filter { !Pronouns.common.contains($0) && !Pronouns.more.contains($0) && $0 != Pronouns.preferNotToSay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowLayout(spacing: 8) {
                ForEach(Pronouns.common + customOptions, id: \.self) { chip($0) }
            }

            if showMore {
                FlowLayout(spacing: 8) {
                    ForEach(Pronouns.more, id: \.self) { chip($0) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                HStack(spacing: 8) {
                    TextField("Add your own", text: $custom)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($customFocused)
                        .submitLabel(.done)
                        .onSubmit(addCustom)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    Button("Add", action: addCustom)
                        .buttonStyle(.bordered)
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            HStack {
                Button {
                    withAnimation(.snappy) { showMore.toggle() }
                } label: {
                    Label(showMore ? "Fewer options" : "More options", systemImage: showMore ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                chip(Pronouns.preferNotToSay)
            }

            Text("Optional · Pick up to \(Pronouns.maxSelections). They'll show on your profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sensoryFeedback(.selection, trigger: pronouns)
    }

    private func chip(_ option: String) -> some View {
        let isOn = selected.contains(option)
        return Button {
            toggle(option)
        } label: {
            HStack(spacing: 4) {
                if isOn { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(option)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(isOn ? .white : .primary)
            .background(isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ option: String) {
        var list = selected
        if let i = list.firstIndex(of: option) {
            list.remove(at: i)
        } else if option == Pronouns.preferNotToSay {
            list = [option]                                   // exclusive choice
        } else {
            list.removeAll { $0 == Pronouns.preferNotToSay }
            guard list.count < Pronouns.maxSelections else { return }
            list.append(option)
        }
        pronouns = Pronouns.join(list)
    }

    private func addCustom() {
        let value = custom.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty else { return }
        if !selected.contains(value) { toggle(value) }
        custom = ""
        customFocused = false
    }
}
