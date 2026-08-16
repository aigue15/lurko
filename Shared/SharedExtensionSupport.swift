import Foundation

enum ThreadlineSharedStore {
    static let appGroup = "group.com.proof.RedditJSON"
    private static let pendingLinksKey = "shared.pending-links.v1"
    private static let widgetItemsKey = "shared.widget-items.v1"
    private static let recentWidgetItemsKey = "shared.recent-widget-items.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func enqueue(_ link: SharedSavedLink) {
        var links = pendingLinks()
        links.removeAll { $0.url == link.url }
        links.insert(link, at: 0)
        defaults.set(try? JSONEncoder().encode(Array(links.prefix(100))), forKey: pendingLinksKey)
    }

    static func takePendingLinks() -> [SharedSavedLink] {
        let links = pendingLinks()
        defaults.removeObject(forKey: pendingLinksKey)
        return links
    }

    static func writeWidgetItems(_ items: [SharedWidgetItem]) {
        defaults.set(try? JSONEncoder().encode(Array(items.prefix(8))), forKey: widgetItemsKey)
    }

    static func widgetItems() -> [SharedWidgetItem] {
        guard let data = defaults.data(forKey: widgetItemsKey),
              let items = try? JSONDecoder().decode([SharedWidgetItem].self, from: data) else {
            return []
        }
        return items
    }

    static func writeRecentWidgetItems(_ items: [SharedWidgetItem]) {
        defaults.set(try? JSONEncoder().encode(Array(items.prefix(8))), forKey: recentWidgetItemsKey)
    }

    static func recentWidgetItems() -> [SharedWidgetItem] {
        guard let data = defaults.data(forKey: recentWidgetItemsKey),
              let items = try? JSONDecoder().decode([SharedWidgetItem].self, from: data) else {
            return []
        }
        return items
    }

    private static func pendingLinks() -> [SharedSavedLink] {
        guard let data = defaults.data(forKey: pendingLinksKey),
              let links = try? JSONDecoder().decode([SharedSavedLink].self, from: data) else {
            return []
        }
        return links
    }
}

struct SharedSavedLink: Codable, Hashable {
    let url: URL
    let title: String
    let savedAt: Date

    init(url: URL, title: String = "", savedAt: Date = Date()) {
        self.url = url
        self.title = title
        self.savedAt = savedAt
    }
}

struct SharedWidgetItem: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let subreddit: String
    let queued: Bool
}
