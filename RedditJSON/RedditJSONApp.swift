import SwiftUI
import CoreSpotlight

@main
struct RedditJSONApp: App {
    private let client = RedditClient()

    var body: some Scene {
        WindowGroup {
            AppRootView(client: client)
                .tint(AppTheme.tint)
        }
    }
}

private enum AppTab: Hashable {
    case browse
    case search
    case library
    case settings
}

struct AppRootView: View {
    let client: RedditClient

    @Environment(\.scenePhase) private var scenePhase
    @State private var library = LocalLibrary()
    @State private var selectedTab: AppTab = .browse
    @State private var searchRefreshID = UUID()
    @State private var deepLinkedPost: RedditPost?

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                BrowseView(client: client)
            }
            .tabItem { Label("Browse", systemImage: "rectangle.grid.1x2") }
            .tag(AppTab.browse)

            NavigationStack {
                ExploreView(client: client, refreshID: searchRefreshID)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(AppTab.search)

            NavigationStack {
                LibraryView(client: client)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppTab.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .environment(library)
        .onChange(of: selectedTab) {
            HapticFeedback.selection(enabled: library.hapticsEnabled)
        }
        .task {
            library.importPendingSharedLinks()
            handlePendingDestination()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            handlePendingDestination()
        }
        .onOpenURL(perform: openDeepLink)
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                let postID = identifier.replacingOccurrences(of: "threadline.post.", with: "")
                deepLinkedPost = library.allLocalPosts.first { $0.id == postID }
            }
        }
        .sheet(item: $deepLinkedPost) { post in
            NavigationStack {
                PostDetailView(post: post, client: client)
            }
            .environment(library)
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .search {
                    searchRefreshID = UUID()
                }
                selectedTab = newTab
            }
        )
    }

    private func openDeepLink(_ url: URL) {
        guard ["lurko", "threadline"].contains(url.scheme?.lowercased() ?? "") else { return }
        if url.host == "library" {
            selectedTab = .library
        } else if url.host == "browse" {
            selectedTab = .browse
        } else if url.host == "post", let postID = url.pathComponents.dropFirst().first {
            deepLinkedPost = library.allLocalPosts.first { $0.id == postID }
        }
    }

    private func handlePendingDestination() {
        guard UserDefaults.standard.string(forKey: "system.pending-destination.v1") == "library" else { return }
        UserDefaults.standard.removeObject(forKey: "system.pending-destination.v1")
        selectedTab = .library
    }
}
