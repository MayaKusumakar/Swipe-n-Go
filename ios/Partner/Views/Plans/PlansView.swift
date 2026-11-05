import SwiftUI

struct PlansView: View {
    @Environment(AppStore.self) private var store
    @State private var segment: Segment = .upcoming
    @State private var showCreate = false

    enum Segment: String, CaseIterable { case upcoming = "Going", hosting = "Hosting", saved = "Saved" }

    private var items: [Activity] {
        switch segment {
        case .upcoming: store.upcoming.filter { !store.isHost($0) }
        case .hosting: store.hosting
        case .saved: store.saved
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let next = store.upcoming.first {
                        NavigationLink(value: next) { NextUpCard(activity: next) }
                            .buttonStyle(PressableStyle())
                    }

                    if !store.requests.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Requests", subtitle: "People who want to join your plans")
                            ForEach(store.requests) { req in
                                VStack(alignment: .leading, spacing: 6) {
                                    if let a = store.activity(req.activityID) {
                                        Label(a.title, systemImage: a.category.symbol)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(a.category.color)
                                            .padding(.leading, 4)
                                    }
                                    RequestRow(request: req)
                                }
                            }
                        }
                    }

                    Picker("Plans", selection: $segment.animation(.snappy)) {
                        ForEach(Segment.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    if items.isEmpty {
                        empty
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(items) { a in
                                NavigationLink(value: a) { ActivityRow(activity: a) }
                                    .buttonStyle(PressableStyle())
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.snappy, value: store.requests.count)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plans")
            .navigationDestination(for: Activity.self) { ActivityDetailView(activity: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Host an activity")
                }
            }
            .sheet(isPresented: $showCreate) { CreateActivityView() }
        }
    }

    private var empty: some View {
        let (symbol, title, message): (String, String, String) = switch segment {
        case .upcoming: ("calendar.badge.plus", "No plans yet", "Swipe right on something in Discover and it'll show up here.")
        case .hosting: ("crown", "Host your first plan", "Got an idea? Post it and let people come to you.")
        case .saved: ("bookmark", "Nothing saved", "Swipe up on a card or tap the bookmark to save it for later.")
        }
        return ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if segment == .hosting {
                Button("Host a plan") { showCreate = true }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Go to Discover") { store.selectedTab = .discover }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 20)
    }
}

// MARK: - Next up

private struct NextUpCard: View {
    @Environment(AppStore.self) private var store
    let activity: Activity

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CategoryBackdrop(category: activity.category)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NEXT UP")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glassEffect(.regular.tint(.white.opacity(0.1)), in: Capsule())
                    if store.isPending(activity) {
                        Label("Pending", systemImage: "hourglass")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .glassEffect(.regular.tint(.yellow.opacity(0.3)), in: Capsule())
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(countdown)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
                Spacer()
                Text(activity.title)
                    .font(.title.weight(.bold))
                    .lineLimit(2)
                Text("\(Image(systemName: "calendar")) \(activity.date.friendlyDateTime) · \(activity.placeName)")
                .lineLimit(1)
                .font(.subheadline.weight(.medium))
                .opacity(0.92)
                AvatarStack(people: store.attendees(of: activity), size: 30, max: 5)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: activity.category.color.opacity(0.3), radius: 16, y: 8)
    }

    private var countdown: String {
        let s = Int(activity.date.timeIntervalSinceNow)
        guard s > 0 else { return "Happening now" }
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return "in \(d)d \(h)h" }
        if h > 0 { return "in \(h)h \(m)m" }
        return String(format: "in %d:%02d", m, sec)
    }
}
