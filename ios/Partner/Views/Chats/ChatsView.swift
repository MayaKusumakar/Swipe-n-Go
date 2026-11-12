import SwiftUI

struct ChatsView: View {
    @Environment(AppStore.self) private var store
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var deleting: Conversation?

    private var filtered: [Conversation] {
        guard !query.isEmpty else { return store.conversations }
        return store.conversations.filter { store.title(for: $0).localizedCaseInsensitiveContains(query) }
    }

    private var groups: [Conversation] { filtered.filter { $0.activityID != nil } }
    private var directs: [Conversation] { filtered.filter { $0.activityID == nil } }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.conversations.isEmpty {
                    ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Join a plan and you'll be added to its group chat."))
                        .listRowBackground(Color.clear)
                }
                if !groups.isEmpty {
                    Section("Plans") {
                        ForEach(groups) { c in
                            row(c)
                        }
                    }
                }
                if !directs.isEmpty {
                    Section("Direct messages") {
                        ForEach(directs) { c in
                            row(c)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search chats")
            .navigationTitle("Chats")
            .profileToolbarButton()
            .navigationDestination(for: UUID.self) { ChatView(conversationID: $0) }
            .animation(.snappy, value: store.conversations.map(\.id))
        }
        .confirmationDialog(deleting.map { "Delete “\(store.title(for: $0))”?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { c in
            Button("Delete chat", role: .destructive) {
                withAnimation(.snappy) { store.deleteConversation(c.id) }
            }
        } message: { c in
            Text(c.activityID == nil
                 ? "The messages will be removed from this iPhone."
                 : "The messages will be removed from this iPhone. You'll stay in the plan.")
        }
        .onChange(of: store.requestedChat, initial: true) { _, id in
            guard let id else { return }
            path = [id]
            store.requestedChat = nil
        }
    }
}

extension ChatsView {
    /// A chat row with the usual swipe actions and long-press menu.
    fileprivate func row(_ c: Conversation) -> some View {
        NavigationLink(value: c.id) { ConversationRow(conversation: c) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = c }
                muteButton(c).tint(.indigo)
            }
            .swipeActions(edge: .leading) {
                if c.unreadCount > 0 {
                    Button("Read", systemImage: "envelope.open") { store.markRead(c.id) }.tint(.blue)
                }
            }
            .contextMenu {
                muteButton(c)
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = c }
            }
    }

    private func muteButton(_ c: Conversation) -> some View {
        Button(c.muted ? "Unmute" : "Mute", systemImage: c.muted ? "bell" : "bell.slash") {
            withAnimation(.snappy) { store.toggleMute(c.id) }
        }
    }
}

private struct ConversationRow: View {
    @Environment(AppStore.self) private var store
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(store.title(for: conversation))
                        .font(.body.weight(conversation.unreadCount > 0 ? .bold : .semibold))
                        .lineLimit(1)
                    if conversation.muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Muted")
                    }
                    Spacer()
                    Text(conversation.lastMessage?.date.relativeShort ?? "")
                        .font(.caption)
                        .foregroundStyle(conversation.unreadCount > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                HStack {
                    Group {
                        if store.typing[conversation.id] != nil {
                            Text("typing…").italic().foregroundStyle(.tint)
                        } else {
                            Text(preview)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    Spacer()
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(conversation.muted ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Brand.accent), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var preview: String {
        guard let m = conversation.lastMessage else { return "Say hi 👋" }
        if m.kind == .system { return m.text }
        let who = m.senderID == store.me.id ? "You" : (store.person(m.senderID)?.firstName ?? "")
        return conversation.activityID == nil && m.senderID != store.me.id ? m.text : "\(who): \(m.text)"
    }

    @ViewBuilder private var avatar: some View {
        if let aid = conversation.activityID, let a = store.activity(aid) {
            CategoryIcon(category: a.category, size: 52)
        } else {
            AvatarView(person: store.others(in: conversation).first, size: 52)
        }
    }
}

// MARK: - Chat

struct ChatView: View {
    @Environment(AppStore.self) private var store
    let conversationID: UUID
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @State private var sentCount = 0

    private var convo: Conversation? { store.conversation(conversationID) }
    private var activity: Activity? { convo?.activityID.flatMap(store.activity) }

    private let quickReplies = ["On my way! 🚶", "Running 5 min late", "Where should we meet? 📍", "Can't wait 🙌"]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if let convo {
                    header(convo)
                    ForEach(Array(convo.messages.enumerated()), id: \.element.id) { i, m in
                        let prev = i > 0 ? convo.messages[i - 1] : nil
                        let next = i + 1 < convo.messages.count ? convo.messages[i + 1] : nil
                        if prev == nil || m.date.timeIntervalSince(prev!.date) > 3600 {
                            Text(m.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                        MessageRow(message: m, isGroup: convo.activityID != nil,
                                   showsSender: prev?.senderID != m.senderID || prev?.kind == .system,
                                   isLastInRun: next?.senderID != m.senderID || next?.kind == .system)
                            .id(m.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    if let typer = store.typing[conversationID] {
                        TypingBubble(person: store.person(typer))
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading)))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: convo?.messages.count)
            .animation(.snappy, value: store.typing[conversationID])
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .navigationTitle(convo.map(store.title) ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let activity {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ActivityDetailView(activity: activity)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            } else if let other = convo.flatMap({ store.others(in: $0).first }) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PersonProfileView(person: other)
                    } label: {
                        AvatarView(person: other, size: 30)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { inputBar }
        .onAppear {
            store.openConversationID = conversationID
            store.markRead(conversationID)
        }
        .onDisappear {
            if store.openConversationID == conversationID { store.openConversationID = nil }
        }
        .onChange(of: convo?.messages.count) { store.markRead(conversationID) }
        .sensoryFeedback(.impact(weight: .light), trigger: sentCount)
    }

    @ViewBuilder
    private func header(_ convo: Conversation) -> some View {
        if let activity {
            NavigationLink {
                ActivityDetailView(activity: activity)
            } label: {
                HStack(spacing: 12) {
                    CategoryIcon(category: activity.category, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text("\(activity.date.friendlyDateTime) · \(store.placeLabel(activity))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    AvatarStack(people: store.attendees(of: activity), size: 24, max: 3)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .padding(.vertical, 10)
        } else if let other = store.others(in: convo).first {
            VStack(spacing: 8) {
                AvatarView(person: other, size: 80)
                Text(other.name).font(.headline)
                Text(other.interests.prefix(3).map(\.title).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if activity != nil && !inputFocused && draft.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(quickReplies, id: \.self) { r in
                            Button(r) { send(r) }
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .glassEffect(.regular.interactive(), in: Capsule())
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onSubmit { send(draft) }

                Button { send(draft) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(draft.trimmingCharacters(in: .whitespaces).isEmpty ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(Brand.gradient), in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .animation(.snappy, value: inputFocused)
        .animation(.snappy, value: draft.isEmpty)
    }

    private func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.send(text, in: conversationID)
        draft = ""
        sentCount += 1
    }
}

// MARK: - Bubbles

private struct MessageRow: View {
    @Environment(AppStore.self) private var store
    let message: Message
    let isGroup: Bool
    let showsSender: Bool
    let isLastInRun: Bool

    private var isMe: Bool { message.senderID == store.me.id }

    var body: some View {
        if message.kind == .system {
            Text(message.text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if isMe { Spacer(minLength: 60) }
                if !isMe && isGroup {
                    if isLastInRun { AvatarView(person: store.person(message.senderID), size: 28) }
                    else { Color.clear.frame(width: 28, height: 28) }
                }
                VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                    if !isMe && isGroup && showsSender {
                        Text(store.person(message.senderID)?.firstName ?? "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                    }
                    Text(message.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(isMe ? .white : .primary)
                        .background {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 20, bottomLeadingRadius: !isMe && isLastInRun ? 6 : 20,
                                bottomTrailingRadius: isMe && isLastInRun ? 6 : 20, topTrailingRadius: 20,
                                style: .continuous
                            )
                            .fill(isMe ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color(.secondarySystemBackground)))
                        }
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
                        }
                }
                if !isMe { Spacer(minLength: 60) }
            }
            .padding(.top, showsSender ? 6 : 0)
        }
    }
}

private struct TypingBubble: View {
    let person: Person?
    @State private var phase = 0.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AvatarView(person: person, size: 28)
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle()
                            .frame(width: 8, height: 8)
                            .opacity(0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.8)))
                            .offset(y: -3 * max(0, sin(t * 6 - Double(i) * 0.8)))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color(.secondarySystemBackground), in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 6)
    }
}
