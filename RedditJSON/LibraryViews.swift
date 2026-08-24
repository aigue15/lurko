import SwiftUI

struct LibraryView: View {
    let client: RedditClient

    @Environment(LocalLibrary.self) private var library

    @State private var section: LibrarySection?
    @State private var destination: LibraryDestination?
    @State private var pendingClearAction: LibraryClearAction?
    @State private var editingPost: RedditPost?
    @State private var searchText = ""
    @State private var isCreatingCollection = false
    @State private var newCollectionName = ""

    init(client: RedditClient, startingSection: LibrarySection? = nil) {
        self.client = client
        _section = State(initialValue: startingSection)
    }

    var body: some View {
        Group {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                localSearchContent
            } else if let section {
                sectionContent(section)
            } else {
                libraryOverview
            }
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(section?.title ?? "Library")
        .searchable(text: $searchText, prompt: "Search your library")
        .onChange(of: section) {
            HapticFeedback.selection(enabled: library.hapticsEnabled)
        }
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .post(let post):
                PostDetailView(post: post, client: client)
            }
        }
        .toolbar {
            if section != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { section = nil }
                    } label: {
                        Label("Library", systemImage: "chevron.left")
                    }
                }
            }

            if section == .collections {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newCollectionName = ""
                        isCreatingCollection = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("New collection")
                }
            }

            if canClearCurrentSection {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pendingClearAction = section == .saved ? .saved : .history
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(section == .saved ? "Clear saved posts" : "Clear history")
                }
            }
        }
        .alert(item: $pendingClearAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text("Clear")) {
                    switch action {
                    case .saved:
                        library.clearSavedPosts()
                    case .history:
                        library.clearHistory()
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $editingPost) { post in
            PostLibraryEditorView(post: post)
        }
        .alert("New collection", isPresented: $isCreatingCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                library.addCollection(named: newCollectionName)
                newCollectionName = ""
            }
            .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Create a collection now, then add posts from their library actions.")
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: LibrarySection) -> some View {
        switch section {
        case .saved:
            savedContent
        case .queue:
            localPostList(
                library.queuedPosts,
                section: .queue,
                emptyTitle: "Reading queue is empty",
                emptyIcon: "text.badge.plus"
            )
        case .favorites:
            localPostList(
                library.favoritePosts,
                section: .favorites,
                emptyTitle: "No favorites yet",
                emptyIcon: "star"
            )
        case .collections:
            collectionsContent
        case .comments:
            savedCommentsContent
        case .history:
            historyContent
        }
    }

    private var libraryOverview: some View {
        Group {
            if visibleSections.isEmpty {
                libraryEmptyState(
                    title: "Your library is empty",
                    systemImage: "books.vertical",
                    message: "Save a post, or long-press one to add it to your queue, favorites, or a collection."
                )
            } else {
                List {
                    Section("Your library") {
                        ForEach(visibleSections) { section in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { self.section = section }
                            } label: {
                                LibrarySectionRow(section: section, count: count(for: section))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens \(section.title.lowercased())")
                        }
                    }

                    if !library.history.isEmpty {
                        Section("Recently viewed") {
                            ForEach(library.history.prefix(3)) { entry in
                                Button {
                                    destination = .post(entry.post)
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.post.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        HStack(spacing: 5) {
                                            Text("r/\(entry.post.subreddit)")
                                            Text("·")
                                            Text(entry.viewedAt, format: .relative(presentation: .named))
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var visibleSections: [LibrarySection] {
        LibrarySection.allCases.filter { count(for: $0) > 0 }
    }

    private func count(for section: LibrarySection) -> Int {
        switch section {
        case .saved: library.savedPosts.count
        case .queue: library.queuedPosts.count
        case .favorites: library.favoritePosts.count
        case .collections: nonemptySmartCollections.count + nonemptyCollections.count
        case .comments: library.savedComments.count
        case .history: library.history.count
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if library.savedPosts.isEmpty {
            libraryEmptyState(
                title: "Nothing saved yet",
                systemImage: "bookmark",
                message: "Save a post from its action bar and it will remain available here on this device."
            )
        } else {
            List {
                ForEach(library.savedPosts) { post in
                    Button {
                        destination = .post(post)
                    } label: {
                        PostRow(post: post)
                            .opacity(library.isRead(post) ? 0.68 : 1)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            library.toggleSaved(post)
                        } label: {
                            Label("Unsave", systemImage: "bookmark.slash")
                        }
                    }
                    .accessibilityLabel("Open saved post: \(post.title)")
                    .contextMenu {
                        Button { editingPost = post } label: {
                            Label("Edit local details", systemImage: "tag")
                        }
                        Button { library.toggleFavorite(post) } label: {
                            Label(library.isFavorite(post) ? "Remove Favorite" : "Favorite", systemImage: "star")
                        }
                        Button { library.toggleReadingQueue(post) } label: {
                            Label(library.isQueued(post) ? "Remove from Queue" : "Add to Queue", systemImage: "text.badge.plus")
                        }
                    }
                }
                .onDelete(perform: library.removeSavedPosts)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if library.history.isEmpty {
            libraryEmptyState(
                title: "No reading history",
                systemImage: "clock.arrow.circlepath",
                message: "Posts you open appear here so you can easily return to them. Your history never leaves this device."
            )
        } else {
            List {
                ForEach(library.history) { entry in
                    Button {
                        destination = .post(entry.post)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            PostRow(post: entry.post)
                                .opacity(0.72)

                            Label {
                                Text(entry.viewedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Open recently viewed post: \(entry.post.title)")
                }
                .onDelete(perform: library.removeHistory)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func localPostList(
        _ posts: [RedditPost],
        section: LibrarySection,
        emptyTitle: String,
        emptyIcon: String
    ) -> some View {
        Group {
            if posts.isEmpty {
                libraryEmptyState(title: emptyTitle, systemImage: emptyIcon, message: "Use a post’s local actions to add it here.")
            } else {
                List(posts) { post in
                    Button {
                        destination = .post(post)
                    } label: {
                        PostRow(post: post)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            remove(post, from: section)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button { editingPost = post } label: {
                            Label("Edit local details", systemImage: "tag")
                        }
                        Button { library.toggleFavorite(post) } label: {
                            Label(library.isFavorite(post) ? "Remove Favorite" : "Favorite", systemImage: "star")
                        }
                        Button { library.toggleReadingQueue(post) } label: {
                            Label(library.isQueued(post) ? "Remove from Queue" : "Add to Queue", systemImage: "text.badge.plus")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func remove(_ post: RedditPost, from section: LibrarySection) {
        switch section {
        case .queue:
            if library.isQueued(post) { library.toggleReadingQueue(post) }
        case .favorites:
            if library.isFavorite(post) { library.toggleFavorite(post) }
        case .saved:
            library.unsave(post)
        case .collections, .comments, .history:
            break
        }
    }

    @ViewBuilder
    private var savedCommentsContent: some View {
        let comments = library.savedComments.values.sorted {
            ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast)
        }

        if comments.isEmpty {
            libraryEmptyState(
                title: "No saved comments",
                systemImage: "text.bubble",
                message: "Save a useful comment from a post and it will appear here."
            )
        } else {
            List(comments) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("u/\(comment.author)")
                            .font(.caption.weight(.semibold))
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(comment.createdUTC.relativeRedditTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(comment.score.compactCount, systemImage: "arrow.up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(comment.body)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 6)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        library.removeSavedComment(id: comment.id)
                    } label: {
                        Label("Remove", systemImage: "bookmark.slash")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var collectionsContent: some View {
        Group {
            if nonemptySmartCollections.isEmpty && nonemptyCollections.isEmpty {
                libraryEmptyState(
                    title: "No populated collections",
                    systemImage: "folder",
                    message: "Long-press a post and choose Notes, Tags & Collections to add it to a collection."
                )
            } else {
                List {
                    if !nonemptySmartCollections.isEmpty {
                        Section("Smart collections") {
                            ForEach(nonemptySmartCollections) { collection in
                                NavigationLink("\(collection.title) (\(collection.posts.count.compactCount))") {
                                    LocalPostCollectionList(title: collection.title, posts: collection.posts, client: client)
                                }
                            }
                        }
                    }

                    if !nonemptyCollections.isEmpty {
                        Section("Your collections") {
                            ForEach(nonemptyCollections) { collection in
                                NavigationLink {
                                    LocalPostCollectionList(title: collection.name, posts: library.posts(in: collection), client: client)
                                } label: {
                                    LabeledContent(
                                        collection.name,
                                        value: library.posts(in: collection).count.compactCount
                                    )
                                }
                                .swipeActions {
                                    Button("Delete", role: .destructive) { library.deleteCollection(collection) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var nonemptyCollections: [LocalPostCollection] {
        library.collections.filter { !library.posts(in: $0).isEmpty }
    }

    private var nonemptySmartCollections: [LibrarySmartCollection] {
        [
            LibrarySmartCollection(title: "Unread saved", posts: library.unreadSavedPosts),
            LibrarySmartCollection(title: "Saved this week", posts: library.recentlySavedPosts),
            LibrarySmartCollection(
                title: "Videos",
                posts: library.savedPosts.filter { LocalPostKind(post: $0) == .video }
            ),
            LibrarySmartCollection(title: "Recently skipped", posts: library.recentlySkippedPosts)
        ]
        .filter { !$0.posts.isEmpty }
    }

    private var localSearchContent: some View {
        let results = library.localSearch(searchText)
        return Group {
            if results.isEmpty {
                libraryEmptyState(
                    title: "No local matches",
                    systemImage: "magnifyingglass",
                    message: "Search covers saved posts, history, cached comments, authors, communities, domains, notes, and tags."
                )
            } else {
                List(results) { result in
                    Button { destination = .post(result.post) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            PostRow(post: result.post)
                            Text(result.matchedFields.map(\.rawValue).sorted().joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func libraryEmptyState(title: String, systemImage: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }

    private var canClearCurrentSection: Bool {
        guard let section else { return false }
        return switch section {
        case .saved: !library.savedPosts.isEmpty
        case .history: !library.history.isEmpty
        case .queue, .favorites, .collections, .comments: false
        }
    }
}

struct SavedPostsView: View {
    let client: RedditClient

    var body: some View {
        LibraryView(client: client, startingSection: .saved)
    }
}

struct SettingsView: View {
    @Environment(LocalLibrary.self) private var library
    @State private var pendingAction: SettingsDestructiveAction?

    var body: some View {
        @Bindable var library = library

        Form {
            Section {
                Picker("Post layout", selection: $library.feedLayout) {
                    Text("Compact").tag(FeedLayout.compact)
                    Text("Comfortable").tag(FeedLayout.comfortable)
                    Text("Media").tag(FeedLayout.media)
                }
                .pickerStyle(.segmented)

                Picker("Default sort", selection: $library.defaultSort) {
                    ForEach(FeedSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
            } header: {
                Text("Browsing")
            } footer: {
                Text("Compact is the Apollo-style list. Comfortable and Media keep the same vote column with more room for text or images.")
            }

            Section("Content") {
                Toggle(isOn: $library.autoplayVideos) {
                    SettingsToggleLabel(
                        title: "Autoplay videos",
                        subtitle: "Play visible videos without sound",
                        systemImage: "play.rectangle"
                    )
                }

                Toggle(isOn: $library.muteVideosByDefault) {
                    SettingsToggleLabel(
                        title: "Mute videos by default",
                        subtitle: "Start native video playback without sound",
                        systemImage: "speaker.slash"
                    )
                }

                Toggle(isOn: $library.showNSFWContent) {
                    SettingsToggleLabel(
                        title: "Show NSFW posts",
                        subtitle: "Include mature public content",
                        systemImage: "eye"
                    )
                }

                Toggle(isOn: $library.blurNSFW) {
                    SettingsToggleLabel(
                        title: "Blur NSFW media",
                        subtitle: "Tap blurred media to reveal it",
                        systemImage: "drop.halffull"
                    )
                }
                .disabled(!library.showNSFWContent)

                Toggle(isOn: $library.blurSpoilers) {
                    SettingsToggleLabel(
                        title: "Blur spoilers",
                        subtitle: "Keep tagged media hidden until tapped",
                        systemImage: "eye.slash"
                    )
                }

                Toggle(isOn: $library.lowDataMode) {
                    SettingsToggleLabel(
                        title: "Low-data mode",
                        subtitle: "Avoid prefetching videos and limit offline media",
                        systemImage: "antenna.radiowaves.left.and.right.slash"
                    )
                }
            }

            Section("Local controls") {
                NavigationLink {
                    ContentFiltersView()
                } label: {
                    Label("Filters & Mutes", systemImage: "line.3.horizontal.decrease.circle")
                }

                NavigationLink {
                    LocalBackupView()
                } label: {
                    Label("Encrypted Backup", systemImage: "lock.doc")
                }
            }

            Section {
                Picker("Offline cache", selection: $library.offlineCacheLimitMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1_000)
                }

                Button("Clear downloaded media", role: .destructive) {
                    Task { await library.clearOfflineCache() }
                }
            } header: {
                Text("Offline reading")
            } footer: {
                Text("Saved posts retain their text, metadata, available comments, and cached media within this limit.")
            }

            Section("Interaction") {
                Toggle(isOn: $library.hapticsEnabled) {
                    SettingsToggleLabel(
                        title: "Haptic feedback",
                        subtitle: "Use subtle feedback for key actions",
                        systemImage: "waveform"
                    )
                }

                Toggle(isOn: $library.markPostsReadOnOpen) {
                    SettingsToggleLabel(
                        title: "Mark posts as read",
                        subtitle: "Dim posts after you open them",
                        systemImage: "checkmark.circle"
                    )
                }
            }

            Section {
                ForEach(RedditInterface.allCases) { interface in
                    Button {
                        HapticFeedback.selection(enabled: library.hapticsEnabled)
                        library.redditInterface = interface
                    } label: {
                        HStack(spacing: 12) {
                            Label(interface.title, systemImage: interface.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            if library.redditInterface == interface {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(library.redditInterface == interface ? .isSelected : [])
                }
            } header: {
                Text("Open Reddit links in")
            } footer: {
                Text(interfaceHelp)
            }

            Section("On this iPhone") {
                LabeledContent("Communities", value: library.subscriptions.count.compactCount)
                LabeledContent("Saved posts", value: library.savedPosts.count.compactCount)
                LabeledContent("History", value: library.history.count.compactCount)

                Button("Clear saved posts", role: .destructive) {
                    pendingAction = .saved
                }
                .disabled(library.savedPosts.isEmpty)

                Button("Clear reading history", role: .destructive) {
                    pendingAction = .history
                }
                .disabled(library.history.isEmpty && library.readPostIDs.isEmpty)

                Button("Reset browsing preferences") {
                    pendingAction = .preferences
                }
            }

            Section {
                PrivacyRow(
                    title: "No Reddit login",
                    detail: "Public communities are available without connecting an account.",
                    systemImage: "person.crop.circle.badge.xmark"
                )
                PrivacyRow(
                    title: "Local by design",
                    detail: "Subscriptions, saves, preferences, and history remain on this device.",
                    systemImage: "iphone"
                )
                PrivacyRow(
                    title: "Read-only access",
                    detail: "Posts and comments come from Reddit's public JSON data and anonymous public fallbacks.",
                    systemImage: "doc.text.magnifyingglass"
                )
            } header: {
                Text("Privacy")
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lyra")
                        .font(.subheadline.weight(.semibold))
                    Text("A focused, native Reddit reader in the spirit of Apollo. Independent and account-free. Not affiliated with Reddit, Inc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle("Settings")
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.buttonTitle)) {
                    switch action {
                    case .saved:
                        library.clearSavedPosts()
                    case .history:
                        library.clearBrowsingData()
                    case .preferences:
                        library.resetPreferences()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var interfaceHelp: String {
        switch library.redditInterface {
        case .browser:
            "Links open on reddit.com in your default browser."
        case .apollo:
            "Links try Apollo first, then fall back to your browser if it is unavailable."
        case .reddit:
            "Links try the official Reddit app first, then fall back to your browser if it is unavailable."
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "0.2"
    }
}

private struct LibrarySectionRow: View {
    let section: LibrarySection
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.body)
                .foregroundStyle(section.color)
                .frame(width: 26)

            Text(section.title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Text(count.compactCount)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct LibrarySmartCollection: Identifiable {
    let title: String
    let posts: [RedditPost]

    var id: String { title }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case saved
    case queue
    case favorites
    case collections
    case comments
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .saved: "Saved"
        case .queue: "Queue"
        case .favorites: "Favorites"
        case .collections: "Collections"
        case .comments: "Saved Comments"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .saved: "bookmark.fill"
        case .queue: "text.badge.plus"
        case .favorites: "star.fill"
        case .collections: "folder.fill"
        case .comments: "text.bubble.fill"
        case .history: "clock.arrow.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .saved: AppTheme.tint
        case .queue: .blue
        case .favorites: .orange
        case .collections: .indigo
        case .comments: .teal
        case .history: .gray
        }
    }
}

private enum LibraryDestination: Hashable {
    case post(RedditPost)
}

private enum LibraryClearAction: String, Identifiable {
    case saved
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .saved: "Clear saved posts?"
        case .history: "Clear reading history?"
        }
    }

    var message: String {
        switch self {
        case .saved: "Every locally saved post will be removed from this iPhone."
        case .history: "Your recently viewed posts will be removed from this iPhone."
        }
    }
}

private enum SettingsDestructiveAction: String, Identifiable {
    case saved
    case history
    case preferences

    var id: Self { self }

    var title: String {
        switch self {
        case .saved: "Clear saved posts?"
        case .history: "Clear reading history?"
        case .preferences: "Reset browsing preferences?"
        }
    }

    var message: String {
        switch self {
        case .saved:
            "Every locally saved post will be removed from this iPhone."
        case .history:
            "Recently viewed and read states will be removed from this iPhone."
        case .preferences:
            "Layout, content, haptic, and link-opening options will return to their defaults. Your communities and saved posts will remain."
        }
    }

    var buttonTitle: String {
        switch self {
        case .preferences: "Reset"
        case .saved, .history: "Clear"
        }
    }
}

private struct SettingsToggleLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.tint)
        }
    }
}

private struct PrivacyRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.tint)
        }
        .padding(.vertical, 3)
    }
}
