import SwiftUI

enum HubFeed: String, CaseIterable, Identifiable {
    case home
    case popular
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .popular: "Popular"
        case .all: "All"
        }
    }
}

/// Feed-first root in the spirit of Apollo: open the app and you are already reading.
struct PostsHubView: View {
    let client: RedditClient

    @State private var feed: HubFeed = .home

    var body: some View {
        Group {
            switch feed {
            case .home:
                HomeFeedView(client: client, hidesNavigationChrome: true)
            case .popular:
                CombinedFeedView(
                    title: "Popular",
                    subtitle: "Trending across Reddit",
                    systemImage: "flame",
                    subreddits: ["popular"],
                    client: client,
                    presentsAsRoot: true
                )
            case .all:
                CombinedFeedView(
                    title: "All",
                    subtitle: "Posts from all public communities",
                    systemImage: "globe",
                    subreddits: ["all"],
                    client: client,
                    presentsAsRoot: true
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("Feed", selection: $feed) {
                    ForEach(HubFeed.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.contentPadding)
                .padding(.vertical, 8)
                Hairline()
            }
            .background(AppTheme.feedBackground)
        }
        .navigationTitle("Posts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    BrowseView(client: client)
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Communities")
            }
        }
    }
}

struct HomeFeedView: View {
    let client: RedditClient
    var hidesNavigationChrome = false

    @Environment(LocalLibrary.self) private var library
    @State private var sort: FeedSort = .hot
    @State private var posts: [RedditPost] = []
    @State private var communities: [String: RedditCommunity] = [:]
    @State private var selectedPost: RedditPost?
    @State private var isLoading = false
    @State private var loadIssue: ContentLoadIssue?
    @State private var appliedPreferences = false
    @State private var scrollPosition: String?

    private let feedID = "feed:home"

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading && posts.isEmpty {
                    LoadingFeedCards()
                } else if library.subscriptions.isEmpty {
                    ContentUnavailableView(
                        "Build your home feed",
                        systemImage: "plus.circle",
                        description: Text("Search for a community and join it locally. No Reddit account needed.")
                    )
                    .frame(minHeight: 420)
                    .padding(.horizontal, AppTheme.contentPadding)
                } else if let loadIssue, posts.isEmpty {
                    LoadIssueView(issue: loadIssue) {
                        Task { await load() }
                    }
                    .frame(minHeight: 420)
                    .padding(.horizontal, AppTheme.contentPadding)
                } else if posts.isEmpty {
                    ContentUnavailableView(
                        "Nothing new yet",
                        systemImage: "text.justify",
                        description: Text("Pull down to refresh your communities.")
                    )
                    .frame(minHeight: 420)
                    .padding(.horizontal, AppTheme.contentPadding)
                } else {
                    if let loadIssue {
                        CachedContentBanner(issue: loadIssue) {
                            Task { await load() }
                        }
                        .padding(.horizontal, AppTheme.contentPadding)
                        .padding(.vertical, 8)
                    }

                    ForEach(posts) { post in
                        PostCard(
                            post: post,
                            community: communities[post.subreddit.redditNormalized],
                            isNew: library.isNewSinceLastVisit(post, feedID: feedID)
                        ) {
                            open(post)
                        }
                        .id(post.id)
                    }
                }
            }
        }
        .scrollPosition(id: $scrollPosition)
        .background(AppTheme.feedBackground)
        .refreshable { await load() }
        .navigationTitle("Home", enabled: !hidesNavigationChrome)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(sort: $sort)
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(post: post, client: client)
        }
        .onAppear {
            scrollPosition = library.readingCheckpoint(for: feedID)?.anchorID
            guard !appliedPreferences else { return }
            appliedPreferences = true
            sort = library.defaultSort
        }
        .onChange(of: scrollPosition) { _, value in
            library.saveReadingCheckpoint(containerID: feedID, anchorID: value)
        }
        .onDisappear { library.markFeedVisited(feedID) }
        .task(id: taskID) { await load() }
    }

    private var taskID: String {
        "\(sort.rawValue):\(library.subscriptions.joined(separator: ",")):\(library.showNSFWContent)"
    }

    private func open(_ post: RedditPost) {
        library.recordViewed(post)
        HapticFeedback.impact(enabled: library.hapticsEnabled)
        selectedPost = post
    }

    private func load() async {
        let names = library.subscriptions
        guard !names.isEmpty else {
            posts = []
            communities = [:]
            return
        }

        isLoading = true
        loadIssue = nil
        defer { isLoading = false }

        let activeSort = sort
        let client = client
        var pages: [[RedditPost]] = []
        var issues: [ContentLoadIssue] = []

        await withTaskGroup(of: FeedFetchResult.self) { group in
            for name in names.prefix(20) {
                group.addTask {
                    do {
                        return FeedFetchResult(
                            posts: try await client.posts(subreddit: name, sort: activeSort).posts,
                            issue: nil
                        )
                    } catch {
                        return FeedFetchResult(posts: [], issue: ContentLoadIssue(error: error))
                    }
                }
            }
            for await result in group {
                if !result.posts.isEmpty { pages.append(result.posts) }
                if let issue = result.issue { issues.append(issue) }
            }
        }

        guard !Task.isCancelled else { return }
        if pages.isEmpty {
            loadIssue = ContentLoadIssue.preferred(in: issues)
            if posts.isEmpty { posts = cachedPosts(for: names) }
        } else {
            posts = library.filterPosts(mixed(pages: pages, sort: activeSort))
            library.updateRecentPostsWidget(posts)
        }

        communities = await loadCommunities(names)
    }

    private func mixed(pages: [[RedditPost]], sort: FeedSort) -> [RedditPost] {
        let unique = Dictionary(grouping: pages.flatMap { $0 }, by: \.id)
            .compactMap { $0.value.first }

        switch sort {
        case .new:
            return Array(unique.sorted { $0.createdUTC > $1.createdUTC }.prefix(120))
        case .top:
            return Array(unique.sorted { $0.score > $1.score }.prefix(120))
        default:
            var result: [RedditPost] = []
            let longest = pages.map(\.count).max() ?? 0
            for index in 0..<longest {
                for page in pages where page.indices.contains(index) {
                    let post = page[index]
                    if !result.contains(where: { $0.id == post.id }) { result.append(post) }
                }
            }
            return Array(result.prefix(120))
        }
    }

    private func loadCommunities(_ names: [String]) async -> [String: RedditCommunity] {
        let client = client
        return await withTaskGroup(of: RedditCommunity?.self, returning: [String: RedditCommunity].self) { group in
            for name in names.prefix(24) {
                group.addTask { try? await client.community(named: name) }
            }
            var result: [String: RedditCommunity] = [:]
            for await community in group {
                if let community { result[community.id] = community }
            }
            return result
        }
    }

    private func cachedPosts(for names: [String]) -> [RedditPost] {
        let subscriptions = Set(names.map(\.redditNormalized))
        return library.filterPosts(library.allLocalPosts)
            .filter { subscriptions.contains($0.subreddit.redditNormalized) }
            .sorted { $0.createdUTC > $1.createdUTC }
    }
}

struct CommunityFeedView: View {
    let subreddit: String
    let client: RedditClient

    @Environment(LocalLibrary.self) private var library
    @State private var sort: FeedSort = .hot
    @State private var posts: [RedditPost] = []
    @State private var community: RedditCommunity?
    @State private var selectedPost: RedditPost?
    @State private var after: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadIssue: ContentLoadIssue?
    @State private var appliedPreferences = false
    @State private var scrollPosition: String?

    private var normalizedName: String {
        subreddit.replacingOccurrences(of: "r/", with: "").redditNormalized
    }

    private var feedID: String { "feed:community:\(normalizedName)" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                CommunityHero(
                    name: normalizedName,
                    community: community,
                    isSubscribed: library.isSubscribed(to: normalizedName),
                    onToggleSubscription: toggleSubscription
                )
                Hairline()

                if isLoading && posts.isEmpty {
                    LoadingFeedCards()
                } else if let loadIssue, posts.isEmpty {
                    LoadIssueView(issue: loadIssue) {
                        Task { await load(reset: true) }
                    }
                    .frame(minHeight: 360)
                    .padding(.horizontal, AppTheme.contentPadding)
                } else if posts.isEmpty {
                    ContentUnavailableView("No posts", systemImage: "tray", description: Text("Try a different sort or pull to refresh."))
                        .frame(minHeight: 360)
                        .padding(.horizontal, AppTheme.contentPadding)
                } else {
                    if let loadIssue {
                        CachedContentBanner(issue: loadIssue) {
                            Task { await load(reset: true) }
                        }
                        .padding(.horizontal, AppTheme.contentPadding)
                        .padding(.vertical, 8)
                    }

                    ForEach(posts) { post in
                        PostCard(
                            post: post,
                            community: community,
                            isNew: library.isNewSinceLastVisit(post, feedID: feedID)
                        ) { open(post) }
                            .id(post.id)
                            .task {
                                if post.id == posts.last?.id { await loadMore() }
                            }
                    }

                    if isLoadingMore { ProgressView().padding(.vertical, 20) }
                }
            }
        }
        .scrollPosition(id: $scrollPosition)
        .background(AppTheme.feedBackground)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(sort: $sort)
            }
        }
        .refreshable { await load(reset: true) }
        .navigationTitle("r/\(normalizedName)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(post: post, client: client)
        }
        .onAppear {
            scrollPosition = library.readingCheckpoint(for: feedID)?.anchorID
            guard !appliedPreferences else { return }
            appliedPreferences = true
            sort = library.defaultSort
        }
        .onChange(of: scrollPosition) { _, value in
            library.saveReadingCheckpoint(containerID: feedID, anchorID: value)
        }
        .onDisappear { library.markFeedVisited(feedID) }
        .task(id: "\(normalizedName)-\(sort.rawValue)-\(library.showNSFWContent)") {
            async let feed: Void = load(reset: true)
            async let about: Void = loadCommunity()
            _ = await (feed, about)
        }
    }

    private func open(_ post: RedditPost) {
        library.recordViewed(post)
        HapticFeedback.impact(enabled: library.hapticsEnabled)
        selectedPost = post
    }

    private func toggleSubscription() {
        library.toggleSubscription(normalizedName)
        HapticFeedback.success(enabled: library.hapticsEnabled)
    }

    private func loadCommunity() async {
        community = try? await client.community(named: normalizedName)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset {
            after = nil
            loadIssue = nil
        }
        defer { isLoading = false }

        for attempt in 0..<2 {
            do {
                let page = try await client.posts(subreddit: normalizedName, sort: sort)
                guard !Task.isCancelled else { return }
                posts = library.filterPosts(page.posts)
                library.updateRecentPostsWidget(posts)
                after = page.after
                return
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled && attempt == 0 && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            } catch {
                guard !Task.isCancelled else { return }
                loadIssue = ContentLoadIssue(error: error)
                if posts.isEmpty {
                    posts = library.filterPosts(library.allLocalPosts)
                        .filter { $0.subreddit.redditNormalized == normalizedName }
                        .sorted { $0.createdUTC > $1.createdUTC }
                }
                return
            }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, let cursor = after else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.posts(subreddit: normalizedName, sort: sort, after: cursor)
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: library.filterPosts(page.posts).filter { !known.contains($0.id) })
            after = page.after
        } catch is CancellationError {
            return
        } catch {
            loadIssue = ContentLoadIssue(error: error)
        }
    }
}

private struct FeedFetchResult: Sendable {
    let posts: [RedditPost]
    let issue: ContentLoadIssue?
}

private struct CommunityHero: View {
    let name: String
    let community: RedditCommunity?
    let isSubscribed: Bool
    let onToggleSubscription: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CommunityAvatar(
                name: name,
                iconURL: URL(string: community?.iconImg?.htmlDecoded ?? ""),
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("r/\(name)")
                    .font(.headline)
                if let members = community?.subscribers {
                    Text("\(members.compactCount) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button(isSubscribed ? "Joined" : "Join", action: onToggleSubscription)
                .buttonStyle(CapsuleActionStyle(prominent: !isSubscribed))
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 12)
        .background(AppTheme.feedBackground)
    }
}

struct PostCard: View {
    let post: RedditPost
    var community: RedditCommunity?
    var isNew = false
    let onOpen: () -> Void

    @Environment(LocalLibrary.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var showLibraryEditor = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                cardContent
                    .padding(.horizontal, AppTheme.contentPadding)
                    .padding(.top, library.feedLayout == .compact ? 10 : 12)
                    .padding(.bottom, library.feedLayout == .compact ? 8 : 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            postFooter
            Hairline().padding(.leading, library.feedLayout == .compact ? 46 : AppTheme.contentPadding)
        }
        .background(AppTheme.feedBackground)
        .opacity(library.isRead(post) ? 0.78 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > 82, abs(horizontal) > vertical * 1.4 else { return }
                if horizontal > 0 {
                    library.save(post)
                    HapticFeedback.success(enabled: library.hapticsEnabled)
                } else {
                    library.hide(post)
                    HapticFeedback.impact(enabled: library.hapticsEnabled)
                }
            }
        )
        .contextMenu {
            Button {
                library.toggleSaved(post)
            } label: {
                Label(library.isSaved(post) ? "Remove Save" : "Save", systemImage: library.isSaved(post) ? "bookmark.slash" : "bookmark")
            }

            Button {
                if library.isRead(post) { library.markUnread(post) }
                else { library.markRead(post) }
            } label: {
                Label(library.isRead(post) ? "Mark Unread" : "Mark Read", systemImage: library.isRead(post) ? "circle" : "checkmark.circle")
            }

            Button {
                library.toggleReadingQueue(post)
            } label: {
                Label(
                    library.isQueued(post) ? "Remove from Queue" : "Add to Queue",
                    systemImage: "text.badge.plus"
                )
            }

            Button {
                library.toggleFavorite(post)
            } label: {
                Label(
                    library.isFavorite(post) ? "Remove Favorite" : "Favorite",
                    systemImage: library.isFavorite(post) ? "star.slash" : "star"
                )
            }

            Button {
                showLibraryEditor = true
            } label: {
                Label("Notes, Tags & Collections", systemImage: "tag")
            }

            Menu("Mute or Filter") {
                Button("Mute u/\(post.author)") { library.muteAuthor(post.author) }
                Button("Mute r/\(post.subreddit)") { library.muteSubreddit(post.subreddit) }
                if !post.domain.isEmpty {
                    Button("Mute \(post.domain)") { library.muteDomain(post.domain) }
                }
                Button("Hide this post", role: .destructive) { library.hide(post) }
            }

            Button(action: openExternally) {
                Label("Open in \(library.redditInterface.title)", systemImage: "arrow.up.forward.app")
            }
        }
        .sheet(isPresented: $showLibraryEditor) {
            PostLibraryEditorView(post: post)
        }
        .accessibilityAction(named: "Save locally") { library.save(post) }
        .accessibilityAction(named: "Hide post") { library.hide(post) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch library.feedLayout {
        case .compact:
            HStack(alignment: .top, spacing: 8) {
                VoteColumn(score: post.score)
                VStack(alignment: .leading, spacing: 5) {
                    compactPostHeader
                    Text(post.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(hasPreviewMedia ? 4 : 3)

                    if !hasPreviewMedia, !post.selftext.isEmpty {
                        Text(post.selftext)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasPreviewMedia {
                    PostPreviewMedia(post: post, height: AppTheme.thumbnailSize, compact: true)
                        .frame(width: AppTheme.thumbnailSize)
                }
            }
        case .comfortable:
            HStack(alignment: .top, spacing: 10) {
                VoteColumn(score: post.score)
                VStack(alignment: .leading, spacing: 8) {
                    postHeader
                    titleAndExcerpt
                    if hasPreviewMedia {
                        PostPreviewMedia(post: post, height: 180)
                    } else if post.selftext.isEmpty {
                        linkPreview
                    }
                }
            }
        case .media:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VoteColumn(score: post.score)
                    VStack(alignment: .leading, spacing: 6) {
                        postHeader
                        Text(post.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                    }
                }
                if hasPreviewMedia {
                    PostPreviewMedia(post: post, height: 240, fitsMedia: true)
                } else if !post.selftext.isEmpty {
                    Text(post.selftext)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .padding(.leading, AppTheme.voteColumnWidth + 10)
                } else {
                    linkPreview
                        .padding(.leading, AppTheme.voteColumnWidth + 10)
                }
            }
        }
    }

    @ViewBuilder
    private var postFooter: some View {
        HStack(spacing: 16) {
            CountLabel(value: post.numComments, systemImage: "bubble.left", accessibilityText: post.numComments.commentLabel)
            if !post.domain.isEmpty, post.domain != "self.\(post.subreddit)" {
                Text(post.domain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                library.toggleSaved(post)
                HapticFeedback.success(enabled: library.hapticsEnabled)
            } label: {
                Image(systemName: library.isSaved(post) ? "bookmark.fill" : "bookmark")
                    .font(.subheadline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(library.isSaved(post) ? AppTheme.tint : Color.secondary)
            .accessibilityLabel(library.isSaved(post) ? "Remove local save" : "Save post locally")

            if let url = post.redditURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Share post")
            }
        }
        .padding(.leading, library.feedLayout == .compact ? 46 : AppTheme.contentPadding)
        .padding(.trailing, 6)
        .padding(.bottom, 4)
    }

    private var hasPreviewMedia: Bool {
        post.imageURL != nil
            || post.videoURL != nil
            || (!post.galleryMedia.isEmpty)
            || (post.hasSupportedExternalMedia && post.thumbnailURL != nil)
    }

    private var compactPostHeader: some View {
        HStack(spacing: 4) {
            Text("r/\(post.subreddit)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("·")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(post.createdUTC.relativeRedditTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if post.over18 {
                Text("NSFW").font(.caption2.weight(.semibold)).foregroundStyle(.red)
            } else if post.spoiler {
                Text("SPOILER").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            } else if isNew {
                Text("NEW").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.tint)
            }
        }
    }

    private var postHeader: some View {
        HStack(spacing: 6) {
            CommunityAvatar(
                name: post.subreddit,
                iconURL: URL(string: community?.iconImg?.htmlDecoded ?? ""),
                size: 22
            )
            Text("r/\(post.subreddit)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("u/\(post.author)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text("· \(post.createdUTC.relativeRedditTime)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if post.over18 {
                Text("NSFW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            } else if post.spoiler {
                Text("SPOILER")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if isNew {
                Text("NEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.tint)
            }
        }
    }

    private var titleAndExcerpt: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(post.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if !post.selftext.isEmpty, library.feedLayout != .media {
                Text(post.selftext)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var linkPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
            Text(post.domain).lineLimit(1)
            Spacer()
            Image(systemName: "arrow.up.right")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openExternally() {
        guard let webURL = post.redditURL,
              let destination = library.redditInterface.destinationURL(for: post) else { return }
        if library.redditInterface == .browser {
            openURL(webURL)
        } else {
            openURL(destination) { accepted in
                if !accepted { openURL(webURL) }
            }
        }
    }
}

private struct PostPreviewMedia: View {
    let post: RedditPost
    let height: CGFloat
    var compact = false
    var fitsMedia = false

    @Environment(LocalLibrary.self) private var library

    var body: some View {
        ZStack {
            if let imageURL = previewImageURL {
                AsyncImage(url: imageURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        if fitsMedia {
                            image.resizable().scaledToFit()
                        } else {
                            image.resizable().scaledToFill()
                        }
                    case .failure:
                        mediaPlaceholder(icon: "photo.badge.exclamationmark")
                    default:
                        mediaPlaceholder(icon: "photo")
                            .redacted(reason: .placeholder)
                    }
                }
            } else {
                mediaPlaceholder(icon: post.videoURL == nil ? "link" : "play.rectangle.fill")
            }

            if post.videoURL != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: compact ? 30 : 50))
                    .foregroundStyle(.white)
                    .shadow(radius: 5)
            }

            if post.galleryMedia.count > 1 {
                Label(post.galleryMedia.count.compactCount, systemImage: "rectangle.stack.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.62), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(9)
                    .accessibilityLabel("Gallery with \(post.galleryMedia.count) items")
            }

            if library.shouldBlurMedia(for: post) {
                Rectangle().fill(.ultraThinMaterial)
                Label(post.over18 ? "Sensitive" : "Spoiler", systemImage: "eye.slash.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .background(
            fitsMedia
                ? Color(uiColor: .secondarySystemGroupedBackground)
                : Color(uiColor: .quaternarySystemFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous))
    }

    private var previewImageURL: URL? {
        post.imageURL ?? ((post.videoURL != nil || post.hasSupportedExternalMedia) ? post.thumbnailURL : nil)
    }

    private func mediaPlaceholder(icon: String) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemFill)
            Image(systemName: icon)
                .font(compact ? .title3 : .title)
                .foregroundStyle(.secondary)
        }
    }
}

struct SortMenu: View {
    @Binding var sort: FeedSort

    var body: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(FeedSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Label(sort.label, systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("sort-menu")
    }
}

/// Dense, action-free row used when a parent owns navigation (search and library).
struct PostRow: View {
    let post: RedditPost
    @Environment(LocalLibrary.self) private var library

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VoteColumn(score: post.score)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text("r/\(post.subreddit)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("· \(post.createdUTC.relativeRedditTime)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if library.isSaved(post) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.tint)
                    }
                }

                Text(post.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                CountLabel(value: post.numComments, systemImage: "bubble.left", accessibilityText: post.numComments.commentLabel)
            }

            if let imageURL = post.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: AppTheme.thumbnailSize, height: AppTheme.thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    if library.shouldBlurMedia(for: post) {
                        RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial)
                        Image(systemName: "eye.slash.fill").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct LoadingFeedCards: View {
    var body: some View {
        ForEach(0..<6, id: \.self) { _ in
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 22, height: 44)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 120, height: 10)
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 14)
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 180, height: 14)
                }
                RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: AppTheme.thumbnailSize, height: AppTheme.thumbnailSize)
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.vertical, 12)
            .redacted(reason: .placeholder)
        }
    }
}

// Kept for compatibility with older call sites and previews.
typealias LoadingRows = LoadingFeedCards
