import Foundation
import CryptoKit

enum LocalFeatureLimits {
    static let maximumNoteLength = 2_000
    static let maximumTagsPerPost = 20
    static let maximumTagLength = 32
    static let maximumFilterValues = 500
    static let maximumOfflineSnapshots = 1_000
    static let maximumSavedComments = 2_000
}

/// A durable snapshot used by the on-device browsing history.
struct LocalHistoryEntry: Codable, Identifiable, Hashable {
    let post: RedditPost
    let viewedAt: Date

    var id: String { post.id }
}

enum LocalPostKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case text
    case image
    case video
    case gallery
    case link

    var id: Self { self }

    var title: String {
        switch self {
        case .text: "Text"
        case .image: "Images"
        case .video: "Videos"
        case .gallery: "Galleries"
        case .link: "Links"
        }
    }

    init(post: RedditPost) {
        if post.isGallery || !post.galleryImageURLs.isEmpty {
            self = .gallery
        } else if post.isVideo || post.videoURL != nil {
            self = .video
        } else if post.imageURL != nil {
            self = .image
        } else if post.isSelf || !post.selftext.isEmpty {
            self = .text
        } else {
            self = .link
        }
    }
}

enum LocalFilterReason: Hashable {
    case hidden
    case nsfw
    case author(String)
    case subreddit(String)
    case domain(String)
    case keyword(String)
    case flair(String)
    case postKind(LocalPostKind)
    case repost

    var title: String {
        switch self {
        case .hidden: "Hidden post"
        case .nsfw: "NSFW"
        case .author(let value): "Muted u/\(value)"
        case .subreddit(let value): "Muted r/\(value)"
        case .domain(let value): "Muted \(value)"
        case .keyword(let value): "Keyword: \(value)"
        case .flair(let value): "Flair: \(value)"
        case .postKind(let kind): "Blocked \(kind.title.lowercased())"
        case .repost: "Possible repost"
        }
    }
}

struct LocalContentFilters: Codable, Hashable {
    var mutedAuthors: [String] = []
    var mutedSubreddits: [String] = []
    var mutedDomains: [String] = []
    var keywords: [String] = []
    var mutedFlairs: [String] = []
    var blockedPostKinds: Set<LocalPostKind> = []
    var hideNSFW = false
    var hideReposts = false

    func reason(for post: RedditPost, hiddenPostIDs: Set<String> = []) -> LocalFilterReason? {
        if hiddenPostIDs.contains(post.id) { return .hidden }
        if hideNSFW && post.over18 { return .nsfw }

        let author = Self.normalized(post.author)
        if normalizedValues(mutedAuthors).contains(author) { return .author(post.author) }

        let subreddit = Self.normalized(post.subreddit.removingSubredditPrefix)
        if normalizedValues(mutedSubreddits).contains(subreddit) { return .subreddit(post.subreddit) }

        let domain = Self.normalized(post.domain)
        if normalizedValues(mutedDomains).contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }) {
            return .domain(post.domain)
        }

        let searchable = Self.normalized([post.title, post.selftext, post.authorFlairText ?? ""].joined(separator: " "))
        if let keyword = cleanedValues(keywords).first(where: { searchable.contains(Self.normalized($0)) }) {
            return .keyword(keyword)
        }

        let flair = Self.normalized(post.linkFlairText ?? "")
        if !flair.isEmpty,
           let muted = cleanedValues(mutedFlairs).first(where: { flair.contains(Self.normalized($0)) }) {
            return .flair(muted)
        }

        let kind = LocalPostKind(post: post)
        if blockedPostKinds.contains(kind) { return .postKind(kind) }
        return nil
    }

    func filtered(_ posts: [RedditPost], hiddenPostIDs: Set<String> = []) -> [RedditPost] {
        var seenReposts = Set<String>()
        return posts.filter { post in
            guard reason(for: post, hiddenPostIDs: hiddenPostIDs) == nil else { return false }
            guard hideReposts else { return true }
            let signature = repostSignature(for: post)
            guard !signature.isEmpty else { return true }
            return seenReposts.insert(signature).inserted
        }
    }

    func cleaned() -> Self {
        var copy = self
        copy.mutedAuthors = Self.cleanedList(mutedAuthors)
        copy.mutedSubreddits = Self.cleanedList(mutedSubreddits)
        copy.mutedDomains = Self.cleanedList(mutedDomains)
        copy.keywords = Self.cleanedList(keywords)
        copy.mutedFlairs = Self.cleanedList(mutedFlairs)
        return copy
    }

    private func repostSignature(for post: RedditPost) -> String {
        let title = Self.normalized(post.title)
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
        guard title.count >= 12 else { return "" }
        return "\(title)|\(Self.normalized(post.domain))"
    }

    private func normalizedValues(_ values: [String]) -> Set<String> {
        Set(cleanedValues(values).map(Self.normalized))
    }

    private func cleanedValues(_ values: [String]) -> [String] {
        Self.cleanedList(values)
    }

    private static func cleanedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized(value)
            guard !value.isEmpty, seen.insert(key).inserted else { continue }
            result.append(value)
            if result.count == LocalFeatureLimits.maximumFilterValues { break }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LocalPostMetadata: Codable, Hashable {
    let postID: String
    var savedAt: Date?
    var favoritedAt: Date?
    var queuedAt: Date?
    var note: String
    var tags: [String]
    var collectionIDs: [UUID]
    var lastOpenedAt: Date?
    var lastScrollOffset: Double?

    init(
        postID: String,
        savedAt: Date? = nil,
        favoritedAt: Date? = nil,
        queuedAt: Date? = nil,
        note: String = "",
        tags: [String] = [],
        collectionIDs: [UUID] = [],
        lastOpenedAt: Date? = nil,
        lastScrollOffset: Double? = nil
    ) {
        self.postID = postID
        self.savedAt = savedAt
        self.favoritedAt = favoritedAt
        self.queuedAt = queuedAt
        self.note = note
        self.tags = tags
        self.collectionIDs = collectionIDs
        self.lastOpenedAt = lastOpenedAt
        self.lastScrollOffset = lastScrollOffset
    }

    var isFavorite: Bool { favoritedAt != nil }
    var isQueued: Bool { queuedAt != nil }

    func cleaned() -> Self {
        var copy = self
        copy.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LocalFeatureLimits.maximumNoteLength))
        var seen = Set<String>()
        var cleanedTags: [String] = []
        for rawTag in tags {
            let tag = String(LocalContentFilters.normalized(rawTag).prefix(LocalFeatureLimits.maximumTagLength))
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            cleanedTags.append(tag)
            if cleanedTags.count == LocalFeatureLimits.maximumTagsPerPost { break }
        }
        copy.tags = cleanedTags.sorted()
        copy.collectionIDs = Array(Set(collectionIDs))
        if let offset = copy.lastScrollOffset {
            copy.lastScrollOffset = max(0, offset)
        }
        return copy
    }
}

struct LocalPostCollection: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        self.createdAt = createdAt
    }
}

struct LocalReadingCheckpoint: Codable, Hashable {
    let containerID: String
    var anchorID: String?
    var offset: Double?
    var updatedAt: Date

    init(containerID: String, anchorID: String? = nil, offset: Double? = nil, updatedAt: Date = Date()) {
        self.containerID = containerID
        self.anchorID = anchorID
        self.offset = offset.map { max(0, $0) }
        self.updatedAt = updatedAt
    }
}

struct OfflineComment: Codable, Hashable, Identifiable {
    let id: String
    let author: String
    let body: String
    let score: Int
    let createdUTC: TimeInterval
    let replies: [OfflineComment]
    var savedAt: Date?

    init(
        id: String,
        author: String,
        body: String,
        score: Int,
        createdUTC: TimeInterval,
        replies: [OfflineComment],
        savedAt: Date? = nil
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.score = score
        self.createdUTC = createdUTC
        self.replies = replies
        self.savedAt = savedAt
    }

    init(_ comment: RedditComment, savedAt: Date? = nil) {
        id = comment.id
        author = comment.author
        body = comment.displayBody
        score = comment.score
        createdUTC = comment.createdUTC
        replies = comment.replies.map { OfflineComment($0) }
        self.savedAt = savedAt
    }

    var flattened: [OfflineComment] {
        [self] + replies.flatMap(\.flattened)
    }
}

struct OfflinePostSnapshot: Codable, Hashable {
    let post: RedditPost
    var comments: [OfflineComment]
    var savedAt: Date
    var updatedAt: Date
    var mediaURLs: [URL]

    init(
        post: RedditPost,
        comments: [OfflineComment] = [],
        savedAt: Date = Date(),
        updatedAt: Date = Date(),
        mediaURLs: [URL]? = nil
    ) {
        self.post = post
        self.comments = comments
        self.savedAt = savedAt
        self.updatedAt = updatedAt
        self.mediaURLs = mediaURLs ?? Self.mediaURLs(for: post)
    }

    private static func mediaURLs(for post: RedditPost) -> [URL] {
        var urls = post.galleryMedia.flatMap { [$0.url, $0.posterURL].compactMap { $0 } }
        if let image = post.imageURL { urls.append(image) }
        if let video = post.videoURL { urls.append(video) }
        if let thumbnail = post.thumbnail.flatMap(URL.init(string:)) { urls.append(thumbnail) }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }
}

struct LocalArchivePayload: Codable {
    var snapshots: [String: OfflinePostSnapshot] = [:]
    var savedComments: [String: OfflineComment] = [:]
}

struct LocalBackupPayload: Codable {
    var schemaVersion = 1
    var exportedAt = Date()
    var subscriptions: [String]
    var savedPosts: [RedditPost]
    var history: [LocalHistoryEntry]
    var readPostDates: [String: Date]
    var filters: LocalContentFilters
    var hiddenPostIDs: Set<String>
    var metadata: [String: LocalPostMetadata]
    var collections: [LocalPostCollection]
    var archive: LocalArchivePayload
    var readingCheckpoints: [String: LocalReadingCheckpoint]
    var feedLastVisitedAt: [String: Date]
    var collapsedCommentIDs: Set<String>
    var skippedPostDates: [String: Date]

    init(
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        subscriptions: [String],
        savedPosts: [RedditPost],
        history: [LocalHistoryEntry],
        readPostDates: [String: Date],
        filters: LocalContentFilters,
        hiddenPostIDs: Set<String>,
        metadata: [String: LocalPostMetadata],
        collections: [LocalPostCollection],
        archive: LocalArchivePayload,
        readingCheckpoints: [String: LocalReadingCheckpoint],
        feedLastVisitedAt: [String: Date],
        collapsedCommentIDs: Set<String>,
        skippedPostDates: [String: Date] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.subscriptions = subscriptions
        self.savedPosts = savedPosts
        self.history = history
        self.readPostDates = readPostDates
        self.filters = filters
        self.hiddenPostIDs = hiddenPostIDs
        self.metadata = metadata
        self.collections = collections
        self.archive = archive
        self.readingCheckpoints = readingCheckpoints
        self.feedLastVisitedAt = feedLastVisitedAt
        self.collapsedCommentIDs = collapsedCommentIDs
        self.skippedPostDates = skippedPostDates
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, subscriptions, savedPosts, history, readPostDates
        case filters, hiddenPostIDs, metadata, collections, archive, readingCheckpoints
        case feedLastVisitedAt, collapsedCommentIDs, skippedPostDates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            exportedAt: try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date(),
            subscriptions: try container.decode([String].self, forKey: .subscriptions),
            savedPosts: try container.decode([RedditPost].self, forKey: .savedPosts),
            history: try container.decode([LocalHistoryEntry].self, forKey: .history),
            readPostDates: try container.decode([String: Date].self, forKey: .readPostDates),
            filters: try container.decode(LocalContentFilters.self, forKey: .filters),
            hiddenPostIDs: try container.decode(Set<String>.self, forKey: .hiddenPostIDs),
            metadata: try container.decode([String: LocalPostMetadata].self, forKey: .metadata),
            collections: try container.decode([LocalPostCollection].self, forKey: .collections),
            archive: try container.decode(LocalArchivePayload.self, forKey: .archive),
            readingCheckpoints: try container.decode([String: LocalReadingCheckpoint].self, forKey: .readingCheckpoints),
            feedLastVisitedAt: try container.decode([String: Date].self, forKey: .feedLastVisitedAt),
            collapsedCommentIDs: try container.decode(Set<String>.self, forKey: .collapsedCommentIDs),
            skippedPostDates: try container.decodeIfPresent([String: Date].self, forKey: .skippedPostDates) ?? [:]
        )
    }
}

struct EncryptedBackupPackage: Codable {
    let version: Int
    let salt: Data
    let sealedPayload: Data
}

enum LocalBackupCrypto {
    enum BackupError: LocalizedError {
        case emptyPassphrase
        case unsupportedVersion
        case invalidPackage

        var errorDescription: String? {
            switch self {
            case .emptyPassphrase: "Enter a backup passphrase."
            case .unsupportedVersion: "This backup version is not supported."
            case .invalidPackage: "The backup is damaged or the passphrase is incorrect."
            }
        }
    }

    static func encrypt(_ payload: LocalBackupPayload, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw BackupError.emptyPassphrase }
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let key = derivedKey(passphrase: passphrase, salt: salt)
        let encoded = try JSONEncoder.threadline.encode(payload)
        let sealed = try AES.GCM.seal(encoded, using: key)
        guard let combined = sealed.combined else { throw BackupError.invalidPackage }
        return try JSONEncoder.threadline.encode(
            EncryptedBackupPackage(version: 1, salt: salt, sealedPayload: combined)
        )
    }

    static func decrypt(_ data: Data, passphrase: String) throws -> LocalBackupPayload {
        guard !passphrase.isEmpty else { throw BackupError.emptyPassphrase }
        let package = try JSONDecoder.threadline.decode(EncryptedBackupPackage.self, from: data)
        guard package.version == 1 else { throw BackupError.unsupportedVersion }
        let key = derivedKey(passphrase: passphrase, salt: package.salt)
        do {
            let box = try AES.GCM.SealedBox(combined: package.sealedPayload)
            let plaintext = try AES.GCM.open(box, using: key)
            return try JSONDecoder.threadline.decode(LocalBackupPayload.self, from: plaintext)
        } catch {
            throw BackupError.invalidPackage
        }
    }

    private static func derivedKey(passphrase: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(passphrase.utf8)),
            salt: salt,
            info: Data("Threadline encrypted backup v1".utf8),
            outputByteCount: 32
        )
    }
}

extension JSONEncoder {
    fileprivate static var threadline: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var threadline: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

final class LocalArchiveDiskStore {
    private let fileURL: URL
    private let encoder = JSONEncoder.threadline
    private let decoder = JSONDecoder.threadline

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Threadline", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("offline-archive-v1.json")
    }

    func load() -> LocalArchivePayload {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? decoder.decode(LocalArchivePayload.self, from: data) else {
            return .init()
        }
        return payload
    }

    func save(_ payload: LocalArchivePayload) {
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

actor OfflineMediaCache {
    static let shared = OfflineMediaCache()

    func configure(limitMB: Int) {
        let bytes = max(50, min(limitMB, 1_000)) * 1_024 * 1_024
        URLCache.shared.diskCapacity = bytes
        URLCache.shared.memoryCapacity = min(bytes / 8, 64 * 1_024 * 1_024)
    }

    func prefetch(urls: [URL], lowDataMode: Bool) async {
        let candidates = urls.prefix(lowDataMode ? 3 : 12)
        for url in candidates {
            if lowDataMode, ["mp4", "m3u8", "mov"].contains(url.pathExtension.lowercased()) { continue }
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("Lyra/1.0 offline-cache", forHTTPHeaderField: "User-Agent")
            guard URLCache.shared.cachedResponse(for: request) == nil else { continue }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  data.count <= 25 * 1_024 * 1_024 else { continue }
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        }
    }

    func clear() {
        URLCache.shared.removeAllCachedResponses()
    }
}

enum LocalSearchField: String, Codable, Hashable {
    case title
    case body
    case author
    case subreddit
    case domain
    case flair
    case note
    case tags
    case comments
}

struct LocalSearchResult: Hashable, Identifiable {
    let post: RedditPost
    let matchedFields: Set<LocalSearchField>
    let score: Int
    var id: String { post.id }
}

enum LocalSearchEngine {
    static func search(
        query: String,
        posts: [RedditPost],
        metadata: [String: LocalPostMetadata],
        snapshots: [String: OfflinePostSnapshot]
    ) -> [LocalSearchResult] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { LocalContentFilters.normalized(String($0)) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        var seen = Set<String>()
        return posts.compactMap { post -> LocalSearchResult? in
            guard seen.insert(post.id).inserted else { return nil }
            let record = metadata[post.id]
            let snapshot = snapshots[post.id]
            let fields: [(LocalSearchField, String, Int)] = [
                (.title, post.title, 8),
                (.body, post.selftext, 4),
                (.author, post.author, 3),
                (.subreddit, post.subreddit, 5),
                (.domain, post.domain, 3),
                (.flair, post.linkFlairText ?? "", 3),
                (.note, record?.note ?? "", 6),
                (.tags, record?.tags.joined(separator: " ") ?? "", 6),
                (.comments, snapshot?.comments.flatMap(\.flattened).map(\.body).joined(separator: " ") ?? "", 2)
            ]

            var matches = Set<LocalSearchField>()
            var score = 0
            for (field, rawValue, weight) in fields {
                let value = LocalContentFilters.normalized(rawValue)
                let matchingTerms = terms.filter(value.contains)
                guard !matchingTerms.isEmpty else { continue }
                matches.insert(field)
                score += matchingTerms.count * weight
            }

            guard terms.allSatisfy({ term in
                fields.contains { LocalContentFilters.normalized($0.1).contains(term) }
            }) else { return nil }
            return LocalSearchResult(post: post, matchedFields: matches, score: score)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.post.createdUTC > $1.post.createdUTC
        }
    }
}
