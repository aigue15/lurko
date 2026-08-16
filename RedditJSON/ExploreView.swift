import SwiftUI

struct ExploreView: View {
    let client: RedditClient
    let refreshID: UUID

    @Environment(LocalLibrary.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var query = ""
    @State private var scope: SearchScope = .communities
    @State private var posts: [RedditPost] = []
    @State private var communities: [RedditCommunity] = []
    @State private var isSearching = false
    @State private var loadIssue: ContentLoadIssue?
    @State private var searchRetryID = UUID()
    @State private var destination: ExploreDestination?
    @State private var suggestions: [DiscoveryCommunity] = []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                discoveryContent
            } else {
                searchResults
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Discover")
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Communities and posts"
        )
        .searchScopes($scope) {
            ForEach(SearchScope.allCases) { searchScope in
                Text(searchScope.label).tag(searchScope)
            }
        }
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .community(let subreddit):
                CommunityFeedView(subreddit: subreddit, client: client)
            case .post(let post):
                PostDetailView(post: post, client: client)
            }
        }
        .task(id: "\(query)|\(scope.rawValue)|\(searchRetryID)") {
            await search()
        }
        .onChange(of: refreshID, initial: true) {
            refreshSuggestions()
        }
    }

    private var discoveryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                discoverySection(title: "Popular communities", subtitle: "A good place to start") {
                    LazyVGrid(
                        columns: discoveryColumns,
                        spacing: 12
                    ) {
                        ForEach(suggestions) { suggestion in
                            DiscoveryCommunityCard(
                                community: suggestion,
                                client: client,
                                isSubscribed: library.isSubscribed(to: suggestion.name),
                                open: { openCommunity(suggestion.name) },
                                toggleSubscription: { toggleSubscription(suggestion.name) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.title2)
                        .foregroundStyle(AppTheme.tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Browse without an account")
                            .font(.subheadline.weight(.semibold))
                        Text("Search and read public communities while subscriptions and saves remain private on your device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var searchResults: some View {
        List {
            if isSearching {
                searchPlaceholders
            } else if let loadIssue {
                LoadIssueView(issue: loadIssue) {
                    searchRetryID = UUID()
                }
                .listRowSeparator(.hidden)
            } else if scope == .communities {
                if communities.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(communities) { community in
                            CommunitySearchRow(
                                community: community,
                                isSubscribed: library.isSubscribed(to: community.displayName),
                                open: { openCommunity(community.displayName) },
                                toggleSubscription: { toggleSubscription(community.displayName) }
                            )
                            .listRowInsets(.init(top: 10, leading: 16, bottom: 10, trailing: 16))
                        }
                    } header: {
                        Text("Communities")
                    }
                }
            } else if posts.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(posts) { post in
                        Button {
                            destination = .post(post)
                        } label: {
                            PostRow(post: post)
                                .opacity(library.isRead(post) ? 0.68 : 1)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .accessibilityLabel("Open post: \(post.title)")
                    }
                } header: {
                    Text("Posts")
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var searchPlaceholders: some View {
        ForEach(0..<5, id: \.self) { _ in
            HStack(spacing: 12) {
                Circle().fill(.quaternary).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 150, height: 13)
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 11)
                }
            }
            .redacted(reason: .placeholder)
            .listRowSeparator(.hidden)
        }
    }

    private func discoverySection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            content()
        }
    }

    private func openCommunity(_ name: String) {
        HapticFeedback.impact(enabled: library.hapticsEnabled)
        destination = .community(name.redditNormalized)
    }

    private var discoveryColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func toggleSubscription(_ name: String) {
        HapticFeedback.selection(enabled: library.hapticsEnabled)
        library.toggleSubscription(name)
    }

    private func refreshSuggestions() {
        let subscribedNames = Set(library.subscriptions.map(\.redditNormalized))
        let previousNames = Set(suggestions.map { $0.name.redditNormalized })
        let refreshed = CommunityCatalog.randomPopular(
            limit: 8,
            excluding: subscribedNames.union(previousNames)
        )
        suggestions = refreshed.map {
            DiscoveryCommunity(name: $0.name, subtitle: "\($0.subscribers.compactCount) members")
        }
    }

    private func search() async {
        let term = trimmedQuery
            .replacingOccurrences(of: "r/", with: "", options: .caseInsensitive)
            .redditNormalized

        guard !term.isEmpty else {
            posts = []
            communities = []
            loadIssue = nil
            isSearching = false
            return
        }

        loadIssue = nil

        let catalogMatches = CommunityCatalog.search(term).map(\.redditCommunity)
        switch scope {
        case .communities:
            communities = catalogMatches
            posts = []
            isSearching = catalogMatches.isEmpty
        case .posts:
            posts = []
            communities = []
            isSearching = true
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        do {
            switch scope {
            case .communities:
                let liveMatches = try await client.searchCommunities(term)
                communities = mergeCommunities(catalogMatches, with: liveMatches)
                posts = []
            case .posts:
                let results = try await client.searchPosts(term)
                posts = library.filterPosts(results)
                communities = []
            }
            guard !Task.isCancelled else { return }
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if scope == .communities, !catalogMatches.isEmpty {
                communities = catalogMatches
                loadIssue = nil
            } else {
                loadIssue = ContentLoadIssue(error: error)
            }
            isSearching = false
        }
    }

    private func mergeCommunities(
        _ catalogMatches: [RedditCommunity],
        with liveMatches: [RedditCommunity]
    ) -> [RedditCommunity] {
        let liveByName = Dictionary(liveMatches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let catalogNames = Set(catalogMatches.map(\.id))
        let enrichedCatalog = catalogMatches.map { liveByName[$0.id] ?? $0 }
        return enrichedCatalog + liveMatches.filter { !catalogNames.contains($0.id) }
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case communities
    case posts

    var id: Self { self }

    var label: String {
        switch self {
        case .communities: "Communities"
        case .posts: "Posts"
        }
    }
}

private enum ExploreDestination: Hashable {
    case community(String)
    case post(RedditPost)
}

private struct DiscoveryCommunity: Identifiable {
    let name: String
    let subtitle: String

    var id: String { name }
}

private struct DiscoveryCommunityCard: View {
    let community: DiscoveryCommunity
    let client: RedditClient
    let isSubscribed: Bool
    let open: () -> Void
    let toggleSubscription: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    RedditCommunityAvatar(name: community.name, client: client, size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("r/\(community.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(community.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: toggleSubscription) {
                Label(isSubscribed ? "Joined" : "Join", systemImage: isSubscribed ? "checkmark" : "plus")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(isSubscribed ? Color.secondary : AppTheme.tint)
                    .background(
                        isSubscribed ? Color.secondary.opacity(0.09) : AppTheme.tintSoft,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSubscribed ? "Leave r/\(community.name)" : "Join r/\(community.name)")
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
    }
}

private struct CommunitySearchRow: View {
    let community: RedditCommunity
    let isSubscribed: Bool
    let open: () -> Void
    let toggleSubscription: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                CommunityRow(community: community)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: toggleSubscription) {
                Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isSubscribed ? Color.secondary : AppTheme.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSubscribed ? "Leave r/\(community.displayName)" : "Join r/\(community.displayName)")
        }
    }
}

struct CommunityRow: View {
    let community: RedditCommunity

    var body: some View {
        HStack(spacing: 12) {
            CommunityAvatar(
                name: community.displayName,
                iconURL: community.iconImg.flatMap { URL(string: $0.htmlDecoded) },
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("r/\(community.displayName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if community.over18 {
                        Text("NSFW")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                    }
                }

                Text(community.publicDescription.isEmpty ? community.title : community.publicDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let subscribers = community.subscribers {
                    Text("\(subscribers.compactCount) members")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct RedditCommunityAvatar: View {
    let name: String
    let client: RedditClient
    var size: CGFloat = 44

    @State private var iconURL: URL?

    var body: some View {
        CommunityAvatar(name: name, iconURL: iconURL, size: size)
            .task(id: name.redditNormalized) {
                guard iconURL == nil,
                      let community = try? await client.community(named: name),
                      let rawIcon = community.iconImg?.htmlDecoded,
                      !rawIcon.isEmpty else { return }
                iconURL = URL(string: rawIcon)
            }
    }
}
