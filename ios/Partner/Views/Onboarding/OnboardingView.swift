import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var name = ""
    @State private var age = 21
    @State private var pronouns = ""
    @State private var interests: Set<ActivityCategory> = []
    @State private var access = Permissions()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var nameFocused: Bool

    private let totalSteps = 4

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                if step > 0 { header.transition(.opacity) }

                Group {
                    switch step {
                    case 0: welcome
                    case 1: aboutYou
                    case 2: interestsStep
                    default: permissions
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)

                footer
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.15), value: step)
        .onChange(of: scenePhase) { _, phase in
            // Pick up changes made in the Settings app.
            if phase == .active { Task { await access.refresh() } }
        }
    }

    // MARK: Background

    @ViewBuilder private var background: some View {
        if step == 0 {
            TimelineView(.animation) { ctx in
                let t = Float(ctx.date.timeIntervalSinceReferenceDate)
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + 0.15 * sin(t * 0.7), 0.5 + 0.12 * cos(t * 0.5)], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ], colors: [
                    Color(red: 1, green: 0.42, blue: 0.35), Color(red: 1, green: 0.55, blue: 0.30), Color(red: 1, green: 0.72, blue: 0.35),
                    Color(red: 0.95, green: 0.30, blue: 0.45), Color(red: 1, green: 0.45, blue: 0.38), Color(red: 1, green: 0.60, blue: 0.32),
                    Color(red: 0.62, green: 0.22, blue: 0.58), Color(red: 0.85, green: 0.25, blue: 0.45), Color(red: 0.98, green: 0.38, blue: 0.35)
                ])
            }
        } else {
            Color(.systemGroupedBackground)
        }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                step -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            HStack(spacing: 6) {
                ForEach(1..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                        .frame(height: 5)
                }
            }
            Text("\(step)/\(totalSteps - 1)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                advance()
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(PrimaryButtonStyle(tint: step == 0 ? AnyShapeStyle(Color.white) : AnyShapeStyle(Brand.gradient),
                                            foreground: step == 0 ? Brand.accent : .white))
            .disabled(!canAdvance)

            if step == 0 {
                Text("By continuing you agree to be a good human. 🤝")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        #if DEBUG
        .task {
            // `-step N` jumps to an onboarding step; `-ask` fires the real permission prompts.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-step"), i + 1 < args.count, let n = Int(args[i + 1]) {
                name = "Anant Katiyar"
                pronouns = "he/him, they/them"
                step = n
            }
            if args.contains("-ask") {
                try? await Task.sleep(for: .seconds(1))
                await access.requestNotifications()
            }
        }
        #endif
    }

    private var primaryTitle: String {
        switch step {
        case 0: "Get started"
        case 1: "Continue"
        case 2: interests.count < 3 ? "Pick \(3 - interests.count) more" : "Continue"
        default: "Start exploring"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: interests.count >= 3
        default: true
        }
    }

    private func advance() {
        nameFocused = false
        if step < totalSteps - 1 {
            step += 1
            if step == 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nameFocused = true } }
        } else {
            let ordered = ActivityCategory.allCases.filter { interests.contains($0) }
            store.notificationsEnabled = true
            store.completeOnboarding(name: name.trimmingCharacters(in: .whitespaces), age: age,
                                     pronouns: pronouns, interests: ordered)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            OrbitingIcons()
                .frame(height: 300)
            VStack(spacing: 12) {
                Text("Swipe-n-Go")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                Text("Never do it alone.\nFind people for runs, shows, food and everything in between.")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    private var aboutYou: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                stepTitle("What should we call you?", "This is how you'll appear to others on Swipe‑n‑Go.")

                TextField("First and last name", text: $name)
                    .textContentType(.name)
                    .font(.title3.weight(.medium))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(18)
                    .cardStyle(radius: 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Pronouns").font(.headline)
                    PronounPicker(pronouns: $pronouns)
                        .padding(18)
                        .cardStyle(radius: 20)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Age").font(.headline)
                    HStack {
                        Text("\(age)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: Double(age)))
                            .monospacedDigit()
                        Text("years old").foregroundStyle(.secondary)
                        Spacer()
                        Stepper("Age", value: $age.animation(.snappy), in: 18...99)
                            .labelsHidden()
                    }
                    .padding(18)
                    .cardStyle(radius: 20)
                    Label("Swipe‑n‑Go is for adults 18+.", systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var interestsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stepTitle("What are you into?", "Pick at least 3. We'll tailor your feed to match.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(ActivityCategory.allCases) { cat in
                        InterestTile(category: cat, isSelected: interests.contains(cat)) {
                            if interests.contains(cat) { interests.remove(cat) } else { interests.insert(cat) }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var permissions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stepTitle("Almost there, \(name.split(separator: " ").first.map(String.init) ?? "friend")!",
                          "A couple of things make Swipe‑n‑Go work best.")

                PermissionCard(symbol: "location.fill", tint: .blue, title: "Location",
                               detail: "See plans happening near you. We never share your exact location.",
                               state: access.location,
                               onAllow: { access.requestLocation() },
                               onOpenSettings: { access.openSettings() })
                PermissionCard(symbol: "bell.badge.fill", tint: .red, title: "Notifications",
                               detail: "Know instantly when someone joins your plan or messages you.",
                               state: access.notifications,
                               onAllow: { Task { await access.requestNotifications() } },
                               onOpenSettings: { access.openSettings() })

                VStack(alignment: .leading, spacing: 14) {
                    Label("Meet in public places first", systemImage: "person.2.fill")
                    Label("Verified profiles show a blue check", systemImage: "checkmark.seal.fill")
                    Label("Report or block anyone, anytime", systemImage: "hand.raised.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(radius: 20)
            }
            .padding(24)
        }
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pieces

private struct InterestTile: View {
    let category: ActivityCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : category.color)
                    .symbolEffect(.bounce, value: isSelected)
                Text(category.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(category.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(duration: 0.3, bounce: 0.4), value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct PermissionCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let state: Permissions.State
    let onAllow: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    switch state {
                    case .notAsked: onAllow()          // shows the system dialog
                    case .denied: onOpenSettings()
                    case .allowed: break
                    }
                } label: {
                    Label(buttonTitle, systemImage: buttonSymbol)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .tint(buttonTint)
                .allowsHitTesting(state != .allowed)
                .padding(.top, 6)
                if state == .denied {
                    Text("Turned off. You can change this anytime in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .cardStyle(radius: 20)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: state)
        .sensoryFeedback(.success, trigger: state) { _, new in new == .allowed }
    }

    private var buttonTitle: String {
        switch state {
        case .notAsked: "Allow"
        case .allowed: "Allowed"
        case .denied: "Open Settings"
        }
    }

    private var buttonSymbol: String {
        switch state {
        case .notAsked: "arrow.right"
        case .allowed: "checkmark"
        case .denied: "gear"
        }
    }

    private var buttonTint: Color {
        switch state {
        case .notAsked: tint
        case .allowed: .green
        case .denied: .orange
        }
    }
}

/// Category symbols drifting around a glowing center — the hero on the welcome screen.
private struct OrbitingIcons: View {
    private let cats: [ActivityCategory] = [.run, .concert, .food, .hike, .coffee, .movies, .gym, .art]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)
                        .position(center)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 104, height: 104)
                        .glassEffect(.regular.tint(.white.opacity(0.15)), in: Circle())
                        .position(center)

                    ForEach(Array(cats.enumerated()), id: \.offset) { i, cat in
                        let ring = i.isMultiple(of: 2) ? 120.0 : 92.0
                        let speed = i.isMultiple(of: 2) ? 0.18 : -0.24
                        let angle = Double(i) / Double(cats.count) * .pi * 2 + t * speed
                        Image(systemName: cat.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular.tint(cat.color.opacity(0.55)), in: Circle())
                            .position(x: center.x + cos(angle) * ring * 1.25, y: center.y + sin(angle) * ring)
                    }
                }
            }
        }
    }
}
