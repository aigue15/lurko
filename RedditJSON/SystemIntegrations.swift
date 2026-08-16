import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum ThreadlineSpotlight {
    static func refresh(posts: [RedditPost], metadata: [String: LocalPostMetadata]) async {
        let items = posts.prefix(1_000).map { post in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = post.title
            attributes.contentDescription = [post.selftext, metadata[post.id]?.note ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            attributes.keywords = [
                post.subreddit,
                post.author,
                post.domain,
                post.linkFlairText ?? ""
            ] + (metadata[post.id]?.tags ?? [])
            attributes.creator = "u/\(post.author)"
            attributes.contentURL = URL(string: "lurko://post/\(post.id)")
            return CSSearchableItem(
                uniqueIdentifier: "threadline.post.\(post.id)",
                domainIdentifier: "threadline.local-library",
                attributeSet: attributes
            )
        }

        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["threadline.local-library"])
            try await CSSearchableIndex.default().indexSearchableItems(items)
        } catch {
            // Spotlight is an optional system surface; the local library remains authoritative.
        }
    }
}

struct OpenThreadlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Lurko"
    static let description = IntentDescription("Open the private, account-free Reddit reader.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result(dialog: "Opening Lurko")
    }
}

struct OpenThreadlineLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Lurko Library"
    static let description = IntentDescription("Open your on-device reading library.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("library", forKey: "system.pending-destination.v1")
        return .result(dialog: "Opening your Lurko library")
    }
}

struct ThreadlineAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenThreadlineIntent(),
            phrases: ["Open \(.applicationName)", "Browse with \(.applicationName)"],
            shortTitle: "Open Lurko",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: OpenThreadlineLibraryIntent(),
            phrases: ["Open my \(.applicationName) library", "Continue reading in \(.applicationName)"],
            shortTitle: "Lurko Library",
            systemImageName: "books.vertical"
        )
    }
}
