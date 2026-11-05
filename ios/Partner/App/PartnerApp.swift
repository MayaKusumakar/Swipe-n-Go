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
    case discover, explore, plans, chats, profile
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .top) {
            if store.hasOnboarded {
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
        .animation(.smooth(duration: 0.5), value: store.hasOnboarded)
        .sensoryFeedback(.success, trigger: store.banner?.id) { _, new in new != nil }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab("Discover", systemImage: "sparkles.rectangle.stack.fill", value: AppTab.discover) {
                DiscoverView()
            }
            Tab("Explore", systemImage: "map.fill", value: AppTab.explore) {
                ExploreView()
            }
            Tab("Plans", systemImage: "calendar", value: AppTab.plans) {
                PlansView()
            }
            .badge(store.requests.count)
            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chats) {
                ChatsView()
            }
            .badge(store.totalUnread)
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
