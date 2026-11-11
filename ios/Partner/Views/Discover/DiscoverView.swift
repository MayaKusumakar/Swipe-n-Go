import SwiftUI

struct Celebration: Identifiable {
    let id = UUID()
    let activity: Activity
    let outcome: JoinOutcome
}

struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @State private var filter: ActivityCategory?
    @State private var dragOffset: CGSize = .zero
    @State private var isFlying = false
    @State private var detail: Activity?
    @State private var celebration: Celebration?
    @State private var showFilters = false
    @State private var haptic = 0

    private var deck: [Activity] {
        guard let filter else { return store.discoverDeck }
        return store.discoverDeck.filter { $0.category == filter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                PlannerPromptBar()
                    .padding(.horizontal, 16)
                filterBar

                ZStack {
                    if deck.isEmpty {
                        emptyState.transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        ForEach(Array(deck.prefix(3).enumerated().reversed()), id: \.element.id) { index, activity in
                            card(activity, depth: index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .animation(.spring(duration: 0.4, bounce: 0.2), value: deck.map(\.id))

                actionBar
                    .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Discover")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Discovery settings")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
                    .sharedBackgroundVisibility(.hidden)
            }
            .sheet(item: $detail) { activity in
                NavigationStack { ActivityDetailView(activity: activity, isSheet: true) }
            }
            .sheet(isPresented: $showFilters) { DiscoverySettingsSheet().presentationDetents([.medium]) }
            .fullScreenCover(item: $celebration) { c in
                CelebrationView(celebration: c)
                    .presentationBackground(.clear)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: haptic)
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("-detail") { detail = deck.first }
            }
            #endif
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    filter = nil
                } label: {
                    Label("For You", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(filter == nil ? .white : .primary)
                        .background(filter == nil ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.thinMaterial), in: Capsule())
                }
                .buttonStyle(.plain)

                let ordered = store.me.interests + ActivityCategory.allCases.filter { !store.me.interests.contains($0) }
                ForEach(ordered) { cat in
                    CategoryChip(category: cat, isSelected: filter == cat) {
                        filter = filter == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: filter)
    }

    // MARK: Card

    @ViewBuilder
    private func card(_ activity: Activity, depth: Int) -> some View {
        let isTop = depth == 0
        SwipeCard(activity: activity, dragOffset: isTop ? dragOffset : .zero)
            .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.05 + min(abs(dragOffset.width) / 3000, 0.05))
            .offset(y: isTop ? 0 : CGFloat(depth) * 14)
            .offset(isTop ? dragOffset : .zero)
            .rotationEffect(.degrees(isTop ? Double(dragOffset.width / 22) : 0), anchor: .bottom)
            .allowsHitTesting(isTop && !isFlying)
            .zIndex(Double(10 - depth))
            .onTapGesture { detail = activity }
            .gesture(isTop ? dragGesture(for: activity) : nil)
            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .identity))
            .accessibilityAction(named: "Join") { perform(.join, on: activity) }
            .accessibilityAction(named: "Skip") { perform(.skip, on: activity) }
    }

    private func dragGesture(for activity: Activity) -> some Gesture {
        DragGesture()
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let predicted = value.predictedEndTranslation
                if value.translation.width > 110 || predicted.width > 400 {
                    perform(.join, on: activity)
                } else if value.translation.width < -110 || predicted.width < -400 {
                    perform(.skip, on: activity)
                } else if value.translation.height < -140 || predicted.height < -500 {
                    perform(.save, on: activity)
                } else {
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) { dragOffset = .zero }
                }
            }
    }

    private func perform(_ action: SwipeAction, on activity: Activity) {
        guard !isFlying else { return }
        isFlying = true
        haptic += 1
        let target: CGSize = switch action {
        case .join: CGSize(width: 650, height: dragOffset.height + 40)
        case .skip: CGSize(width: -650, height: dragOffset.height + 40)
        case .save: CGSize(width: dragOffset.width, height: -1000)
        }
        withAnimation(.easeIn(duration: 0.28)) { dragOffset = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                store.swipe(activity, action)
                dragOffset = .zero
            }
            isFlying = false
            if action == .join {
                celebration = Celebration(activity: activity, outcome: activity.requiresApproval ? .requested : .joined)
            } else if action == .save {
                store.show(InAppBanner(title: "Saved for later", subtitle: activity.title, symbol: "bookmark.fill", color: .blue))
            }
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        let top = deck.first
        return GlassEffectContainer(spacing: 18) {
            HStack(spacing: 18) {
                RoundAction(symbol: "arrow.uturn.backward", tint: .yellow, size: 48) {
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { store.undoLastSwipe() }
                }
                .disabled(!store.canUndo)
                .opacity(store.canUndo ? 1 : 0.45)
                .accessibilityLabel("Undo")

                RoundAction(symbol: "xmark", tint: .red, size: 62) {
                    if let top { perform(.skip, on: top) }
                }
                .accessibilityLabel("Skip")

                RoundAction(symbol: "checkmark", tint: Brand.accent, size: 74, prominent: true) {
                    if let top { perform(.join, on: top) }
                }
                .accessibilityLabel("Join")

                RoundAction(symbol: "bookmark.fill", tint: .blue, size: 62) {
                    if let top { perform(.save, on: top) }
                }
                .accessibilityLabel("Save")

                RoundAction(symbol: "info", tint: .secondary, size: 48) {
                    detail = top
                }
                .accessibilityLabel("Details")
            }
        }
        .disabled(top == nil)
        .opacity(top == nil ? 0.5 : 1)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Brand.gradient)
                .symbolEffect(.breathe)
            Text(filter == nil ? "You're all caught up" : "No more \(filter!.title.lowercased()) plans")
                .font(.title2.weight(.bold))
            Text("New plans pop up all the time. Or be the one who starts something.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
            VStack(spacing: 10) {
                Button("Host an activity") { store.showCreate = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 240)
                PlannerShortcutButton()
                Button("Review skipped plans") {
                    withAnimation { filter = nil; store.resetSkipped() }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardStyle(radius: 32)
    }
}

// MARK: - Round action button

private struct RoundAction: View {
    let symbol: String
    let tint: Color
    let size: CGFloat
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(prominent ? .white : tint)
                .frame(width: size, height: size)
                .background {
                    if prominent { Circle().fill(Brand.gradient).shadow(color: Brand.accent.opacity(0.45), radius: 12, y: 6) }
                }
                .glassEffect(prominent ? .regular.interactive().tint(Brand.accent) : .regular.interactive(), in: Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Swipe card

struct SwipeCard: View {
    @Environment(AppStore.self) private var store
    let activity: Activity
    var dragOffset: CGSize = .zero

    private var host: Person? { store.person(activity.hostID) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ActivityCover(category: activity.category, photoData: activity.coverPhotoData)

            LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.75)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label(activity.category.title, systemImage: activity.category.symbol)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassEffect(.regular.tint(.white.opacity(0.1)), in: Capsule())
                    if store.me.interests.contains(activity.category) {
                        Label("For you", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassEffect(.regular.tint(.yellow.opacity(0.35)), in: Capsule())
                    }
                }
                .foregroundStyle(.white)

                Spacer()

                Text(activity.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 10) {
                    AvatarView(person: host, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text("Hosted by \(host?.firstName ?? "Someone")").font(.subheadline.weight(.semibold))
                            if host?.isVerified == true {
                                Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.cyan)
                            }
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                            Text(String(format: "%.1f", host?.rating ?? 5)).font(.caption.weight(.semibold))
                            Text("· \(host?.activitiesDone ?? 0) plans").font(.caption)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    AvatarStack(people: activity.attendeeIDs.compactMap(store.person), size: 28, max: 3)
                }
                .foregroundStyle(.white)

                HStack(spacing: 6) {
                    infoChip("calendar", "\(activity.date.friendlyDay) \(activity.date.friendlyTime)")
                        .layoutPriority(1)
                    infoChip(store.canSeeLocation(activity) ? "location.fill" : "eye.slash.fill", store.distanceLabel(activity))
                    infoChip("person.2.fill", "\(activity.spotsLeft) left")
                }
            }
            .padding(22)

            stamps
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func infoChip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(.white.opacity(0.18), in: Capsule())
    }

    @ViewBuilder private var stamps: some View {
        let joinAmount = min(max(dragOffset.width / 120, 0), 1)
        let skipAmount = min(max(-dragOffset.width / 120, 0), 1)
        let saveAmount = min(max(-dragOffset.height / 140, 0), 1) * (1 - max(joinAmount, skipAmount))
        ZStack {
            stamp("JOIN", .green, -14).opacity(joinAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(28).padding(.top, 40)
            stamp("PASS", .red, 14).opacity(skipAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(28).padding(.top, 40)
            stamp("SAVE", .blue, 0).opacity(saveAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .allowsHitTesting(false)
    }

    private func stamp(_ text: String, _ color: Color, _ angle: Double) -> some View {
        Text(text)
            .font(.system(size: 40, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 5))
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Celebration

struct CelebrationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let celebration: Celebration
    @State private var appeared = false

    private var activity: Activity { celebration.activity }
    private var host: Person? { store.person(activity.hostID) }
    private var joined: Bool { celebration.outcome == .joined }

    var body: some View {
        ZStack {
            ActivityCover(category: activity.category, photoData: activity.coverPhotoData)
                .overlay(.black.opacity(0.25))
                .ignoresSafeArea()

            ConfettiView(colors: [.white, .yellow, activity.category.color.mix(with: .white, by: 0.4), .pink])
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 26) {
                Spacer()
                Text(joined ? "It's a plan!" : "Request sent!")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)

                Text(joined
                     ? "You and \(host?.firstName ?? "your host") are doing **\(activity.title)** \(activity.date.friendlyDay.lowercased() == "today" ? "today" : "on \(activity.date.friendlyDay)")."
                     : "\(host?.firstName ?? "The host") reviews requests for **\(activity.title)**. We'll let you know as soon as you're in.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 30)

                HStack(spacing: -22) {
                    AvatarView(person: store.me, size: 120, showsRing: true)
                        .rotationEffect(.degrees(appeared ? -8 : -30))
                        .offset(x: appeared ? 0 : -120)
                    AvatarView(person: host, size: 120, showsRing: true)
                        .rotationEffect(.degrees(appeared ? 8 : 30))
                        .offset(x: appeared ? 0 : 120)
                }
                .overlay {
                    Image(systemName: joined ? "checkmark" : "hourglass")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Brand.gradient, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .offset(y: 56)
                        .scaleEffect(appeared ? 1 : 0)
                }
                .padding(.vertical, 20)

                Spacer()

                VStack(spacing: 12) {
                    if joined {
                        Button {
                            let id = store.groupConversation(for: activity)
                            dismiss()
                            store.selectedTab = .chats
                            store.requestedChat = id
                        } label: {
                            Label("Say hi to the group", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: AnyShapeStyle(Color.white), foreground: activity.category.color))
                    }
                    Button(joined ? "Keep swiping" : "Got it") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.45).delay(0.05)) { appeared = true }
        }
        .sensoryFeedback(.success, trigger: appeared)
    }
}

/// Lightweight confetti using Canvas.
struct ConfettiView: View {
    let colors: [Color]
    @State private var start = Date.now
    private let pieces: [(x: Double, speed: Double, spin: Double, size: Double, sway: Double, delay: Double, color: Int)] =
        (0..<90).map { i in
            (Double.random(in: 0...1), Double.random(in: 140...320), Double.random(in: -6...6),
             Double.random(in: 6...12), Double.random(in: 10...40), Double.random(in: 0...0.8), i)
        }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                for p in pieces {
                    let time = max(0, t - p.delay)
                    let y = -20 + time * p.speed
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(time * 2 + p.x * 10) * p.sway
                    var g = gc
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .radians(time * p.spin))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                    g.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[p.color % colors.count]))
                }
            }
        }
    }
}

// MARK: - Discovery settings

struct DiscoverySettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Distance")
                            Spacer()
                            Text("\(Int(store.radiusMiles)) mi")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        Slider(value: $store.radiusMiles, in: 1...150, step: 1) {
                            Text("Distance")
                        } onEditingChanged: { editing in
                            if !editing { store.save() }
                        }
                    }
                } footer: {
                    Text("Show plans within this distance of Davis, CA.")
                }

                Section("Interests") {
                    NavigationLink {
                        InterestsEditor()
                    } label: {
                        HStack {
                            Text("Your interests")
                            Spacer()
                            Text("\(store.me.interests.count) selected").foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Show skipped plans again") {
                        store.resetSkipped()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Discovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}
