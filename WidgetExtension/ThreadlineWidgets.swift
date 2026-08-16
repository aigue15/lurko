import SwiftUI
import WidgetKit

struct ThreadlineQueueEntry: TimelineEntry {
    let date: Date
    let items: [SharedWidgetItem]
}

struct ThreadlineQueueProvider: TimelineProvider {
    let recent: Bool

    func placeholder(in context: Context) -> ThreadlineQueueEntry {
        ThreadlineQueueEntry(
            date: Date(),
            items: [SharedWidgetItem(id: "preview", title: "Your reading queue", subreddit: "lurko", queued: true)]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ThreadlineQueueEntry) -> Void) {
        completion(ThreadlineQueueEntry(date: Date(), items: items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThreadlineQueueEntry>) -> Void) {
        let entry = ThreadlineQueueEntry(date: Date(), items: items)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private var items: [SharedWidgetItem] {
        recent ? ThreadlineSharedStore.recentWidgetItems() : ThreadlineSharedStore.widgetItems()
    }
}

struct ThreadlineQueueWidget: Widget {
    let kind = "ThreadlineQueueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ThreadlineQueueProvider(recent: false)) { entry in
            ThreadlineListWidgetView(entry: entry, title: "Lurko", emptyText: "Your reading queue is empty")
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "lurko://library"))
        }
        .configurationDisplayName("Lurko Queue")
        .description("Continue your private on-device reading queue.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ThreadlineNewPostsWidget: Widget {
    let kind = "ThreadlineNewPostsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ThreadlineQueueProvider(recent: true)) { entry in
            ThreadlineListWidgetView(entry: entry, title: "New posts", emptyText: "Open a feed to refresh")
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "lurko://browse"))
        }
        .configurationDisplayName("Lurko New Posts")
        .description("See the newest posts from your most recently refreshed feed.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ThreadlineListWidgetView: View {
    let entry: ThreadlineQueueEntry
    let title: String
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: "books.vertical.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            if entry.items.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("r/\(item.subreddit)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

@main
struct ThreadlineWidgetBundle: WidgetBundle {
    var body: some Widget {
        ThreadlineQueueWidget()
        ThreadlineNewPostsWidget()
    }
}
