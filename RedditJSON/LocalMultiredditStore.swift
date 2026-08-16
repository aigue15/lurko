import Foundation
import Observation

/// A private, on-device collection of communities. It intentionally does not mirror or
/// synchronize Reddit account multireddits because Lurko does not require a login.
struct LocalMultireddit: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var subreddits: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        subreddits: [String],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subreddits = Self.cleanedSubreddits(subreddits)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func cleanedSubreddits(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.removingSubredditPrefix.redditNormalized }
            .filter { value in
                guard !value.isEmpty,
                      value.count <= 21,
                      value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                      seen.insert(value).inserted else { return false }
                return true
            }
            .prefix(200)
            .map(\.self)
    }
}

@MainActor
@Observable
final class LocalMultiredditStore {
    private enum Constants {
        static let storageKey = "local.multireddits.v1"
        static let feedLimit = 100
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    private(set) var feeds: [LocalMultireddit] {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Constants.storageKey),
           let decoded = try? decoder.decode([LocalMultireddit].self, from: data) {
            feeds = Self.cleanedFeeds(decoded)
        } else {
            feeds = []
        }
        persist()
    }

    @discardableResult
    func create(name: String, subreddits: [String]) -> LocalMultireddit? {
        let feed = LocalMultireddit(name: name, subreddits: subreddits)
        guard Self.isValid(feed) else { return nil }
        feeds.append(feed)
        feeds = Self.cleanedFeeds(feeds)
        return feed
    }

    func update(_ feed: LocalMultireddit, name: String, subreddits: [String]) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        let updated = LocalMultireddit(
            id: feed.id,
            name: name,
            subreddits: subreddits,
            createdAt: feed.createdAt,
            updatedAt: Date()
        )
        guard Self.isValid(updated) else { return }
        feeds[index] = updated
        feeds = Self.cleanedFeeds(feeds)
    }

    func delete(_ feed: LocalMultireddit) {
        feeds.removeAll { $0.id == feed.id }
    }

    private func persist() {
        guard let data = try? encoder.encode(feeds) else { return }
        defaults.set(data, forKey: Constants.storageKey)
    }

    private static func cleanedFeeds(_ values: [LocalMultireddit]) -> [LocalMultireddit] {
        var seenIDs = Set<UUID>()
        return values
            .map {
                LocalMultireddit(
                    id: $0.id,
                    name: $0.name,
                    subreddits: $0.subreddits,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
            .filter { isValid($0) && seenIDs.insert($0.id).inserted }
            .prefix(Constants.feedLimit)
            .map(\.self)
    }

    private static func isValid(_ feed: LocalMultireddit) -> Bool {
        !feed.name.isEmpty && feed.name.count <= 40 && !feed.subreddits.isEmpty
    }
}
