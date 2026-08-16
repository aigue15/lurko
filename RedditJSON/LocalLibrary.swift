import Foundation
import Observation
import CryptoKit
import WidgetKit

enum RedditInterface: String, Codable, CaseIterable, Identifiable {
    case browser
    case apollo
    case reddit

    var id: Self { self }

    var title: String {
        switch self {
        case .browser: "Browser"
        case .apollo: "Apollo"
        case .reddit: "Reddit"
        }
    }

    var icon: String {
        switch self {
        case .browser: "safari"
        case .apollo: "a.circle.fill"
        case .reddit: "app.badge.fill"
        }
    }

    func destinationURL(for post: RedditPost) -> URL? {
        switch self {
        case .browser:
            return post.redditURL
        case .apollo:
            return URL(string: "apollo://www.reddit.com\(post.permalink)")
        case .reddit:
            return URL(string: "reddit://reddit.com\(post.permalink)")
        }
    }
}

/// Controls how much information each item in a feed presents.
enum FeedLayout: String, Codable, CaseIterable, Identifiable {
    case comfortable
    case compact
    case media

    var id: Self { self }

    var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        case .media: "Large media"
        }
    }

    var icon: String {
        switch self {
        case .comfortable: "rectangle.grid.1x2"
        case .compact: "list.bullet"
        case .media: "photo.on.rectangle.angled"
        }
    }
}

@MainActor
@Observable
final class LocalLibrary {
    private enum Key {
        // Keep the original keys so existing installations migrate without data loss.
        static let subscriptions = "local.subscriptions.v1"
        static let savedPosts = "local.saved-posts.v1"
        static let redditInterface = "preferences.reddit-interface.v1"

        static let history = "local.history.v1"
        static let readPostDates = "local.read-post-dates.v1"
        static let feedLayout = "preferences.feed-layout.v1"
        static let defaultSort = "preferences.default-sort.v1"
        static let showNSFWContent = "preferences.show-nsfw-content.v1"
        static let blurNSFW = "preferences.blur-nsfw.v1"
        static let blurSpoilers = "preferences.blur-spoilers.v1"
        static let autoplayVideos = "preferences.autoplay-videos.v1"
        static let muteVideosByDefault = "preferences.mute-videos-by-default.v1"
        static let hapticsEnabled = "preferences.haptics-enabled.v1"
        static let markPostsReadOnOpen = "preferences.mark-read-on-open.v1"
        static let contentFilters = "local.content-filters.v1"
        static let hiddenPostIDs = "local.hidden-post-ids.v1"
        static let postMetadata = "local.post-metadata.v1"
        static let collections = "local.post-collections.v1"
        static let readingCheckpoints = "local.reading-checkpoints.v1"
        static let feedLastVisitedAt = "local.feed-last-visited.v1"
        static let collapsedCommentIDs = "local.collapsed-comment-ids.v1"
        static let skippedPostDates = "local.skipped-post-dates.v1"
        static let offlineCacheLimitMB = "preferences.offline-cache-limit-mb.v1"
        static let lowDataMode = "preferences.low-data-mode.v1"
    }

    private enum Limit {
        static let subscriptions = 2_000
        static let savedPosts = 1_000
        static let history = 300
        static let readPosts = 5_000
        static let hiddenPosts = 5_000
        static let skippedPosts = 1_000
        static let checkpoints = 500
        static let readPostLifetime: TimeInterval = 180 * 24 * 60 * 60
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let archiveStore: LocalArchiveDiskStore
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    var subscriptions: [String] {
        didSet { persistSubscriptions() }
    }

    var savedPosts: [RedditPost] {
        didSet {
            persistSavedPosts()
            refreshSystemIndex()
        }
    }

    private(set) var history: [LocalHistoryEntry] {
        didSet {
            persistHistory()
            refreshSystemIndex()
        }
    }

    private var readPostDates: [String: Date] {
        didSet { persistReadPostDates() }
    }

    var contentFilters: LocalContentFilters {
        didSet { persist(contentFilters.cleaned(), forKey: Key.contentFilters) }
    }

    private(set) var hiddenPostIDs: Set<String> {
        didSet { persist(Array(hiddenPostIDs.prefix(Limit.hiddenPosts)), forKey: Key.hiddenPostIDs) }
    }

    private(set) var postMetadata: [String: LocalPostMetadata] {
        didSet {
            persist(postMetadata, forKey: Key.postMetadata)
            refreshSystemIndex()
        }
    }

    private(set) var collections: [LocalPostCollection] {
        didSet { persist(collections, forKey: Key.collections) }
    }

    private(set) var offlineSnapshots: [String: OfflinePostSnapshot] {
        didSet { persistArchive() }
    }

    private(set) var savedComments: [String: OfflineComment] {
        didSet { persistArchive() }
    }

    private(set) var readingCheckpoints: [String: LocalReadingCheckpoint] {
        didSet { persist(readingCheckpoints, forKey: Key.readingCheckpoints) }
    }

    private(set) var feedLastVisitedAt: [String: Date] {
        didSet { persist(feedLastVisitedAt, forKey: Key.feedLastVisitedAt) }
    }

    private(set) var collapsedCommentIDs: Set<String> {
        didSet { persist(Array(collapsedCommentIDs.prefix(5_000)), forKey: Key.collapsedCommentIDs) }
    }

    private(set) var skippedPostDates: [String: Date] {
        didSet { persist(skippedPostDates, forKey: Key.skippedPostDates) }
    }

    var redditInterface: RedditInterface {
        didSet { defaults.set(redditInterface.rawValue, forKey: Key.redditInterface) }
    }

    var feedLayout: FeedLayout {
        didSet { defaults.set(feedLayout.rawValue, forKey: Key.feedLayout) }
    }

    var defaultSort: FeedSort {
        didSet { defaults.set(defaultSort.rawValue, forKey: Key.defaultSort) }
    }

    /// Whether mature posts are allowed into feeds at all.
    var showNSFWContent: Bool {
        didSet { defaults.set(showNSFWContent, forKey: Key.showNSFWContent) }
    }

    /// Whether mature media is covered until the reader explicitly reveals it.
    var blurNSFW: Bool {
        didSet { defaults.set(blurNSFW, forKey: Key.blurNSFW) }
    }

    var blurSpoilers: Bool {
        didSet { defaults.set(blurSpoilers, forKey: Key.blurSpoilers) }
    }

    var autoplayVideos: Bool {
        didSet { defaults.set(autoplayVideos, forKey: Key.autoplayVideos) }
    }

    var muteVideosByDefault: Bool {
        didSet { defaults.set(muteVideosByDefault, forKey: Key.muteVideosByDefault) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    var markPostsReadOnOpen: Bool {
        didSet { defaults.set(markPostsReadOnOpen, forKey: Key.markPostsReadOnOpen) }
    }

    var offlineCacheLimitMB: Int {
        didSet {
            let boundedValue = max(50, min(offlineCacheLimitMB, 1_000))
            if offlineCacheLimitMB != boundedValue {
                offlineCacheLimitMB = boundedValue
                return
            }
            defaults.set(offlineCacheLimitMB, forKey: Key.offlineCacheLimitMB)
            Task { await OfflineMediaCache.shared.configure(limitMB: offlineCacheLimitMB) }
        }
    }

    var lowDataMode: Bool {
        didSet { defaults.set(lowDataMode, forKey: Key.lowDataMode) }
    }

    /// Compatibility aliases for call sites that describe these settings as media preferences.
    var blurNSFWMedia: Bool {
        get { blurNSFW }
        set { blurNSFW = newValue }
    }

    var autoplayMedia: Bool {
        get { autoplayVideos }
        set { autoplayVideos = newValue }
    }

    var recentlyViewedPosts: [RedditPost] {
        history.map(\.post)
    }

    var readPostIDs: Set<String> {
        Set(readPostDates.keys)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let archiveStore = LocalArchiveDiskStore()
        self.archiveStore = archiveStore
        let decoder = JSONDecoder()
        let archive = archiveStore.load()

        let decodedSubscriptions = defaults.stringArray(forKey: Key.subscriptions) ?? ["suits", "apple"]
        subscriptions = Self.cleanedSubscriptions(decodedSubscriptions)

        if let data = defaults.data(forKey: Key.savedPosts),
           let decoded = try? decoder.decode([RedditPost].self, from: data) {
            savedPosts = Self.cleanedPosts(decoded, limit: Limit.savedPosts)
        } else {
            savedPosts = []
        }

        if let data = defaults.data(forKey: Key.history),
           let decoded = try? decoder.decode([LocalHistoryEntry].self, from: data) {
            history = Self.cleanedHistory(decoded)
        } else {
            history = []
        }

        if let data = defaults.data(forKey: Key.readPostDates),
           let decoded = try? decoder.decode([String: Date].self, from: data) {
            readPostDates = Self.cleanedReadDates(decoded)
        } else {
            readPostDates = [:]
        }

        contentFilters = defaults.data(forKey: Key.contentFilters)
            .flatMap { try? decoder.decode(LocalContentFilters.self, from: $0) }?.cleaned() ?? .init()
        hiddenPostIDs = Set(
            defaults.data(forKey: Key.hiddenPostIDs)
                .flatMap { try? decoder.decode([String].self, from: $0) } ?? []
        )
        postMetadata = defaults.data(forKey: Key.postMetadata)
            .flatMap { try? decoder.decode([String: LocalPostMetadata].self, from: $0) } ?? [:]
        collections = defaults.data(forKey: Key.collections)
            .flatMap { try? decoder.decode([LocalPostCollection].self, from: $0) } ?? []
        offlineSnapshots = archive.snapshots
        savedComments = archive.savedComments
        readingCheckpoints = defaults.data(forKey: Key.readingCheckpoints)
            .flatMap { try? decoder.decode([String: LocalReadingCheckpoint].self, from: $0) } ?? [:]
        feedLastVisitedAt = defaults.data(forKey: Key.feedLastVisitedAt)
            .flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
        collapsedCommentIDs = Set(
            defaults.data(forKey: Key.collapsedCommentIDs)
                .flatMap { try? decoder.decode([String].self, from: $0) } ?? []
        )
        skippedPostDates = defaults.data(forKey: Key.skippedPostDates)
            .flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]

        redditInterface = defaults.string(forKey: Key.redditInterface)
            .flatMap(RedditInterface.init(rawValue:)) ?? .browser
        feedLayout = defaults.string(forKey: Key.feedLayout)
            .flatMap(FeedLayout.init(rawValue:)) ?? .comfortable
        defaultSort = defaults.string(forKey: Key.defaultSort)
            .flatMap(FeedSort.init(rawValue:)) ?? .hot

        showNSFWContent = defaults.object(forKey: Key.showNSFWContent) as? Bool ?? false
        blurNSFW = defaults.object(forKey: Key.blurNSFW) as? Bool ?? true
        blurSpoilers = defaults.object(forKey: Key.blurSpoilers) as? Bool ?? true
        autoplayVideos = defaults.object(forKey: Key.autoplayVideos) as? Bool ?? true
        muteVideosByDefault = defaults.object(forKey: Key.muteVideosByDefault) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        markPostsReadOnOpen = defaults.object(forKey: Key.markPostsReadOnOpen) as? Bool ?? true
        offlineCacheLimitMB = max(50, defaults.integer(forKey: Key.offlineCacheLimitMB))
        if defaults.object(forKey: Key.offlineCacheLimitMB) == nil { offlineCacheLimitMB = 250 }
        lowDataMode = defaults.object(forKey: Key.lowDataMode) as? Bool ?? false

        // Rewrite successfully decoded collections in their cleaned, bounded form. Corrupt
        // payloads are replaced with valid empty values rather than retried on every launch.
        persistSubscriptions()
        persistSavedPosts()
        persistHistory()
        persistReadPostDates()
        contentFilters = contentFilters.cleaned()
        for post in savedPosts where postMetadata[post.id]?.savedAt == nil {
            var metadata = postMetadata[post.id] ?? LocalPostMetadata(postID: post.id)
            metadata.savedAt = Date()
            postMetadata[post.id] = metadata.cleaned()
        }
        Task { await OfflineMediaCache.shared.configure(limitMB: offlineCacheLimitMB) }
    }

    // MARK: - Subscriptions

    func isSubscribed(to subreddit: String) -> Bool {
        let normalized = Self.normalizedSubreddit(subreddit)
        return !normalized.isEmpty && subscriptions.contains(normalized)
    }

    func subscribe(to subreddit: String) {
        let normalized = Self.normalizedSubreddit(subreddit)
        guard !normalized.isEmpty, !subscriptions.contains(normalized) else { return }
        subscriptions = Self.cleanedSubscriptions(subscriptions + [normalized])
    }

    func unsubscribe(from subreddit: String) {
        let normalized = Self.normalizedSubreddit(subreddit)
        subscriptions.removeAll { $0 == normalized }
    }

    func toggleSubscription(_ subreddit: String) {
        if isSubscribed(to: subreddit) {
            unsubscribe(from: subreddit)
        } else {
            subscribe(to: subreddit)
        }
    }

    func removeSubscriptions(at offsets: IndexSet) {
        Self.removeElements(at: offsets, from: &subscriptions)
    }

    func clearSubscriptions() {
        subscriptions.removeAll()
    }

    // MARK: - Saved posts

    func isSaved(_ post: RedditPost) -> Bool {
        isSaved(postID: post.id)
    }

    func isSaved(postID: String) -> Bool {
        savedPosts.contains { $0.id == postID }
    }

    func save(_ post: RedditPost) {
        var updated = savedPosts.filter { $0.id != post.id }
        updated.insert(post, at: 0)
        savedPosts = Array(updated.prefix(Limit.savedPosts))
        var metadata = postMetadata[post.id] ?? LocalPostMetadata(postID: post.id)
        metadata.savedAt = metadata.savedAt ?? Date()
        postMetadata[post.id] = metadata.cleaned()
        archive(post)
    }

    func unsave(_ post: RedditPost) {
        unsave(postID: post.id)
    }

    func unsave(postID: String) {
        savedPosts.removeAll { $0.id == postID }
        guard var metadata = postMetadata[postID] else { return }
        metadata.savedAt = nil
        postMetadata[postID] = metadata.cleaned()
        pruneLocalPostIfUnretained(postID)
    }

    func toggleSaved(_ post: RedditPost) {
        if isSaved(post) {
            unsave(post)
        } else {
            save(post)
        }
    }

    func removeSavedPosts(at offsets: IndexSet) {
        let postIDs = offsets.compactMap { savedPosts.indices.contains($0) ? savedPosts[$0].id : nil }
        postIDs.forEach { unsave(postID: $0) }
    }

    func clearSavedPosts() {
        savedPosts.removeAll()
        for postID in Array(postMetadata.keys) {
            postMetadata[postID]?.savedAt = nil
            pruneLocalPostIfUnretained(postID)
        }
    }

    /// Refreshes metadata such as score and reply count without changing a post's order.
    func updateStoredPost(_ post: RedditPost) {
        if let index = savedPosts.firstIndex(where: { $0.id == post.id }) {
            savedPosts[index] = post
        }

        if let index = history.firstIndex(where: { $0.id == post.id }) {
            let viewedAt = history[index].viewedAt
            history[index] = LocalHistoryEntry(post: post, viewedAt: viewedAt)
        }
    }

    // MARK: - History

    func recordViewed(_ post: RedditPost) {
        var updated = history.filter { $0.id != post.id }
        updated.insert(LocalHistoryEntry(post: post, viewedAt: Date()), at: 0)
        history = Array(updated.prefix(Limit.history))

        if markPostsReadOnOpen {
            markRead(post)
        }
    }

    func removeHistory(at offsets: IndexSet) {
        Self.removeElements(at: offsets, from: &history)
    }

    func removeFromHistory(_ post: RedditPost) {
        removeFromHistory(postID: post.id)
    }

    func removeFromHistory(postID: String) {
        history.removeAll { $0.id == postID }
    }

    func clearHistory() {
        history.removeAll()
    }

    // MARK: - Read state

    func isRead(_ post: RedditPost) -> Bool {
        isRead(postID: post.id)
    }

    func isRead(postID: String) -> Bool {
        readPostDates[postID] != nil
    }

    func markRead(_ post: RedditPost) {
        markRead(postID: post.id)
    }

    func markRead(postID: String) {
        guard !postID.isEmpty else { return }
        readPostDates[postID] = Date()
        pruneReadPostDatesIfNeeded()
    }

    func markUnread(_ post: RedditPost) {
        markUnread(postID: post.id)
    }

    func markUnread(postID: String) {
        readPostDates.removeValue(forKey: postID)
    }

    func clearReadHistory() {
        readPostDates.removeAll()
    }

    // MARK: - Local library metadata

    func metadata(for postID: String) -> LocalPostMetadata {
        postMetadata[postID] ?? LocalPostMetadata(postID: postID)
    }

    func isFavorite(_ post: RedditPost) -> Bool {
        postMetadata[post.id]?.isFavorite == true
    }

    func toggleFavorite(_ post: RedditPost) {
        var metadata = postMetadata[post.id] ?? LocalPostMetadata(postID: post.id)
        metadata.favoritedAt = metadata.isFavorite ? nil : Date()
        postMetadata[post.id] = metadata.cleaned()
        if metadata.favoritedAt != nil { archive(post) }
        else { pruneLocalPostIfUnretained(post.id) }
    }

    func isQueued(_ post: RedditPost) -> Bool {
        postMetadata[post.id]?.isQueued == true
    }

    func toggleReadingQueue(_ post: RedditPost) {
        var metadata = postMetadata[post.id] ?? LocalPostMetadata(postID: post.id)
        metadata.queuedAt = metadata.isQueued ? nil : Date()
        postMetadata[post.id] = metadata.cleaned()
        if metadata.queuedAt != nil { archive(post) }
        else { pruneLocalPostIfUnretained(post.id) }
    }

    func updateMetadata(for post: RedditPost, note: String, tags: [String], collectionIDs: [UUID]) {
        var metadata = postMetadata[post.id] ?? LocalPostMetadata(postID: post.id)
        metadata.note = note
        metadata.tags = tags
        metadata.collectionIDs = collectionIDs
        postMetadata[post.id] = metadata.cleaned()
        archive(post)
    }

    func addCollection(named name: String) {
        let collection = LocalPostCollection(name: name)
        guard !collection.name.isEmpty,
              !collections.contains(where: { $0.name.caseInsensitiveCompare(collection.name) == .orderedSame }) else {
            return
        }
        collections.append(collection)
        collections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func deleteCollection(_ collection: LocalPostCollection) {
        collections.removeAll { $0.id == collection.id }
        for postID in Array(postMetadata.keys) {
            postMetadata[postID]?.collectionIDs.removeAll { $0 == collection.id }
        }
    }

    var favoritePosts: [RedditPost] {
        allLocalPosts.filter { postMetadata[$0.id]?.isFavorite == true }
            .sorted { (postMetadata[$0.id]?.favoritedAt ?? .distantPast) > (postMetadata[$1.id]?.favoritedAt ?? .distantPast) }
    }

    var queuedPosts: [RedditPost] {
        allLocalPosts.filter { postMetadata[$0.id]?.isQueued == true }
            .sorted { (postMetadata[$0.id]?.queuedAt ?? .distantPast) > (postMetadata[$1.id]?.queuedAt ?? .distantPast) }
    }

    func posts(in collection: LocalPostCollection) -> [RedditPost] {
        allLocalPosts.filter { postMetadata[$0.id]?.collectionIDs.contains(collection.id) == true }
    }

    var unreadSavedPosts: [RedditPost] {
        savedPosts.filter { !isRead($0) }
    }

    var recentlySavedPosts: [RedditPost] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return savedPosts.filter { (postMetadata[$0.id]?.savedAt ?? .distantPast) >= cutoff }
    }

    var recentlySkippedPosts: [RedditPost] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return allLocalPosts
            .filter { (skippedPostDates[$0.id] ?? .distantPast) >= cutoff }
            .sorted { (skippedPostDates[$0.id] ?? .distantPast) > (skippedPostDates[$1.id] ?? .distantPast) }
    }

    // MARK: - Offline archive and search

    func archive(_ post: RedditPost) {
        let existing = offlineSnapshots[post.id]
        offlineSnapshots[post.id] = OfflinePostSnapshot(
            post: post,
            comments: existing?.comments ?? [],
            savedAt: existing?.savedAt ?? Date(),
            updatedAt: Date()
        )
        pruneOfflineArchiveIfNeeded()
        let urls = offlineSnapshots[post.id]?.mediaURLs ?? []
        Task { await OfflineMediaCache.shared.prefetch(urls: urls, lowDataMode: lowDataMode) }
    }

    func archiveComments(_ comments: [RedditComment], for post: RedditPost) {
        var snapshot = offlineSnapshots[post.id] ?? OfflinePostSnapshot(post: post)
        snapshot.comments = comments.map { OfflineComment($0) }
        snapshot.updatedAt = Date()
        offlineSnapshots[post.id] = snapshot
        pruneOfflineArchiveIfNeeded()
    }

    func offlineComments(for postID: String) -> [OfflineComment] {
        offlineSnapshots[postID]?.comments ?? []
    }

    func isCommentSaved(_ comment: RedditComment) -> Bool {
        savedComments[comment.id] != nil
    }

    func toggleSavedComment(_ comment: RedditComment) {
        if savedComments[comment.id] != nil {
            savedComments.removeValue(forKey: comment.id)
        } else {
            savedComments[comment.id] = OfflineComment(comment, savedAt: Date())
        }
        if savedComments.count > LocalFeatureLimits.maximumSavedComments {
            let retained = savedComments.values
                .sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
                .prefix(LocalFeatureLimits.maximumSavedComments)
            savedComments = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
        }
    }

    func removeSavedComment(id: String) {
        savedComments.removeValue(forKey: id)
    }

    func localSearch(_ query: String) -> [LocalSearchResult] {
        LocalSearchEngine.search(
            query: query,
            posts: allLocalPosts,
            metadata: postMetadata,
            snapshots: offlineSnapshots
        )
    }

    func importPendingSharedLinks() {
        for link in ThreadlineSharedStore.takePendingLinks() {
            let components = link.url.pathComponents.filter { $0 != "/" }
            let subreddit: String = {
                guard let rIndex = components.firstIndex(of: "r"), components.indices.contains(rIndex + 1) else {
                    return link.url.host ?? "web"
                }
                return components[rIndex + 1]
            }()
            let postID: String = {
                guard let commentsIndex = components.firstIndex(of: "comments"),
                      components.indices.contains(commentsIndex + 1) else {
                    let digest = SHA256.hash(data: Data(link.url.absoluteString.utf8))
                    return "shared-" + digest.prefix(10).map { String(format: "%02x", $0) }.joined()
                }
                return components[commentsIndex + 1]
            }()
            let post = RedditPost(
                id: postID,
                title: link.title.isEmpty ? (link.url.host ?? link.url.absoluteString) : link.title,
                author: "unknown",
                subreddit: subreddit,
                permalink: link.url.path,
                url: link.url.absoluteString,
                postHint: "link",
                createdUTC: link.savedAt.timeIntervalSince1970
            )
            save(post)
            if !isQueued(post) { toggleReadingQueue(post) }
        }
    }

    func updateRecentPostsWidget(_ posts: [RedditPost]) {
        ThreadlineSharedStore.writeRecentWidgetItems(
            posts.prefix(8).map {
                SharedWidgetItem(
                    id: $0.id,
                    title: $0.title,
                    subreddit: $0.subreddit,
                    queued: postMetadata[$0.id]?.isQueued == true
                )
            }
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    var allLocalPosts: [RedditPost] {
        var seen = Set<String>()
        return (savedPosts + history.map(\.post) + offlineSnapshots.values.map(\.post))
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: - Filters and continuity

    func hide(_ post: RedditPost) {
        hiddenPostIDs.insert(post.id)
        skippedPostDates[post.id] = Date()
        archive(post)
    }

    func unhide(_ post: RedditPost) {
        hiddenPostIDs.remove(post.id)
        skippedPostDates.removeValue(forKey: post.id)
    }

    func clearHiddenPosts() {
        hiddenPostIDs.removeAll()
        skippedPostDates.removeAll()
    }

    func muteAuthor(_ author: String) {
        contentFilters.mutedAuthors.append(author)
        contentFilters = contentFilters.cleaned()
    }

    func muteSubreddit(_ subreddit: String) {
        contentFilters.mutedSubreddits.append(subreddit.removingSubredditPrefix)
        contentFilters = contentFilters.cleaned()
    }

    func muteDomain(_ domain: String) {
        contentFilters.mutedDomains.append(domain)
        contentFilters = contentFilters.cleaned()
    }

    func filterPosts(_ posts: [RedditPost]) -> [RedditPost] {
        contentFilters.filtered(posts, hiddenPostIDs: hiddenPostIDs)
            .filter { showNSFWContent || !$0.over18 }
    }

    func saveReadingCheckpoint(containerID: String, anchorID: String?, offset: Double? = nil) {
        readingCheckpoints[containerID] = LocalReadingCheckpoint(
            containerID: containerID,
            anchorID: anchorID,
            offset: offset
        )
        if readingCheckpoints.count > Limit.checkpoints {
            readingCheckpoints = Dictionary(
                uniqueKeysWithValues: readingCheckpoints.values
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(Limit.checkpoints)
                    .map { ($0.containerID, $0) }
            )
        }
    }

    func readingCheckpoint(for containerID: String) -> LocalReadingCheckpoint? {
        readingCheckpoints[containerID]
    }

    func markFeedVisited(_ feedID: String, at date: Date = Date()) {
        feedLastVisitedAt[feedID] = date
    }

    func isNewSinceLastVisit(_ post: RedditPost, feedID: String) -> Bool {
        guard let lastVisit = feedLastVisitedAt[feedID] else { return true }
        return Date(timeIntervalSince1970: post.createdUTC) > lastVisit
    }

    func isCommentCollapsed(_ commentID: String) -> Bool {
        collapsedCommentIDs.contains(commentID)
    }

    func toggleCommentCollapsed(_ commentID: String) {
        if collapsedCommentIDs.contains(commentID) {
            collapsedCommentIDs.remove(commentID)
        } else {
            collapsedCommentIDs.insert(commentID)
        }
    }

    // MARK: - Content policy

    func shouldDisplay(_ post: RedditPost) -> Bool {
        filterPosts([post]).first != nil
    }

    func shouldBlurMedia(for post: RedditPost) -> Bool {
        (post.over18 && blurNSFW) || (post.spoiler && blurSpoilers)
    }

    func shouldAutoplay(_ post: RedditPost) -> Bool {
        autoplayVideos && post.isVideo && shouldDisplay(post) && !shouldBlurMedia(for: post)
    }

    // MARK: - Maintenance

    /// Re-applies bounds and deduplication after an import or a long-running session.
    func performStorageMaintenance() {
        subscriptions = Self.cleanedSubscriptions(subscriptions)
        savedPosts = Self.cleanedPosts(savedPosts, limit: Limit.savedPosts)
        history = Self.cleanedHistory(history)
        readPostDates = Self.cleanedReadDates(readPostDates)
        contentFilters = contentFilters.cleaned()
        hiddenPostIDs = Set(hiddenPostIDs.prefix(Limit.hiddenPosts))
        skippedPostDates = Dictionary(
            uniqueKeysWithValues: skippedPostDates
                .sorted { $0.value > $1.value }
                .prefix(Limit.skippedPosts)
                .map { ($0.key, $0.value) }
        )
        postMetadata = Dictionary(
            uniqueKeysWithValues: postMetadata.values.map { ($0.postID, $0.cleaned()) }
        )
        pruneOfflineArchiveIfNeeded()
    }

    /// Clears browsing traces while leaving subscriptions, saves, and preferences intact.
    func clearBrowsingData() {
        history.removeAll()
        readPostDates.removeAll()
    }

    func resetPreferences() {
        redditInterface = .browser
        feedLayout = .comfortable
        defaultSort = .hot
        showNSFWContent = false
        blurNSFW = true
        blurSpoilers = true
        autoplayVideos = true
        muteVideosByDefault = true
        hapticsEnabled = true
        markPostsReadOnOpen = true
        lowDataMode = false
        offlineCacheLimitMB = 250
    }

    func clearOfflineCache() async {
        await OfflineMediaCache.shared.clear()
    }

    func encryptedBackup(passphrase: String) throws -> Data {
        try LocalBackupCrypto.encrypt(backupPayload(), passphrase: passphrase)
    }

    func importEncryptedBackup(_ data: Data, passphrase: String) throws {
        let payload = try LocalBackupCrypto.decrypt(data, passphrase: passphrase)
        subscriptions = Self.cleanedSubscriptions(payload.subscriptions)
        savedPosts = Self.cleanedPosts(payload.savedPosts, limit: Limit.savedPosts)
        history = Self.cleanedHistory(payload.history)
        readPostDates = Self.cleanedReadDates(payload.readPostDates)
        contentFilters = payload.filters.cleaned()
        hiddenPostIDs = Set(payload.hiddenPostIDs.prefix(Limit.hiddenPosts))
        postMetadata = Dictionary(
            uniqueKeysWithValues: payload.metadata.values.map { ($0.postID, $0.cleaned()) }
        )
        collections = payload.collections
        offlineSnapshots = payload.archive.snapshots
        savedComments = payload.archive.savedComments
        readingCheckpoints = payload.readingCheckpoints
        feedLastVisitedAt = payload.feedLastVisitedAt
        collapsedCommentIDs = payload.collapsedCommentIDs
        skippedPostDates = payload.skippedPostDates
        performStorageMaintenance()
    }

    private func backupPayload() -> LocalBackupPayload {
        LocalBackupPayload(
            subscriptions: subscriptions,
            savedPosts: savedPosts,
            history: history,
            readPostDates: readPostDates,
            filters: contentFilters,
            hiddenPostIDs: hiddenPostIDs,
            metadata: postMetadata,
            collections: collections,
            archive: LocalArchivePayload(snapshots: offlineSnapshots, savedComments: savedComments),
            readingCheckpoints: readingCheckpoints,
            feedLastVisitedAt: feedLastVisitedAt,
            collapsedCommentIDs: collapsedCommentIDs,
            skippedPostDates: skippedPostDates
        )
    }

    // MARK: - Persistence

    private func persistSubscriptions() {
        defaults.set(Self.cleanedSubscriptions(subscriptions), forKey: Key.subscriptions)
    }

    private func persistSavedPosts() {
        persist(Self.cleanedPosts(savedPosts, limit: Limit.savedPosts), forKey: Key.savedPosts)
    }

    private func persistHistory() {
        persist(Self.cleanedHistory(history), forKey: Key.history)
    }

    private func persistReadPostDates() {
        persist(Self.cleanedReadDates(readPostDates), forKey: Key.readPostDates)
    }

    private func persistArchive() {
        archiveStore.save(LocalArchivePayload(snapshots: offlineSnapshots, savedComments: savedComments))
    }

    private func persist<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func refreshSystemIndex() {
        let posts = allLocalPosts
        let metadata = postMetadata
        let widgetPosts = queuedPosts.isEmpty ? Array(savedPosts.prefix(8)) : Array(queuedPosts.prefix(8))
        ThreadlineSharedStore.writeWidgetItems(
            widgetPosts.map {
                SharedWidgetItem(
                    id: $0.id,
                    title: $0.title,
                    subreddit: $0.subreddit,
                    queued: postMetadata[$0.id]?.isQueued == true
                )
            }
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "ThreadlineQueueWidget")
        Task { await ThreadlineSpotlight.refresh(posts: posts, metadata: metadata) }
    }

    private func pruneReadPostDatesIfNeeded() {
        guard readPostDates.count > Limit.readPosts else { return }
        readPostDates = Self.cleanedReadDates(readPostDates)
    }

    private func pruneLocalPostIfUnretained(_ postID: String) {
        guard let metadata = postMetadata[postID],
              metadata.savedAt == nil,
              !metadata.isFavorite,
              !metadata.isQueued,
              metadata.note.isEmpty,
              metadata.tags.isEmpty,
              metadata.collectionIDs.isEmpty else { return }
        postMetadata.removeValue(forKey: postID)
        offlineSnapshots.removeValue(forKey: postID)
    }

    private func pruneOfflineArchiveIfNeeded() {
        guard offlineSnapshots.count > LocalFeatureLimits.maximumOfflineSnapshots else { return }
        let retained = offlineSnapshots.values
            .sorted { lhs, rhs in
                let lhsMetadata = postMetadata[lhs.post.id]
                let rhsMetadata = postMetadata[rhs.post.id]
                let lhsPriority = lhsMetadata?.isFavorite == true || lhsMetadata?.isQueued == true
                let rhsPriority = rhsMetadata?.isFavorite == true || rhsMetadata?.isQueued == true
                if lhsPriority != rhsPriority { return lhsPriority }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(LocalFeatureLimits.maximumOfflineSnapshots)
        offlineSnapshots = Dictionary(uniqueKeysWithValues: retained.map { ($0.post.id, $0) })
    }

    private static func normalizedSubreddit(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/") { value.removeFirst() }
        if value.lowercased().hasPrefix("r/") { value.removeFirst(2) }
        return value.redditNormalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func cleanedSubscriptions(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map(normalizedSubreddit)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(Limit.subscriptions)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func cleanedPosts(_ posts: [RedditPost], limit: Int) -> [RedditPost] {
        var seen = Set<String>()
        return Array(posts.lazy.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }.prefix(limit))
    }

    private static func cleanedHistory(_ entries: [LocalHistoryEntry]) -> [LocalHistoryEntry] {
        var seen = Set<String>()
        return Array(
            entries
                .sorted { $0.viewedAt > $1.viewedAt }
                .lazy
                .filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
                .prefix(Limit.history)
        )
    }

    private static func cleanedReadDates(_ dates: [String: Date], now: Date = Date()) -> [String: Date] {
        let oldestAllowed = now.addingTimeInterval(-Limit.readPostLifetime)
        return Dictionary(
            uniqueKeysWithValues: dates
                .filter { !$0.key.isEmpty && $0.value >= oldestAllowed && $0.value <= now }
                .sorted { $0.value > $1.value }
                .prefix(Limit.readPosts)
                .map { ($0.key, $0.value) }
        )
    }

    private static func removeElements<Element>(at offsets: IndexSet, from array: inout [Element]) {
        for index in offsets.sorted(by: >) where array.indices.contains(index) {
            array.remove(at: index)
        }
    }
}
