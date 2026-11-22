import SwiftUI

@main
struct PartnerApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Brand.accent)
        }
    }
}

enum AppTab: Hashable {
    case discover, explore, create, chats, plans
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .top) {
            if !store.canOpenApp {
                SignInView()
                    .transition(.opacity)
            } else if store.hasOnboarded {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                OnboardingView()
                    .transition(.opacity)
            }

            if let banner = store.banner {
                BannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.smooth) { store.banner = nil } }
                    .zIndex(10)
                    .padding(.top, 4)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                store.publishScheduledPosts()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
        .task(id: store.hasOnboarded && store.auth.isSignedIn && scenePhase == .active) {
            // Pull shared events from the backend while the app is open.
            guard store.hasOnboarded, store.auth.isSignedIn, scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.syncWithServer()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .animation(.smooth(duration: 0.5), value: store.hasOnboarded)
        .animation(.smooth(duration: 0.5), value: store.canOpenApp)
        .sensoryFeedback(.success, trigger: store.banner?.id) { _, new in new != nil }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var hostTabSelected = false

    var body: some View {
        @Bindable var store = store
        // Keep the last content tab so dismissing Host returns to it.
        let selection = Binding<AppTab>(
            get: { hostTabSelected ? .create : store.selectedTab },
            set: { tab in
                if tab == .create {
                    hostTabSelected = true
                    store.showCreate = true
                } else {
                    hostTabSelected = false
                    store.selectedTab = tab
                }
            }
        )
        TabView(selection: selection) {
            Tab("Explore", systemImage: "map.fill", value: AppTab.explore) {
                ExploreView()
            }
            Tab("Discover", systemImage: "sparkles.rectangle.stack.fill", value: AppTab.discover) {
                DiscoverView()
            }
            Tab("Host", systemImage: "plus.circle.fill", value: AppTab.create) {
                Color.clear
            }
            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chats) {
                ChatsView()
            }
            .badge(store.totalUnread)
            Tab("Plans", systemImage: "calendar", value: AppTab.plans) {
                PlansView()
            }
            .badge(store.requests.count)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay {
            // First run (or a replay from Profile): show how swiping works over Discover.
            if store.showsSwipeTutorial && store.selectedTab == .discover && !store.showCreate
                && !store.showProfile && !store.showPlanner {
                SwipeTutorialView {
                    withAnimation(.smooth(duration: 0.35)) { store.finishSwipeTutorial() }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: store.showsSwipeTutorial)
        .sheet(isPresented: $store.showCreate, onDismiss: {
            hostTabSelected = false
        }) {
            CreateActivityView()
        }
        .sheet(isPresented: $store.showPlanner) { PlannerView(initialQuery: store.debugPlannerQuery) }
        .sheet(isPresented: $store.showProfile) { ProfileView() }
    }
}
