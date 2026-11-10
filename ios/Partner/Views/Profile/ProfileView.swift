import SwiftUI

struct ProfileView: View {
    var embedded = false

    var body: some View {
        if embedded {
            ProfileContent()
        } else {
            NavigationStack { ProfileContent(showsDone: true) }
        }
    }
}

private struct ProfileContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var showsDone = false
    @State private var showEdit = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                ProfileHeader(person: store.me, showAge: store.showAgeOnProfile)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                StatsRow(items: [
                    ("\(store.upcoming.filter { !store.isHost($0) }.count)", "Going"),
                    ("\(store.hosting.count)", "Hosting"),
                    ("\(store.me.activitiesDone)", "Done"),
                    (String(format: "%.1f★", store.me.rating), "Rating")
                ])
                .listRowInsets(EdgeInsets(top: 14, leading: 8, bottom: 14, trailing: 8))
            }

            Section("Interests") {
                NavigationLink { InterestsEditor() } label: {
                    FlowLayout(spacing: 8) {
                        ForEach(store.me.interests) { cat in
                            HStack(spacing: 4) {
                                Image(systemName: cat.symbol)
                                Text(cat.title)
                            }
                                .font(.caption.weight(.semibold))
                                .fixedSize()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(cat.color)
                                .background(cat.color.opacity(0.14), in: Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Preferences") {
                Toggle(isOn: $store.notificationsEnabled) {
                    Label("In-app notifications", systemImage: "bell.badge.fill")
                }
                .onChange(of: store.notificationsEnabled) { store.save() }
                Toggle(isOn: $store.showAgeOnProfile) {
                    Label("Show age on profile", systemImage: "person.text.rectangle")
                }
                .onChange(of: store.showAgeOnProfile) { store.save() }
                NavigationLink {
                    DiscoverySettingsSheet()
                } label: {
                    LabeledContent {
                        Text("\(Int(store.radiusMiles)) mi")
                    } label: {
                        Label("Discovery distance", systemImage: "location.circle.fill")
                    }
                }
            }

            Section("Safety") {
                NavigationLink { SafetyCenterView() } label: {
                    Label("Safety center", systemImage: "shield.lefthalf.filled")
                }
                Label("Verify your profile", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.blue)
            }

            Section {
                Button {
                    store.refreshDemoContent()
                    store.show(InAppBanner(title: "Fresh plans loaded", subtitle: "New activities are waiting in Discover",
                                           symbol: "sparkles", color: Brand.accent))
                } label: {
                    Label("Refresh demo content", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Sign out & reset", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Partner prototype v1.0 · Made with ❤️ in Davis")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { EditProfileView() }
        .confirmationDialog("Reset Partner?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Sign out & reset", role: .destructive) { store.resetEverything() }
        } message: {
            Text("This clears your profile, plans and chats on this device.")
        }
    }
}

// MARK: - Shared profile pieces

struct ProfileHeader: View {
    let person: Person
    var showAge = true

    var body: some View {
        VStack(spacing: 12) {
            AvatarView(person: person, size: 110)
                .shadow(color: Color(hue: person.hue, saturation: 0.6, brightness: 0.9).opacity(0.5), radius: 18, y: 8)
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(showAge ? "\(person.name), \(person.age)" : person.name)
                        .font(.title2.weight(.bold))
                    if person.isVerified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 6) {
                    if !person.pronouns.isEmpty { Text(person.pronouns) }
                    if !person.pronouns.isEmpty { Text("·") }
                    HStack(spacing: 4) {
                        Image(systemName: "graduationcap.fill")
                        Text(person.school)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            if !person.bio.isEmpty {
                Text(person.bio)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct StatsRow: View {
    let items: [(String, String)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(spacing: 2) {
                    Text(item.0).font(.title3.weight(.bold).monospacedDigit())
                    Text(item.1).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                if i < items.count - 1 { Divider().frame(height: 30) }
            }
        }
    }
}

// MARK: - Edit profile

struct EditProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Person = AppStore.defaultMe()

    private let emojis = ["😊", "😎", "🤠", "🥳", "🤓", "😇", "🏃", "🧗", "🚴", "🏀", "🎸", "🎧", "🎨", "📚", "☕️", "🌮", "🍜", "🌿", "🐶", "🐱", "🌞", "✨", "🔥", "🌊"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        AvatarView(person: draft, size: 100)
                            .animation(.snappy, value: draft.emoji)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                            ForEach(emojis, id: \.self) { e in
                                Button { draft.emoji = e } label: {
                                    Text(e).font(.title2)
                                        .frame(width: 36, height: 36)
                                        .background(draft.emoji == e ? Color.accentColor.opacity(0.2) : .clear, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Image(systemName: "paintpalette.fill").foregroundStyle(.secondary)
                            Slider(value: $draft.hue, in: 0...1)
                                .tint(Color(hue: draft.hue, saturation: 0.6, brightness: 0.9))
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("About you") {
                    TextField("Name", text: $draft.name)
                    TextField("Pronouns", text: $draft.pronouns)
                    Stepper("Age: \(draft.age)", value: $draft.age, in: 18...99)
                    TextField("School or work", text: $draft.school)
                }

                Section {
                    TextField("Tell people what you're into", text: $draft.bio, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Bio")
                } footer: {
                    Text("\(draft.bio.count)/150")
                        .foregroundStyle(draft.bio.count > 150 ? .red : .secondary)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        draft.bio = String(draft.bio.prefix(150))
                        store.updateProfile(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { draft = store.me }
        }
    }
}

// MARK: - Interests editor

struct InterestsEditor: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(ActivityCategory.allCases) { cat in
                    let on = store.me.interests.contains(cat)
                    Button {
                        var p = store.me
                        if on { p.interests.removeAll { $0 == cat } } else { p.interests.append(cat) }
                        withAnimation(.snappy) { store.updateProfile(p) }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: cat.symbol).font(.title2.weight(.semibold))
                            Text(cat.title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(on ? .white : cat.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .background(on ? AnyShapeStyle(cat.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: on)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Interests")
    }
}

// MARK: - Someone else's profile

struct PersonProfileView: View {
    @Environment(AppStore.self) private var store
    let person: Person
    @State private var reported = false
    @State private var confirmReport = false

    private var theirPlans: [Activity] {
        store.activities.filter { $0.hostID == person.id && !$0.isPast }
    }

    private var shared: Set<ActivityCategory> { Set(person.interests).intersection(store.me.interests) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ProfileHeader(person: person)

                HStack(spacing: 12) {
                    Button {
                        let id = store.directConversation(with: person.id)
                        store.selectedTab = .chats
                        store.requestedChat = id
                    } label: {
                        Label("Message", systemImage: "bubble.left.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 20)

                StatsRow(items: [
                    ("\(person.activitiesDone)", "Plans done"),
                    (String(format: "%.1f★", person.rating), "Rating"),
                    ("\(shared.count)", "In common")
                ])
                .padding(.vertical, 14)
                .cardStyle(radius: 20)
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Interests", subtitle: shared.isEmpty ? nil : "Highlighted ones you share")
                    FlowLayout(spacing: 8) {
                        ForEach(person.interests) { cat in
                            let isShared = shared.contains(cat)
                            Label(cat.title, systemImage: cat.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(isShared ? .white : cat.color)
                                .background(isShared ? AnyShapeStyle(cat.gradient) : AnyShapeStyle(cat.color.opacity(0.14)), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 20)

                if !theirPlans.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "\(person.firstName)'s plans")
                        ForEach(theirPlans) { a in
                            NavigationLink {
                                ActivityDetailView(activity: a)
                            } label: {
                                ActivityRow(activity: a)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: "Check out \(person.firstName) on Partner!") {
                        Label("Share profile", systemImage: "square.and.arrow.up")
                    }
                    Button("Report", systemImage: "flag.fill", role: .destructive) { confirmReport = true }
                    Button("Block", systemImage: "hand.raised.fill", role: .destructive) { confirmReport = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("Thanks for letting us know", isPresented: $reported) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Our safety team will review this. \(person.firstName) won't be told it was you.")
        }
        .confirmationDialog("Report or block \(person.firstName)?", isPresented: $confirmReport, titleVisibility: .visible) {
            Button("Report & block", role: .destructive) { reported = true }
        }
    }
}

// MARK: - Safety

struct SafetyCenterView: View {
    var body: some View {
        List {
            Section {
                tip("person.2.fill", .blue, "Meet in public", "Pick busy, well-lit spots for first meetups — cafés, parks, campus.")
                tip("location.fill", .green, "Share your plans", "Tell a friend where you're going and who you're meeting.")
                tip("checkmark.seal.fill", .cyan, "Look for verified profiles", "A blue check means we've verified their identity.")
                tip("car.fill", .orange, "Get there your own way", "Especially the first time, arrange your own transport.")
                tip("hand.raised.fill", .red, "Trust your gut", "Leave anytime you feel uncomfortable. Report anyone who makes you feel unsafe.")
            }
            Section {
                Link(destination: URL(string: "tel:911")!) {
                    Label("Emergency: call 911", systemImage: "phone.fill").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Safety center")
    }

    private func tip(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
