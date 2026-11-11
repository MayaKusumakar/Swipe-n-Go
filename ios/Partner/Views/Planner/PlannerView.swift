import SwiftUI

/// "I'm free…": say when you're free (tap or type) and get plans that fit, each with a reason.
struct PlannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initialQuery: String?

    @State private var model = PlannerModel()
    @State private var detail: Activity?
    @FocusState private var inputFocused: Bool

    private let quickPicks: [(title: String, symbol: String)] = [
        ("Tonight", "moon.stars.fill"),
        ("Tomorrow morning", "sunrise.fill"),
        ("Tomorrow after 5", "sunset.fill"),
        ("This weekend", "sun.max.fill"),
    ]

    private let examples = [
        "Free Thursday after 5, want something active but I don't know anyone",
        "Tomorrow morning, something chill and cheap",
        "This weekend, I want to try hiking for the first time",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    inputField
                    quickPickRow
                    content
                }
                .padding(20)
                .animation(.spring(duration: 0.45, bounce: 0.15), value: model.phase)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("I'm free…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if case .finished = model.phase {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New plan", systemImage: "arrow.counterclockwise") {
                            model.reset()
                            inputFocused = true
                        }
                    }
                }
            }
            .navigationDestination(item: $detail) { ActivityDetailView(activity: $0) }
            .sensoryFeedback(.success, trigger: model.phase) { _, new in
                if case .finished = new { true } else { false }
            }
            .onDisappear { model.cancel() }
            .task {
                if let initialQuery, !initialQuery.isEmpty { model.submit(initialQuery, store: store) }
            }
        }
    }

    // MARK: Header and input

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When are you free?")
                .font(.largeTitle.weight(.bold))
            Text("Tell us your free time and what you feel like. We'll find plans that fit and tell you why.")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var inputField: some View {
        @Bindable var model = model
        return HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .top) {
                TextField("e.g. free Thursday after 5, something active", text: $model.text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .onChange(of: model.text) { _, new in
                        // Return submits instead of adding a line.
                        if new.contains("\n") {
                            model.text = new.replacingOccurrences(of: "\n", with: "")
                            submit()
                        }
                    }
                if !model.text.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { model.text = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(model.canSubmit ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.gray.opacity(0.4)),
                                in: Circle())
            }
            .disabled(!model.canSubmit)
            .accessibilityLabel("Find plans")
        }
    }

    private var quickPickRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(quickPicks, id: \.title) { pick in
                    Button {
                        inputFocused = false
                        model.submit(pick.title, store: store)
                    } label: {
                        Label(pick.title, systemImage: pick.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
        .scrollIndicators(.hidden)
        .disabled(model.isPlanning)
    }

    // MARK: Content by phase

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            suggestions.transition(.opacity)
        case .planning(let step):
            PlanningProgress(step: step)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .finished(let result):
            results(result)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.recents.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent").font(.headline)
                        Spacer()
                        Button("Clear") { withAnimation { model.clearRecents() } }
                            .font(.subheadline)
                    }
                    ForEach(model.recents, id: \.self) { recent in
                        Button { model.submit(recent, store: store) } label: {
                            Label(recent, systemImage: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Try saying").font(.headline)
                ForEach(examples, id: \.self) { example in
                    Button { model.submit(example, store: store) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "quote.opening").foregroundStyle(Brand.accent)
                            Text(example).multilineTextAlignment(.leading).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .padding(14)
                        .cardStyle(radius: 18)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            privacyNote
        }
    }

    @ViewBuilder
    private func results(_ result: PlanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !result.understood.isEmpty {
                Text(result.understood)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Brand.gradient, in: Capsule())
                    .accessibilityLabel("Looking for: \(result.understood)")
            }

            EngineBadge(engine: result.engine)

            if let reason = result.fallbackReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let note = result.note {
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if result.picks.isEmpty {
                ContentUnavailableView {
                    Label("Nothing coming up", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(store.showSampleEvents
                         ? "Nobody has posted plans yet. Host one with ＋ and people will come to you."
                         : "Sample events are off and nothing is posted yet. Turn them on in Profile → Server, or host a plan with ＋.")
                }
            }

            ForEach(Array(result.picks.enumerated()), id: \.element.id) { index, pick in
                PlanPickCard(pick: pick, isBestFit: index == 0) { detail = pick.activity }
            }

            privacyNote.padding(.top, 4)
        }
    }

    private var privacyNote: some View {
        Label("To plan with Claude, your request, interests and the plans nearby go to your team's server. Nothing is saved there.",
              systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func submit() {
        inputFocused = false
        model.submit(store: store)
    }
}

// MARK: - Pieces

private struct EngineBadge: View {
    let engine: PlanEngine

    var body: some View {
        Label(engine == .claude ? "Planned by Claude" : "Planned on your iPhone",
              systemImage: engine == .claude ? "sparkles" : "iphone")
            .font(.caption.weight(.semibold))
            .foregroundStyle(engine == .claude ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct PlanningProgress: View {
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.gradient)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Planning…").font(.headline)
            }
            ForEach(Array(PlannerModel.steps.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 12) {
                    Group {
                        if index < step {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if index == step {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 22)
                    Text(title)
                        .foregroundStyle(index <= step ? .primary : .secondary)
                }
                .font(.subheadline)
                .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planning. \(PlannerModel.steps[min(step, PlannerModel.steps.count - 1)]).")
    }
}

private struct PlanPickCard: View {
    @Environment(AppStore.self) private var store
    let pick: PlanPick
    let isBestFit: Bool
    let open: () -> Void

    var body: some View {
        let a = pick.activity
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    CategoryBackdrop(category: a.category, animated: false)
                    Image(systemName: a.category.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(a.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text("\(a.date.friendlyDateTime) · \(a.placeName)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if isBestFit {
                    Text("Best fit")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Brand.gradient, in: Capsule())
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Brand.gradient)
                    .accessibilityHidden(true)
                Text(pick.reason)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                AvatarStack(people: store.attendees(of: a), size: 22, max: 3)
                    .accessibilityHidden(true)
                Text("\(a.attendeeIDs.count + 1) going · \(a.spotsLeft) left · \(a.costNote)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                joinControl(a)
            }
        }
        .padding(14)
        .cardStyle(radius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isBestFit ? "Best fit. " : "")\(a.title), \(a.date.friendlyDateTime) at \(a.placeName). \(pick.reason)")
        .accessibilityAction(named: "Open details", open)
        .accessibilityAction(named: a.requiresApproval ? "Request to join" : "Join") { join(a) }
        .animation(.snappy, value: store.isGoing(a))
        .animation(.snappy, value: store.isPending(a))
    }

    @ViewBuilder
    private func joinControl(_ a: Activity) -> some View {
        if store.isGoing(a) {
            Label("Going", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else if store.isPending(a) {
            Label("Requested", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        } else {
            Button { join(a) } label: {
                Text(a.requiresApproval ? "Request" : "Join")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Brand.gradient, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .sensoryFeedback(.success, trigger: store.isGoing(a) || store.isPending(a))
        }
    }

    private func join(_ a: Activity) {
        guard !store.isGoing(a), !store.isPending(a) else { return }
        store.join(a)
    }
}
