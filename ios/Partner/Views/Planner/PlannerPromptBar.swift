import SwiftUI

/// The entry point to the AI planner on Discover. Styled like a search field,
/// because that's where people expect to type what they want (as in Maps or
/// Photos search); the examples underneath show what kind of thing to say.
struct PlannerPromptBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let examples = [
        "free tomorrow after 5, something active",
        "this weekend, want to try hiking",
        "tonight, something chill and cheap",
        "Thursday afternoon, I don't know anyone",
    ]

    var body: some View {
        Button { store.showPlanner = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.gradient)
                    .symbolEffect(.pulse, options: .repeat(2), isActive: !reduceMotion)

                VStack(alignment: .leading, spacing: 1) {
                    Text("When are you free?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    TimelineView(.periodic(from: .now, by: 3.5)) { context in
                        let index = Int(context.date.timeIntervalSinceReferenceDate / 3.5) % Self.examples.count
                        Text("“\(Self.examples[index])”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: index)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Brand.accent)
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Plan with AI. When are you free?")
        .accessibilityHint("Describe your free time and what you feel like doing, and get plans that fit.")
    }
}

/// A smaller entry point for empty states: "nothing here, let us find something".
struct PlannerShortcutButton: View {
    @Environment(AppStore.self) private var store
    var title = "Find something for my free time"

    var body: some View {
        Button { store.showPlanner = true } label: {
            Label(title, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .foregroundStyle(Brand.accent)
                .background(Brand.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
