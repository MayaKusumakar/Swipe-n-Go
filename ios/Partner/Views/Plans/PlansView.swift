import SwiftUI

struct PlansView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: Tab = .going
    @State private var hostingSection: HostingSection = .plans
    @State private var editingDraft: ActivityDraft?
    @State private var draftError = false

    enum Tab: String, CaseIterable { case hosting = "Host", going = "Going", saved = "Saved" }
    /// Shown inside the Host tab only.
    enum HostingSection: String, CaseIterable { case plans = "Your plans", drafts = "Drafts", scheduled = "Scheduled" }

    /// Which list is on screen, combining the tab and, under Hosting, its section.
    private enum Segment { case upcoming, hosting, saved, drafts, scheduled }

    private var segment: Segment {
        switch tab {
        case .going: return .upcoming
        case .saved: return .saved
        case .hosting: break
        }
        switch hostingSection {
        case .plans: return .hosting
        case .drafts: return .drafts
        case .scheduled: return .scheduled
        }
    }

    private var items: [Activity] {
        switch segment {
        case .upcoming: store.upcoming.filter { !store.isHost($0) }
        case .hosting: store.hosting
        case .saved: store.saved
        case .drafts, .scheduled: []
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

                    Picker("Plans", selection: $tab.animation(.snappy)) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    if tab == .hosting {
                        Picker("Hosting", selection: $hostingSection.animation(.snappy)) {
                            ForEach(HostingSection.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }

                    if segment == .saved, store.pendingSaves.isEmpty == false, !store.serverStatus.isOnline {
                        Label("Saved on this iPhone. Your other devices get it when the server is reachable.",
                              systemImage: "icloud.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if segment == .drafts || segment == .scheduled {
                        draftList
                    } else if items.isEmpty {
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
            .profileToolbarButton()
            .sheet(item: $editingDraft) { CreateActivityView(draft: $0) }
            .alert("Could not save changes", isPresented: $draftError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
        }
    }

    private var draftList: some View {
        let posts = store.drafts.filter {
            segment == .scheduled ? $0.scheduledAt != nil : $0.scheduledAt == nil
        }
        return VStack(alignment: .leading, spacing: 16) {
            if posts.isEmpty {
                ContentUnavailableView(
                    segment == .scheduled ? "No scheduled posts" : "No drafts",
                    systemImage: segment == .scheduled ? "clock" : "doc",
                    description: Text("Start a plan with +, then save a draft or schedule it for later.")
                )
            }
            ForEach(posts) { draft in
                VStack(alignment: .leading, spacing: 10) {
                    Text(draft.title.isEmpty ? "Untitled plan" : draft.title)
                        .font(.headline)
                    if let recurrence = draft.recurrence {
                        Text("\(recurrence.frequency.rawValue) · \(recurrence.count) events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let scheduledAt = draft.scheduledAt {
                        Text("Publishes \(scheduledAt.friendlyDateTime)")
                            .font(.subheadline)
                        Text("Editing pauses scheduled publishing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Saved \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(draft.scheduledAt == nil ? "Continue editing" : "Edit and pause schedule") {
                            var editable = draft
                            editable.scheduledAt = nil
                            guard store.saveDraft(editable) else {
                                draftError = true
                                return
                            }
                            editingDraft = editable
                        }
                        Spacer()
                        Button("Delete", role: .destructive) {
                            if !store.deleteDraft(draft.id) { draftError = true }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .cardStyle(radius: 18)
            }
        }
    }

    private var empty: some View {
        let (symbol, title, message): (String, String, String) = switch segment {
        case .upcoming: ("calendar.badge.plus", "No plans yet", "Swipe right on something in Discover and it'll show up here.")
        case .hosting: ("crown", "Host your first plan", "Got an idea? Post it and let people come to you.")
        case .drafts, .scheduled: ("doc", "No posts", "Your unfinished posts appear here.")
        case .saved: ("bookmark", "Nothing saved yet", "Swipe up on a card or tap the bookmark on an event to save it for later.")
        }
        return ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if segment == .hosting {
                Button("Host a plan") { store.showCreate = true }
                    .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 10) {
                    PlannerShortcutButton()
                    Button("Go to Discover") { store.selectedTab = .discover }
                        .buttonStyle(.bordered)
                }
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
            ActivityCover(category: activity.category, photoData: activity.coverPhotoData)
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
                Text("\(Image(systemName: "calendar")) \(activity.date.friendlyDateTime) · \(store.placeLabel(activity))")
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
