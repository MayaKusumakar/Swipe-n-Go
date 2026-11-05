import SwiftUI
import MapKit

struct ActivityDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let activity: Activity
    var isSheet = false

    @State private var celebration: Celebration?
    @State private var confirmLeave = false
    @State private var confirmCancel = false

    private var live: Activity { store.activity(activity.id) ?? activity }
    private var host: Person? { store.person(live.hostID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 22) {
                    quickFacts
                    if store.isHost(live) { hostTools }
                    hostCard
                    about
                    goingSection
                    locationSection
                    safetyNote
                }
                .padding(20)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: "Join me for \(live.title) on Partner — \(live.date.friendlyDateTime) at \(live.placeName)!") {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    store.toggleSaved(live)
                } label: {
                    Image(systemName: store.isSaved(live) ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.selection, trigger: store.isSaved(live))
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .fullScreenCover(item: $celebration) { c in
            CelebrationView(celebration: c).presentationBackground(.clear)
        }
        .confirmationDialog("Leave this plan?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave plan", role: .destructive) { withAnimation { store.leave(live) } }
        } message: {
            Text("\(host?.firstName ?? "The host") will be notified. You can always request to join again.")
        }
        .confirmationDialog("Cancel this plan?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel plan", role: .destructive) {
                store.cancel(live)
                dismiss()
            }
        } message: {
            Text("Everyone who joined will be notified.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let stretch = max(0, minY)
            ZStack(alignment: .bottomLeading) {
                CategoryBackdrop(category: live.category)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    Label(live.category.title, systemImage: live.category.symbol)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassEffect(.regular.tint(.white.opacity(0.1)), in: Capsule())
                    Text(live.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Text("\(live.date.friendlyDateTime) · \(live.placeName)")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(width: geo.size.width, height: geo.size.height + stretch)
            .offset(y: -stretch)
        }
        .frame(height: 360)
    }

    // MARK: Facts

    private var quickFacts: some View {
        HStack(spacing: 0) {
            fact("calendar", live.date.friendlyDay, live.date.friendlyTime)
            Divider().frame(height: 40)
            fact("clock.fill", durationText, "Duration")
            Divider().frame(height: 40)
            fact("location.fill", Geo.distanceText(to: live.coordinate), "Away")
            Divider().frame(height: 40)
            fact("creditcard.fill", live.costNote, "Cost")
        }
        .padding(.vertical, 16)
        .cardStyle(radius: 22)
    }

    private var durationText: String {
        let h = live.durationMinutes / 60, m = live.durationMinutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func fact(_ symbol: String, _ value: String, _ caption: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(live.category.color)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    // MARK: Host tools

    private var hostTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Requests", subtitle: store.requests(for: live).isEmpty ? "No pending requests right now" : nil)
            ForEach(store.requests(for: live)) { req in
                RequestRow(request: req)
            }
            Button(role: .destructive) { confirmCancel = true } label: {
                Label("Cancel plan", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: Host

    private var hostCard: some View {
        NavigationLink {
            if let host { PersonProfileView(person: host) }
        } label: {
            HStack(spacing: 14) {
                AvatarView(person: host, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(host?.name ?? "Host").font(.headline)
                        if host?.isVerified == true {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.subheadline)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f", host?.rating ?? 5)).fontWeight(.semibold)
                        Text("· Hosted \(host?.activitiesDone ?? 0) plans").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Text(host?.bio ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .cardStyle(radius: 22)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
    }

    // MARK: About

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "About")
            Text(live.details).font(.body).foregroundStyle(.primary.opacity(0.85))
            FlowLayout(spacing: 8) {
                TagPill(text: live.level.rawValue, tint: live.category.color)
                if live.requiresApproval { TagPill(text: "Host approves", tint: .orange) }
                ForEach(live.tags, id: \.self) { TagPill(text: $0) }
            }
        }
    }

    // MARK: Going

    private var goingSection: some View {
        let people = store.attendees(of: live)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Who's going")
                Text("\(people.count)/\(live.capacity)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(people.count), total: Double(live.capacity))
                .tint(live.category.color)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(people) { p in
                        NavigationLink {
                            if p.id == store.me.id { ProfileView(embedded: true) } else { PersonProfileView(person: p) }
                        } label: {
                            VStack(spacing: 6) {
                                AvatarView(person: p, size: 56)
                                    .overlay(alignment: .bottomTrailing) {
                                        if p.id == live.hostID {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(5)
                                                .background(.orange, in: Circle())
                                                .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                                        }
                                    }
                                Text(p.id == store.me.id ? "You" : p.firstName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .frame(width: 64)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(0..<live.spotsLeft, id: \.self) { _ in
                        VStack(spacing: 6) {
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .foregroundStyle(.tertiary)
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "plus").foregroundStyle(.tertiary))
                            Text("Open").font(.caption).foregroundStyle(.tertiary)
                        }
                        .frame(width: 64)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Where")
            VStack(spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(center: live.coordinate,
                                                                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                    Annotation(live.placeName, coordinate: live.coordinate) {
                        CategoryIcon(category: live.category, size: 36)
                            .shadow(radius: 4, y: 2)
                    }
                }
                .frame(height: 170)
                .allowsHitTesting(false)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.placeName).font(.subheadline.weight(.semibold))
                        Text(live.address).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        let item = MKMapItem(location: CLLocation(latitude: live.latitude, longitude: live.longitude), address: nil)
                        item.name = live.placeName
                        item.openInMaps()
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
            }
            .cardStyle(radius: 22)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var safetyNote: some View {
        Label {
            Text("Meet in public, tell a friend where you're going, and trust your gut. You can report anyone from their profile.")
        } icon: {
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(.green)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
    }

    // MARK: Bottom bar

    @ViewBuilder private var bottomBar: some View {
        HStack(spacing: 12) {
            if store.isHost(live) {
                chatButton(title: "Open group chat")
            } else if store.isGoing(live) {
                Menu {
                    Button("Leave plan", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                } label: {
                    Label("Going", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .frame(height: 54)
                        .padding(.horizontal, 18)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                chatButton(title: "Group chat")
            } else if store.isPending(live) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Request sent — waiting for \(host?.firstName ?? "host")")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .glassEffect(.regular, in: Capsule())
            } else if live.isFull {
                Text("This plan is full")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .glassEffect(.regular, in: Capsule())
            } else {
                Button {
                    if let host { messageHost(host) }
                } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.title3)
                        .frame(width: 54, height: 54)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Message host")

                Button {
                    let outcome = store.join(live)
                    celebration = Celebration(activity: live, outcome: outcome)
                } label: {
                    Label(live.requiresApproval ? "Request to join" : "Join · \(live.spotsLeft) spot\(live.spotsLeft == 1 ? "" : "s") left",
                          systemImage: live.requiresApproval ? "hand.wave.fill" : "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle(tint: AnyShapeStyle(live.category.gradient)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .animation(.snappy, value: store.isGoing(live))
        .animation(.snappy, value: store.isPending(live))
    }

    private func chatButton(title: String) -> some View {
        Button {
            let id = store.groupConversation(for: live)
            openChat(id)
        } label: {
            Label(title, systemImage: "bubble.left.and.bubble.right.fill")
        }
        .buttonStyle(PrimaryButtonStyle(tint: AnyShapeStyle(live.category.gradient)))
    }

    private func messageHost(_ host: Person) {
        openChat(store.directConversation(with: host.id))
    }

    private func openChat(_ id: UUID) {
        if isSheet { dismiss() }
        store.selectedTab = .chats
        store.requestedChat = id
    }
}

// MARK: - Request row

struct RequestRow: View {
    @Environment(AppStore.self) private var store
    let request: JoinRequest

    var body: some View {
        let person = store.person(request.personID)
        HStack(alignment: .top, spacing: 12) {
            AvatarView(person: person, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(person?.name ?? "Someone").font(.subheadline.weight(.semibold))
                    if person?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                    }
                    Spacer()
                    Text(request.date.relativeShort).font(.caption).foregroundStyle(.secondary)
                }
                Text("“\(request.note)”").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) { store.approve(request) }
                    } label: {
                        Label("Accept", systemImage: "checkmark").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Button {
                        withAnimation(.snappy) { store.decline(request) }
                    } label: {
                        Text("Decline").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .cardStyle(radius: 20)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
