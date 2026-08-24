import AVKit
import Photos
import SafariServices
import SwiftUI
import WebKit

struct PostDetailView: View {
    let post: RedditPost
    let client: RedditClient

    @Environment(LocalLibrary.self) private var library
    @Environment(\.openURL) private var openURL

    @State private var comments: [RedditComment] = []
    @State private var commentSort: CommentSort = .best
    @State private var isLoadingComments = true
    @State private var commentsIssue: ContentLoadIssue?
    @State private var presentedURL: PresentedURL?
    @State private var engagementScore: Int?
    @State private var engagementCommentCount: Int?
    @State private var community: RedditCommunity?
    @State private var commentSearchText = ""
    @State private var topCommentIndex = 0
    @State private var commentSearchIndex = 0
    @State private var focusedCommentID: String?
    @State private var detailScrollPosition: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    postSurface
                        .id("post")
                    Hairline()
                    commentsSurface(proxy: proxy)
                        .id("comments")
                }
            }
            .background(AppTheme.feedBackground)
            .coordinateSpace(name: CommentScrollCoordinateSpace.name)
            .scrollPosition(id: $detailScrollPosition)
            .onPreferenceChange(CommentPositionPreferenceKey.self) { positions in
                updateFocusedComment(from: positions)
            }
            .safeAreaPadding(.bottom, 66)
            .overlay(alignment: .bottomTrailing) {
                if !activeCommentNodes.isEmpty {
                    commentNavigationButton(proxy: proxy)
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .onAppear {
            detailScrollPosition = library.readingCheckpoint(for: "post:\(post.id)")?.anchorID
        }
        .onChange(of: detailScrollPosition) { _, value in
            library.saveReadingCheckpoint(containerID: "post:\(post.id)", anchorID: value)
        }
        .onChange(of: commentSearchText) {
            commentSearchIndex = 0
            focusedCommentID = nil
        }
        .sheet(item: $presentedURL) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        .task {
            library.recordViewed(post)
            async let commentsTask: Void = loadComments()
            async let engagementTask: Void = loadEngagement()
            async let communityTask: Void = loadCommunity()
            _ = await (commentsTask, engagementTask, communityTask)
        }
    }

    private var postSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CommunityFeedView(subreddit: post.subreddit, client: client)
            } label: {
                HStack(spacing: 8) {
                    CommunityAvatar(name: post.subreddit, iconURL: community?.iconURL, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("r/\(post.subreddit)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("u/\(post.author) · \(post.createdUTC.relativeRedditTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if post.stickied || post.locked || post.linkFlairText != nil {
                HStack(spacing: 8) {
                    if post.stickied { statusPill("Pinned", icon: "pin.fill") }
                    if post.locked { statusPill("Locked", icon: "lock.fill") }
                    if let flair = post.linkFlairText, !flair.isEmpty { statusPill(flair, icon: nil) }
                }
            }

            Text(post.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)

            PostMediaView(post: post)

            if !post.selftext.isEmpty {
                MarkdownBody(text: post.selftext)
            }

            if post.imageURL == nil, post.videoURL == nil, let url = post.externalURL {
                Button {
                    presentedURL = PresentedURL(url: url)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "safari")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open link")
                                .font(.subheadline.weight(.semibold))
                            Text(post.domain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.primary)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                VoteColumn(score: displayedScore)
                CountLabel(value: displayedCommentCount, systemImage: "bubble.left", accessibilityText: displayedCommentCount.commentLabel)
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    library.toggleSaved(post)
                    HapticFeedback.success(enabled: library.hapticsEnabled)
                } label: {
                    Label(library.isSaved(post) ? "Saved" : "Save", systemImage: library.isSaved(post) ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .buttonStyle(PostUtilityActionStyle(isActive: library.isSaved(post)))
                .accessibilityLabel(library.isSaved(post) ? "Remove local save" : "Save post locally")

                if let url = post.redditURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                    }
                    .buttonStyle(PostUtilityActionStyle())
                }

                Button(action: openPostExternally) {
                    Label("Open", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .buttonStyle(PostUtilityActionStyle())
                .accessibilityLabel("Open post in \(library.redditInterface.title)")
            }
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 14)
    }

    private func commentsSurface(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayedCommentCount.commentLabel)
                        .font(.headline)
                    if loadedCommentCount > 0, loadedCommentCount < displayedCommentCount {
                        Text("Showing \(loadedCommentCount.compactCount) available replies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Picker("Comment sort", selection: $commentSort) {
                        ForEach(CommentSort.allCases) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                } label: {
                    Label(commentSort.title, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                }
            }

            HStack(spacing: 8) {
                TextField("Search comments", text: $commentSearchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { jumpSearchResult(direction: 0, proxy: proxy) }

                if !normalizedCommentQuery.isEmpty {
                    Text(commentMatchSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !normalizedCommentQuery.isEmpty {
                HStack(spacing: 8) {
                    Label(
                        "\(matchingCommentNodes.count.compactCount) matching comments",
                        systemImage: "text.magnifyingglass"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        jumpSearchResult(direction: -1, proxy: proxy)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(matchingCommentNodes.isEmpty)
                    .accessibilityLabel("Previous comment search result")

                    Text(commentMatchSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34)

                    Button {
                        jumpSearchResult(direction: 1, proxy: proxy)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(matchingCommentNodes.isEmpty)
                    .accessibilityLabel("Next comment search result")
                }
            }

            if let commentsIssue, !comments.isEmpty || !library.offlineComments(for: post.id).isEmpty {
                CachedContentBanner(issue: commentsIssue) {
                    Task { await loadComments() }
                }
            }

            if isLoadingComments && comments.isEmpty && library.offlineComments(for: post.id).isEmpty {
                CommentPlaceholders()
            } else if let commentsIssue, comments.isEmpty, library.offlineComments(for: post.id).isEmpty {
                LoadIssueView(issue: commentsIssue) {
                    Task { await loadComments() }
                }
                .frame(minHeight: 220)
            } else if comments.isEmpty, !library.offlineComments(for: post.id).isEmpty {
                Label("Offline comments", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if visibleOfflineTopComments.isEmpty {
                    ContentUnavailableView("No matching comments", systemImage: "text.magnifyingglass")
                        .frame(minHeight: 160)
                } else {
                    ForEach(visibleOfflineTopComments) { comment in
                        OfflineCommentThreadView(comment: comment, depth: 0)
                    }
                }
            } else if comments.isEmpty {
                ContentUnavailableView("No comments yet", systemImage: "bubble.left")
                    .frame(minHeight: 180)
            } else {
                ForEach(visibleTopComments) { comment in
                    CommentThreadView(
                        comment: comment,
                        depth: 0,
                        sensitiveMedia: post.over18,
                        postAuthor: post.author,
                        searchQuery: normalizedCommentQuery
                    )
                    if comment.id != visibleTopComments.last?.id { Divider() }
                }

                if loadedCommentCount < displayedCommentCount {
                    Button(action: openPostExternally) {
                        Label("Continue in \(library.redditInterface.title)", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 14)
    }

    private func commentNavigationButton(proxy: ScrollViewProxy) -> some View {
        Button {
            if focusedCommentParentID != nil {
                jumpToParent(proxy: proxy)
            } else {
                jumpToNextThread(proxy: proxy)
            }
        } label: {
            Image(systemName: focusedCommentParentID == nil ? "arrow.down.to.line" : "arrow.turn.up.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(AppTheme.tint, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(activeTopCommentIDs.isEmpty)
        .accessibilityLabel(focusedCommentParentID == nil ? "Next comment thread" : "Go to parent comment")
        .accessibilityHint("The button changes to the next available comment navigation action")
        .animation(.snappy, value: focusedCommentParentID == nil)
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    library.toggleSaved(post)
                } label: {
                    Label(library.isSaved(post) ? "Remove Save" : "Save Post", systemImage: library.isSaved(post) ? "bookmark.slash" : "bookmark")
                }

                if let url = post.redditURL {
                    ShareLink(item: url) {
                        Label("Share Post", systemImage: "square.and.arrow.up")
                    }
                }

                Button(action: openPostExternally) {
                    Label("Open in \(library.redditInterface.title)", systemImage: "arrow.up.forward.app")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var sortedComments: [RedditComment] {
        switch commentSort {
        case .best: comments.sorted { $0.score > $1.score }
        case .new: comments.sorted { $0.createdUTC > $1.createdUTC }
        case .old: comments.sorted { $0.createdUTC < $1.createdUTC }
        }
    }

    private var visibleTopComments: [RedditComment] {
        guard !normalizedCommentQuery.isEmpty else { return sortedComments }
        return sortedComments.filter { commentMatches($0, query: normalizedCommentQuery) }
    }

    private func commentMatches(_ comment: RedditComment, query: String) -> Bool {
        LocalContentFilters.normalized("\(comment.author) \(comment.displayBody)").contains(query)
            || comment.replies.contains { commentMatches($0, query: query) }
    }

    private var visibleOfflineTopComments: [OfflineComment] {
        let comments = library.offlineComments(for: post.id)
        guard !normalizedCommentQuery.isEmpty else { return comments }
        return comments.filter { offlineCommentMatches($0, query: normalizedCommentQuery) }
    }

    private func offlineCommentMatches(_ comment: OfflineComment, query: String) -> Bool {
        LocalContentFilters.normalized("\(comment.author) \(comment.body)").contains(query)
            || comment.replies.contains { offlineCommentMatches($0, query: query) }
    }

    private var normalizedCommentQuery: String {
        LocalContentFilters.normalized(commentSearchText)
    }

    private var activeCommentNodes: [CommentNavigationNode] {
        if comments.isEmpty {
            return commentNavigationNodes(for: library.offlineComments(for: post.id))
        }
        return commentNavigationNodes(for: sortedComments)
    }

    private var matchingCommentNodes: [CommentNavigationNode] {
        guard !normalizedCommentQuery.isEmpty else { return [] }
        return activeCommentNodes.filter { $0.searchText.contains(normalizedCommentQuery) }
    }

    private var activeTopCommentIDs: [String] {
        comments.isEmpty ? visibleOfflineTopComments.map(\.id) : visibleTopComments.map(\.id)
    }

    private var focusedCommentParentID: String? {
        guard let focusedCommentID else { return nil }
        return activeCommentNodes.first { $0.id == focusedCommentID }?.parentID
    }

    private var commentMatchSummary: String {
        guard !matchingCommentNodes.isEmpty else { return "0/0" }
        let current = min(commentSearchIndex, matchingCommentNodes.count - 1) + 1
        return "\(current)/\(matchingCommentNodes.count)"
    }

    private func jumpSearchResult(direction: Int, proxy: ScrollViewProxy) {
        guard !matchingCommentNodes.isEmpty else { return }
        if direction == 0 {
            commentSearchIndex = min(commentSearchIndex, matchingCommentNodes.count - 1)
        } else {
            commentSearchIndex = (commentSearchIndex + direction + matchingCommentNodes.count) % matchingCommentNodes.count
        }
        jump(to: matchingCommentNodes[commentSearchIndex], proxy: proxy)
    }

    private func jumpToParent(proxy: ScrollViewProxy) {
        guard let parentID = focusedCommentParentID,
              let parent = activeCommentNodes.first(where: { $0.id == parentID }) else { return }
        jump(to: parent, proxy: proxy)
    }

    private func jumpToNextThread(proxy: ScrollViewProxy) {
        guard !activeTopCommentIDs.isEmpty else { return }
        if let focusedCommentID,
           let rootID = activeCommentNodes.first(where: { $0.id == focusedCommentID })?.rootID,
           let current = activeTopCommentIDs.firstIndex(of: rootID) {
            topCommentIndex = (current + 1) % activeTopCommentIDs.count
        } else {
            topCommentIndex = min(topCommentIndex, activeTopCommentIDs.count - 1)
        }
        guard let node = activeCommentNodes.first(where: { $0.id == activeTopCommentIDs[topCommentIndex] }) else { return }
        jump(to: node, proxy: proxy)
    }

    private func jump(to node: CommentNavigationNode, proxy: ScrollViewProxy) {
        for ancestorID in node.ancestorIDs where library.isCommentCollapsed(ancestorID) {
            library.toggleCommentCollapsed(ancestorID)
        }
        focusedCommentID = node.id
        withAnimation(.snappy) {
            proxy.scrollTo(comments.isEmpty ? "offline-comment-\(node.id)" : "comment-\(node.id)", anchor: .top)
        }
    }

    private func updateFocusedComment(from positions: [String: CGFloat]) {
        guard let nearestCommentID = positions.min(by: {
            abs($0.value - AppTheme.contentPadding) < abs($1.value - AppTheme.contentPadding)
        })?.key else { return }
        focusedCommentID = nearestCommentID
    }

    private func commentNavigationNodes(for roots: [RedditComment]) -> [CommentNavigationNode] {
        var result: [CommentNavigationNode] = []

        func append(_ comment: RedditComment, parentID: String?, rootID: String, ancestors: [String]) {
            result.append(
                CommentNavigationNode(
                    id: comment.id,
                    parentID: parentID,
                    rootID: rootID,
                    ancestorIDs: ancestors,
                    searchText: LocalContentFilters.normalized("\(comment.author) \(comment.displayBody)")
                )
            )
            for reply in comment.replies {
                append(reply, parentID: comment.id, rootID: rootID, ancestors: ancestors + [comment.id])
            }
        }

        for root in roots {
            append(root, parentID: nil, rootID: root.id, ancestors: [])
        }
        return result
    }

    private func commentNavigationNodes(for roots: [OfflineComment]) -> [CommentNavigationNode] {
        var result: [CommentNavigationNode] = []

        func append(_ comment: OfflineComment, parentID: String?, rootID: String, ancestors: [String]) {
            result.append(
                CommentNavigationNode(
                    id: comment.id,
                    parentID: parentID,
                    rootID: rootID,
                    ancestorIDs: ancestors,
                    searchText: LocalContentFilters.normalized("\(comment.author) \(comment.body)")
                )
            )
            for reply in comment.replies {
                append(reply, parentID: comment.id, rootID: rootID, ancestors: ancestors + [comment.id])
            }
        }

        for root in roots {
            append(root, parentID: nil, rootID: root.id, ancestors: [])
        }
        return result
    }

    private var displayedScore: Int { engagementScore ?? post.score }

    private var displayedCommentCount: Int {
        max(engagementCommentCount ?? post.numComments, loadedCommentCount)
    }

    private var loadedCommentCount: Int {
        func count(_ comment: RedditComment) -> Int {
            1 + comment.replies.reduce(0) { $0 + count($1) }
        }
        return comments.reduce(0) { $0 + count($1) }
    }

    private func statusPill(_ text: String, icon: String?) -> some View {
        Group {
            if let icon { Label(text, systemImage: icon) }
            else { Text(text) }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }

    private func loadComments() async {
        isLoadingComments = true
        commentsIssue = nil
        defer { isLoadingComments = false }
        do {
            comments = try await client.comments(postID: post.id, subreddit: post.subreddit)
            library.archiveComments(comments, for: post)
        } catch is CancellationError {
            return
        } catch {
            commentsIssue = ContentLoadIssue(error: error)
        }
    }

    private func loadEngagement() async {
        guard let engagement = try? await client.engagement(for: post) else { return }
        engagementScore = engagement.score
        engagementCommentCount = engagement.commentCount
        var updated = post
        updated.score = engagement.score
        updated.numComments = engagement.commentCount
        library.updateStoredPost(updated)
    }

    private func loadCommunity() async {
        community = try? await client.community(named: post.subreddit)
    }

    private func openPostExternally() {
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

enum CommentSort: String, CaseIterable, Identifiable {
    case best
    case new
    case old

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .best: "sparkles"
        case .new: "clock"
        case .old: "clock.arrow.circlepath"
        }
    }
}

struct PostMediaView: View {
    let post: RedditPost

    @Environment(LocalLibrary.self) private var library
    @State private var revealSensitive = false
    @State private var selectedMedia: MediaSelection?
    @State private var galleryIndex = 0

    var body: some View {
        Group {
            if !post.galleryMedia.isEmpty {
                gallery(post.galleryMedia)
            } else if let externalURL = post.externalURL, post.hasSupportedExternalMedia {
                ResolvedExternalMediaView(
                    sourceURL: externalURL,
                    previewURL: post.imageURL,
                    autoplay: library.autoplayVideos && !library.shouldBlurMedia(for: post),
                    presentation: .post
                )
            } else if let videoURL = post.videoURL {
                InlineVideoView(
                    url: videoURL,
                    autoplay: library.shouldAutoplay(post),
                    muted: library.muteVideosByDefault
                )
            } else if let imageURL = post.imageURL {
                image(imageURL)
            }
        }
        .overlay {
            if library.shouldBlurMedia(for: post), !revealSensitive {
                Button {
                    revealSensitive = true
                    HapticFeedback.impact(enabled: library.hapticsEnabled)
                } label: {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill").font(.title2)
                            Text(post.over18 ? "Sensitive content" : "Spoiler")
                                .font(.subheadline.bold())
                            Text("Tap to reveal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .fullScreenCover(item: $selectedMedia) { media in
            FullScreenMediaView(selection: media)
        }
    }

    private func gallery(_ items: [RedditGalleryMedia]) -> some View {
        VStack(spacing: 0) {
            TabView(selection: $galleryIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    galleryItem(item, allItems: items)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 420)
            .background(.black.opacity(0.04))

            if items.indices.contains(galleryIndex) {
                let item = items[galleryIndex]
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(galleryIndex + 1) of \(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let caption = item.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }

                    Spacer(minLength: 0)

                    if let outboundURL = item.outboundURL {
                        Link(destination: outboundURL) {
                            Image(systemName: "arrow.up.right")
                        }
                        .accessibilityLabel("Open gallery item link")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }

    @ViewBuilder
    private func galleryItem(_ item: RedditGalleryMedia, allItems: [RedditGalleryMedia]) -> some View {
        switch item.kind {
        case .image:
            Button {
                presentGalleryImage(item, allItems: allItems)
            } label: {
                remoteImage(item.url, contentMode: .fit)
            }
            .buttonStyle(.plain)
        case .animatedImage:
            AnimatedRemoteImage(url: item.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.04))
                .overlay {
                    Button {
                        presentGalleryImage(item, allItems: allItems)
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open animated gallery image full screen")
                }
        case .video:
            InlineVideoView(
                url: item.url,
                autoplay: false,
                muted: library.muteVideosByDefault
            )
        }
    }

    private func presentGalleryImage(_ item: RedditGalleryMedia, allItems: [RedditGalleryMedia]) {
        let imageURLs = allItems.compactMap { media -> URL? in
            media.kind == .video ? nil : media.url
        }
        guard let selectedIndex = imageURLs.firstIndex(of: item.url) else { return }
        selectedMedia = MediaSelection(urls: imageURLs, selectedIndex: selectedIndex)
    }

    private func image(_ url: URL) -> some View {
        Button {
            selectedMedia = MediaSelection(urls: [url], selectedIndex: 0)
        } label: {
            remoteImage(url, contentMode: .fit)
                .frame(minHeight: 190, maxHeight: 480)
        }
        .buttonStyle(.plain)
    }

    private func remoteImage(_ url: URL, contentMode: ContentMode) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else if phase.error != nil {
                ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
            } else {
                ZStack { Rectangle().fill(.quaternary); ProgressView() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct InlineVideoView: View {
    let url: URL
    let autoplay: Bool
    let loops: Bool
    let muted: Bool
    @State private var player: AVPlayer?
    @State private var isMuted: Bool
    @State private var playbackError: String?
    @State private var retryID = UUID()

    init(url: URL, autoplay: Bool, loops: Bool = false, muted: Bool = true) {
        self.url = url
        self.autoplay = autoplay
        self.loops = loops
        self.muted = muted
        _isMuted = State(initialValue: muted)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black

            if let player {
                VideoPlayer(player: player)
            } else if let playbackError {
                ContentUnavailableView {
                    Label("Video unavailable", systemImage: "play.slash")
                } description: {
                    Text(playbackError)
                } actions: {
                    HStack {
                        Button("Try Again") { retryID = UUID() }
                        Link("Open Video", destination: url)
                    }
                    .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
            } else {
                ProgressView("Loading video")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if let player {
                Button {
                    isMuted.toggle()
                    player.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.58), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel(isMuted ? "Unmute video" : "Mute video")
            }
        }
            .frame(minHeight: 260, idealHeight: 360, maxHeight: 480)
            .background(.black)
            .task(id: retryID) { await preparePlayer() }
            .onChange(of: muted) { _, value in
                isMuted = value
                player?.isMuted = value
            }
            .onDisappear { player?.pause() }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
                guard let player, loops, notification.object as? AVPlayerItem === player.currentItem else { return }
                player.seek(to: .zero)
                player.play()
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
                guard let player, notification.object as? AVPlayerItem === player.currentItem else { return }
                player.pause()
                self.player = nil
                playbackError = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                    ?? "The video stream could not be played."
            }
            .accessibilityLabel("Video player")
    }

    private func preparePlayer() async {
        player?.pause()
        player = nil
        playbackError = nil

        do {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            guard playable else { throw URLError(.cannotDecodeContentData) }
            guard !Task.isCancelled else { return }

            let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            newPlayer.isMuted = isMuted
            player = newPlayer
            if autoplay { newPlayer.play() }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            playbackError = error.localizedDescription
        }
    }
}

private enum ExternalMediaPresentation {
    case post
    case comment

    var minimumHeight: CGFloat { self == .post ? 220 : 170 }
    var preferredHeight: CGFloat { self == .post ? 360 : 230 }
    var maximumHeight: CGFloat { self == .post ? 480 : 320 }
}

/// Resolves provider pages off the main actor and always retains an actionable
/// original-link fallback. Direct media does not wait for the resolver.
private struct ResolvedExternalMediaView: View {
    let sourceURL: URL
    let previewURL: URL?
    let autoplay: Bool
    let presentation: ExternalMediaPresentation

    @Environment(LocalLibrary.self) private var library

    @State private var resolvedResource: ExternalMediaResource?
    @State private var didFinishResolution = false
    @State private var selectedMedia: MediaSelection?
    @State private var presentedURL: PresentedURL?

    private var resource: ExternalMediaResource? {
        ExternalMediaClassifier.immediateResource(for: sourceURL) ?? resolvedResource
    }

    private var providerTitle: String {
        ExternalMediaClassifier.provider(for: sourceURL)?.title
            ?? sourceURL.host?.replacingOccurrences(of: "www.", with: "")
            ?? "source"
    }

    var body: some View {
        Group {
            if let resource {
                media(resource)
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .task(id: sourceURL) {
            guard ExternalMediaClassifier.immediateResource(for: sourceURL) == nil else {
                didFinishResolution = true
                return
            }
            resolvedResource = await ExternalMediaResolver.shared.resolve(sourceURL)
            guard !Task.isCancelled else { return }
            didFinishResolution = true
        }
        .fullScreenCover(item: $selectedMedia) { selection in
            FullScreenMediaView(selection: selection)
        }
        .sheet(item: $presentedURL) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func media(_ resource: ExternalMediaResource) -> some View {
        switch resource.kind {
        case .image:
            Button {
                selectedMedia = MediaSelection(urls: [resource.mediaURL], selectedIndex: 0)
            } label: {
                AsyncImage(url: resource.mediaURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        unavailable(resource)
                    } else {
                        mediaLoadingPlaceholder
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: presentation.minimumHeight,
                    idealHeight: presentation.preferredHeight,
                    maxHeight: presentation.maximumHeight
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open image from \(resource.provider.title) full screen")

        case .animatedImage:
            AnimatedRemoteImage(url: resource.mediaURL)
                .frame(maxWidth: .infinity)
                .frame(height: presentation.preferredHeight)
                .background(.black.opacity(0.04))
                .overlay {
                    Button {
                        selectedMedia = MediaSelection(urls: [resource.mediaURL], selectedIndex: 0)
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open animated image from \(resource.provider.title) full screen")
                }

        case .video:
            ZStack(alignment: .topTrailing) {
                InlineVideoView(
                    url: resource.mediaURL,
                    autoplay: autoplay,
                    loops: resource.loops,
                    muted: library.muteVideosByDefault
                )
                providerButton(resource)
                    .padding(10)
            }

        case .embed:
            ProviderEmbedCard(
                resource: resource,
                previewURL: previewURL,
                autoplay: autoplay,
                height: presentation.preferredHeight,
                openOriginal: { presentedURL = PresentedURL(url: resource.originalURL) }
            )
        }
    }

    private var fallback: some View {
        ZStack(alignment: .bottomTrailing) {
            if let previewURL {
                Button {
                    selectedMedia = MediaSelection(urls: [previewURL], selectedIndex: 0)
                } label: {
                    AsyncImage(url: previewURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            mediaLoadingPlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(
                        minHeight: presentation.minimumHeight,
                        idealHeight: presentation.preferredHeight,
                        maxHeight: presentation.maximumHeight
                    )
                }
                .buttonStyle(.plain)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [AppTheme.tint.opacity(0.18), Color(uiColor: .secondarySystemGroupedBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 38))
                        .foregroundStyle(AppTheme.tint)
                }
                .frame(maxWidth: .infinity)
                .frame(height: presentation.minimumHeight)
            }

            if !didFinishResolution {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .accessibilityLabel("Loading media")
            }

            Button {
                presentedURL = PresentedURL(url: sourceURL)
            } label: {
                Label("Open in \(providerTitle)", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(10)
        }
    }

    private var mediaLoadingPlaceholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            ProgressView()
        }
    }

    private func unavailable(_ resource: ExternalMediaResource) -> some View {
        Button {
            presentedURL = PresentedURL(url: resource.originalURL)
        } label: {
            ContentUnavailableView {
                Label("Media unavailable", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("Open it safely on \(resource.provider.title)")
            }
        }
        .buttonStyle(.plain)
    }

    private func providerButton(_ resource: ExternalMediaResource) -> some View {
        Button {
            presentedURL = PresentedURL(url: resource.originalURL)
        } label: {
            Label(resource.provider.title, systemImage: "arrow.up.right")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Open original on \(resource.provider.title)")
    }
}

private struct CommentBodyView: View {
    let comment: RedditComment
    let sensitiveMedia: Bool

    @Environment(LocalLibrary.self) private var library
    @State private var hasRevealedMedia = false
    @State private var showsAdditionalMediaLinks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !comment.displayBody.isEmpty {
                MarkdownBody(text: comment.displayBody, font: .subheadline)
            }

            if !comment.inlineMediaURLs.isEmpty {
                if sensitiveMedia, library.blurNSFW, !hasRevealedMedia {
                    Button {
                        hasRevealedMedia = true
                        HapticFeedback.impact(enabled: library.hapticsEnabled)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.quaternary.opacity(0.7))
                            VStack(spacing: 7) {
                                Image(systemName: "eye.slash.fill").font(.title3)
                                Text("Sensitive comment media").font(.subheadline.bold())
                                Text("Tap to reveal").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: ExternalMediaPresentation.comment.minimumHeight)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(comment.inlineMediaURLs.prefix(4)), id: \.absoluteString) { url in
                            ResolvedExternalMediaView(
                                sourceURL: url,
                                previewURL: ExternalMediaClassifier.immediateResource(for: url)?.posterURL,
                                autoplay: false,
                                presentation: .comment
                            )
                        }

                        if comment.inlineMediaURLs.count > 4 {
                            DisclosureGroup(isExpanded: $showsAdditionalMediaLinks) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(comment.inlineMediaURLs.dropFirst(4)), id: \.absoluteString) { url in
                                        Link(destination: url) {
                                            Label(
                                                url.host?.replacingOccurrences(of: "www.", with: "") ?? "Media link",
                                                systemImage: "arrow.up.right"
                                            )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .padding(.top, 5)
                            } label: {
                                Label(
                                    "\(comment.inlineMediaURLs.count - 4) more media links",
                                    systemImage: "link"
                                )
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct ProviderEmbedCard: View {
    let resource: ExternalMediaResource
    let previewURL: URL?
    let autoplay: Bool
    let height: CGFloat
    let openOriginal: () -> Void

    @State private var hasStarted = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if hasStarted {
                ProviderWebView(url: resource.mediaURL, autoplay: autoplay)
                    .frame(height: height)
                    .background(.black)
            } else {
                ZStack {
                    if let previewURL {
                        AsyncImage(url: previewURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Rectangle().fill(.quaternary)
                            }
                        }
                    } else {
                        LinearGradient(
                            colors: [Color.black.opacity(0.82), AppTheme.tint.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }

                    Button {
                        hasStarted = true
                    } label: {
                        VStack(spacing: 9) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 52))
                            Text("Play from \(resource.provider.title)")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .shadow(radius: 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: height)
                .clipped()
            }

            Button(action: openOriginal) {
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .padding(9)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(10)
            .accessibilityLabel("Open on \(resource.provider.title)")
        }
    }
}

private struct ProviderWebView: UIViewRepresentable {
    let url: URL
    let autoplay: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(initialHost: url.host?.lowercased())
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = autoplay ? [] : .all
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let initialHost: String?

        init(initialHost: String?) {
            self.initialHost = initialHost
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destinationHost = navigationAction.request.url?.host?.lowercased(),
                  let initialHost else {
                decisionHandler(.cancel)
                return
            }
            let isSameProvider = destinationHost == initialHost
                || destinationHost.hasSuffix(".\(initialHost)")
                || initialHost.hasSuffix(".\(destinationHost)")
            decisionHandler(isSameProvider ? .allow : .cancel)
        }
    }
}

private struct AnimatedRemoteImage: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        load(url, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        load(url, in: webView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, in webView: WKWebView, coordinator: Coordinator) {
        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}img{width:100%;height:100%;object-fit:contain}</style>
        </head><body><img src="\(escapedURL)" alt="Animated image"></body></html>
        """
        coordinator.loadedURL = url
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}

private struct CommentThreadView: View {
    let comment: RedditComment
    let depth: Int
    let sensitiveMedia: Bool
    let postAuthor: String
    let searchQuery: String

    @Environment(LocalLibrary.self) private var library

    private var collapsed: Bool { library.isCommentCollapsed(comment.id) }
    private var isPostAuthor: Bool {
        comment.author.caseInsensitiveCompare(postAuthor) == .orderedSame
    }
    private var isSearchMatch: Bool {
        !searchQuery.isEmpty
            && LocalContentFilters.normalized("\(comment.author) \(comment.displayBody)").contains(searchQuery)
    }

    private var lineColor: Color {
        Color.secondary.opacity(0.28)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { library.toggleCommentCollapsed(comment.id) } label: {
                HStack(spacing: 5) {
                    Text("u/\(comment.author)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isPostAuthor ? AppTheme.tint : (comment.stickied ? Color.green : Color.primary))
                    if isPostAuthor {
                        Text("OP")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.tint)
                    } else if let distinguished = comment.distinguished, !distinguished.isEmpty {
                        Text(distinguished.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                    if isSearchMatch {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.tint)
                    }
                    Text("· \(comment.createdUTC.relativeRedditTime)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if comment.isEdited {
                        Text("edited").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Label(comment.score.compactCount, systemImage: "arrow.up")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: collapsed ? "plus.circle" : "minus.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    library.toggleSavedComment(comment)
                } label: {
                    Label(
                        library.isCommentSaved(comment) ? "Remove Saved Comment" : "Save Comment",
                        systemImage: library.isCommentSaved(comment) ? "bookmark.slash" : "bookmark"
                    )
                }
                Button {
                    library.muteAuthor(comment.author)
                } label: {
                    Label("Mute u/\(comment.author)", systemImage: "person.slash")
                }
            }

            if !collapsed {
                CommentBodyView(comment: comment, sensitiveMedia: sensitiveMedia)

                if !comment.replies.isEmpty, depth < 7 {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(comment.replies) { reply in
                            CommentThreadView(
                                comment: reply,
                                depth: depth + 1,
                                sensitiveMedia: sensitiveMedia,
                                postAuthor: postAuthor,
                                searchQuery: searchQuery
                            )
                        }
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(lineColor).frame(width: 1)
                    }
                }
            } else {
                Text("\(comment.replies.count.compactCount) replies hidden")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, isSearchMatch ? 7 : 0)
        .background(
            isSearchMatch ? AppTheme.tintSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CommentPositionPreferenceKey.self,
                    value: [
                        comment.id: proxy.frame(in: .named(CommentScrollCoordinateSpace.name)).minY
                    ]
                )
            }
        }
        .id("comment-\(comment.id)")
    }
}

enum CommentScrollCoordinateSpace {
    static let name = "post-detail-comments"
}

struct CommentPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct CommentNavigationNode {
    let id: String
    let parentID: String?
    let rootID: String
    let ancestorIDs: [String]
    let searchText: String
}

private struct MarkdownBody: View {
    let text: String
    var font: Font = .body

    var body: some View {
        Text(attributedText)
            .font(font)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: text.htmlDecoded, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text.htmlDecoded)
    }
}

private struct CommentPlaceholders: View {
    var body: some View {
        ForEach(0..<4, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 150, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 13)
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 240, height: 13)
            }
            .redacted(reason: .placeholder)
            .padding(.vertical, 5)
        }
    }
}

struct MediaSelection: Identifiable {
    let urls: [URL]
    let selectedIndex: Int
    var id: String { "\(selectedIndex):\(urls.map(\.absoluteString).joined(separator: "|"))" }
}

struct FullScreenMediaView: View {
    let selection: MediaSelection
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int
    @State private var saveMessage: String?

    init(selection: MediaSelection) {
        self.selection = selection
        _selectedIndex = State(initialValue: selection.selectedIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(selection.urls.enumerated()), id: \.offset) { index, url in
                    ZoomableImage(url: url).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: selection.urls.count > 1 ? .always : .never))
            .background(.black)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: selection.urls[selectedIndex]) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button {
                        Task { await saveCurrentImage() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Save image to Photos")
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .alert("Media", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveMessage = nil }
        } message: {
            Text(saveMessage ?? "")
        }
    }

    @MainActor
    private func saveCurrentImage() async {
        let url = selection.urls[selectedIndex]
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else {
            saveMessage = "This item is not a downloadable image."
            return
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = "Photo access is required to save images."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveMessage = "Saved to Photos."
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

struct FullScreenImageView: View {
    let url: URL

    var body: some View {
        FullScreenMediaView(selection: MediaSelection(urls: [url], selectedIndex: 0))
    }
}

struct ZoomableImage: View {
    let url: URL
    @State private var scale = 1.0
    @State private var lastScale = 1.0

    var body: some View {
        Group {
            if ExternalMediaClassifier.immediateResource(for: url)?.kind == .animatedImage {
                AnimatedRemoteImage(url: url)
            } else {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
                            .foregroundStyle(.white)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
        }
        .scaleEffect(scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .onChanged { value in scale = max(1, min(5, lastScale * value.magnification)) }
                .onEnded { _ in lastScale = scale }
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                scale = scale > 1 ? 1 : 2.5
                lastScale = scale
            }
        }
    }
}

struct PresentedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) { }
}
