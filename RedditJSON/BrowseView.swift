import SwiftUI

/// Apollo-inspired directory for anonymous feeds, local custom feeds, and subscriptions.
struct BrowseView: View {
    let client: RedditClient

    @Environment(LocalLibrary.self) private var library
    @State private var multireddits = LocalMultiredditStore()
    @State private var presentedEditor: MultiredditEditorDestination?
    @State private var pendingDeletion: LocalMultireddit?
    @State private var selectedIndexID: String?

    private var sortedSubscriptions: [String] {
        library.subscriptions.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var groupedSubscriptions: [(letter: String, names: [String])] {
        let groups = Dictionary(grouping: sortedSubscriptions) { name in
            guard let scalar = name.uppercased().unicodeScalars.first,
                  (65...90).contains(scalar.value) else { return "#" }
            return String(Character(scalar))
        }
        return groups
            .map { (letter: $0.key, names: $0.value) }
            .sorted { lhs, rhs in
                if lhs.letter == "#" { return false }
                if rhs.letter == "#" { return true }
                return lhs.letter < rhs.letter
            }
    }

    private var sortedMultireddits: [LocalMultireddit] {
        multireddits.feeds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var subscriptionDirectoryItems: [BrowseSubscriptionDirectoryItem] {
        groupedSubscriptions.flatMap { group in
            [.letter(group.letter)] + group.names.map(BrowseSubscriptionDirectoryItem.community)
        }
    }

    private var indexEntries: [BrowseIndexEntry] {
        [
            .symbol(id: "index-home", anchor: BrowseAnchor.home, image: "house.fill", name: "Home"),
            .symbol(id: "index-popular", anchor: BrowseAnchor.popular, image: "flame.fill", name: "Popular"),
            .symbol(id: "index-all", anchor: BrowseAnchor.all, image: "circle.grid.2x2.fill", name: "All"),
            .symbol(id: "index-multireddits", anchor: BrowseAnchor.multireddits, image: "square.stack.3d.up.fill", name: "Custom feeds")
        ] + groupedSubscriptions.map {
            .letter($0.letter, anchor: BrowseAnchor.letter($0.letter))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        feedsSection.padding(.bottom, 12)
                        multiredditsSection.padding(.bottom, 8)
                        subscriptionsSection
                    }
                    .padding(.leading, AppTheme.contentPadding)
                    .padding(.trailing, 28)
                    .padding(.vertical, 4)
                }
                .background(AppTheme.groupedBackground)

                BrowseIndexRail(entries: indexEntries, selectedID: selectedIndexID) { entry in
                    guard selectedIndexID != entry.id else { return }
                    selectedIndexID = entry.id
                    HapticFeedback.selection(enabled: library.hapticsEnabled)
                    proxy.scrollTo(entry.anchor, anchor: .top)
                } onInteractionEnded: {
                    selectedIndexID = nil
                }
            }
        }
        .navigationTitle("Communities")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        presentedEditor = .create
                    } label: {
                        Label("New Custom Feed", systemImage: "plus")
                    }

                    if !sortedMultireddits.isEmpty {
                        Menu {
                            ForEach(sortedMultireddits) { feed in
                                Button {
                                    presentedEditor = .edit(feed)
                                } label: {
                                    Label(feed.name, systemImage: "pencil")
                                }
                            }
                        } label: {
                            Label("Edit Custom Feed", systemImage: "pencil")
                        }
                    }
                } label: {
                    Label("Custom feed actions", systemImage: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("browse-create-custom-feed")
            }
        }
        .sheet(item: $presentedEditor) { destination in
            MultiredditEditorView(destination: destination, store: multireddits)
        }
        .alert(
            "Delete custom feed?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { feed in
            Button("Delete", role: .destructive) {
                multireddits.delete(feed)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { feed in
            Text("\u{201c}\(feed.name)\u{201d} will be removed from this device. Its communities will stay subscribed.")
        }
    }

    private var feedsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            BrowseSectionHeader(title: "Feeds")

            NavigationLink {
                HomeFeedView(client: client)
            } label: {
                BrowseDestinationRow(
                    title: "Home",
                    subtitle: "Posts from your subscriptions",
                    systemImage: "house.fill",
                    color: AppTheme.tint
                )
            }
            .buttonStyle(.plain)
            .id(BrowseAnchor.home)

            NavigationLink {
                CombinedFeedView(
                    title: "Popular",
                    subtitle: "What Reddit is talking about",
                    systemImage: "flame",
                    subreddits: ["popular"],
                    client: client
                )
            } label: {
                BrowseDestinationRow(
                    title: "Popular",
                    subtitle: "Trending across Reddit",
                    systemImage: "flame.fill",
                    color: .orange
                )
            }
            .buttonStyle(.plain)
            .id(BrowseAnchor.popular)

            NavigationLink {
                CombinedFeedView(
                    title: "All",
                    subtitle: "The widest public Reddit feed",
                    systemImage: "globe",
                    subreddits: ["all"],
                    client: client
                )
            } label: {
                BrowseDestinationRow(
                    title: "All",
                    subtitle: "Posts from all public communities",
                    systemImage: "circle.grid.2x2.fill",
                    color: .blue
                )
            }
            .buttonStyle(.plain)
            .id(BrowseAnchor.all)
        }
    }

    private var multiredditsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            BrowseSectionHeader(title: "Custom Feeds")
                .id(BrowseAnchor.multireddits)

            if sortedMultireddits.isEmpty {
                Button {
                    presentedEditor = .create
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.tint)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create a custom feed")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("Mix public communities into one timeline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the custom feed editor")
            } else {
                ForEach(sortedMultireddits) { feed in
                    NavigationLink {
                        CombinedFeedView(
                            title: feed.name,
                            subtitle: feed.subreddits.map { "r/\($0)" }.joined(separator: "  ·  "),
                            systemImage: "square.stack.3d.up.fill",
                            subreddits: feed.subreddits,
                            client: client
                        )
                    } label: {
                        BrowseDestinationRow(
                            title: feed.name,
                            subtitle: customFeedSubtitle(feed),
                            systemImage: "square.stack.3d.up.fill",
                            color: AppTheme.communityColor(feed.name)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            presentedEditor = .edit(feed)
                        } label: {
                            Label("Edit Custom Feed", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDeletion = feed
                        } label: {
                            Label("Delete Custom Feed", systemImage: "trash")
                        }
                    }
                    .accessibilityAction(named: "Edit Custom Feed") {
                        presentedEditor = .edit(feed)
                    }
                    .accessibilityAction(named: "Delete Custom Feed") {
                        pendingDeletion = feed
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionsSection: some View {
        if groupedSubscriptions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                BrowseSectionHeader(title: "Communities")
                ContentUnavailableView(
                    "No subscriptions yet",
                    systemImage: "person.2.badge.plus",
                    description: Text("Find a community in Search and join it locally.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        } else {
            ForEach(subscriptionDirectoryItems) { item in
                subscriptionDirectoryRow(item)
            }
        }
    }

    @ViewBuilder
    private func subscriptionDirectoryRow(_ item: BrowseSubscriptionDirectoryItem) -> some View {
        switch item {
        case .letter(let letter):
            Text(letter)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 26)
                .background(AppTheme.groupedBackground)
                .id(BrowseAnchor.letter(letter))

        case .community(let subreddit):
            NavigationLink {
                CommunityFeedView(subreddit: subreddit, client: client)
            } label: {
                HStack(spacing: 12) {
                    RedditCommunityAvatar(name: subreddit, client: client, size: 32)
                    Text("r/\(subreddit)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open r/\(subreddit)")
        }
    }

    private func customFeedSubtitle(_ feed: LocalMultireddit) -> String {
        let preview = feed.subreddits.prefix(3).map { "r/\($0)" }.joined(separator: " · ")
        let remainder = feed.subreddits.count - min(feed.subreddits.count, 3)
        return remainder > 0 ? "\(preview) +\(remainder)" : preview
    }
}

private enum BrowseAnchor {
    static let home = "browse-feed-home"
    static let popular = "browse-feed-popular"
    static let all = "browse-feed-all"
    static let multireddits = "browse-multireddits"

    static func letter(_ value: String) -> String { "browse-letter-\(value)" }
}

private enum BrowseSubscriptionDirectoryItem: Identifiable {
    case letter(String)
    case community(String)

    var id: String {
        switch self {
        case .letter(let value): "letter-\(value)"
        case .community(let value): "community-\(value)"
        }
    }
}

private struct BrowseSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
            .lineLimit(1)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}

private struct BrowseDestinationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this feed")
    }
}

private struct BrowseIndexEntry: Identifiable {
    enum Content {
        case symbol(String)
        case letter(String)
    }

    let id: String
    let anchor: String
    let content: Content
    let accessibilityName: String

    static func symbol(id: String, anchor: String, image: String, name: String) -> Self {
        Self(id: id, anchor: anchor, content: .symbol(image), accessibilityName: name)
    }

    static func letter(_ value: String, anchor: String) -> Self {
        Self(id: "index-letter-\(value)", anchor: anchor, content: .letter(value), accessibilityName: value)
    }
}

private struct BrowseIndexRail: View {
    let entries: [BrowseIndexEntry]
    let selectedID: String?
    let onSelectionChanged: (BrowseIndexEntry) -> Void
    let onInteractionEnded: () -> Void

    @State private var isDragging = false

    private let slotHeight: CGFloat = 20

    var body: some View {
        ZStack(alignment: .trailing) {
            if isDragging,
               let selected = entries.first(where: { $0.id == selectedID }) {
                Text(selected.accessibilityName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 30)
                    .background(AppTheme.tint, in: Capsule())
                    .offset(x: -38)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    Group {
                        switch entry.content {
                        case .symbol(let image):
                            Image(systemName: image)
                                .font(.system(size: 9, weight: .heavy))
                        case .letter(let value):
                            Text(value)
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .foregroundStyle(selectedID == entry.id ? AppTheme.tint : Color.primary.opacity(0.72))
                    .frame(width: 16, height: slotHeight)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: 44, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard !entries.isEmpty else { return }
                        isDragging = true
                        let rawIndex = Int(value.location.y / slotHeight)
                        let index = min(max(rawIndex, 0), entries.count - 1)
                        onSelectionChanged(entries[index])
                    }
                    .onEnded { _ in
                        isDragging = false
                        onInteractionEnded()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Browse index")
            .accessibilityValue(entries.first(where: { $0.id == selectedID })?.accessibilityName ?? "Home")
            .accessibilityHint("Swipe up or down to jump between feeds and community letters")
            .accessibilityAdjustableAction { direction in
                let current = entries.firstIndex(where: { $0.id == selectedID }) ?? 0
                let next: Int
                switch direction {
                case .increment: next = min(current + 1, entries.count - 1)
                case .decrement: next = max(current - 1, 0)
                @unknown default: return
                }
                guard entries.indices.contains(next) else { return }
                onSelectionChanged(entries[next])
            }
        }
        .frame(width: 44, height: CGFloat(entries.count) * slotHeight)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .animation(.easeOut(duration: 0.12), value: selectedID)
    }
}

private enum MultiredditEditorDestination: Identifiable {
    case create
    case edit(LocalMultireddit)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let feed): "edit-\(feed.id.uuidString)"
        }
    }

    var feed: LocalMultireddit? {
        if case .edit(let feed) = self { return feed }
        return nil
    }
}

private struct MultiredditEditorView: View {
    let destination: MultiredditEditorDestination
    let store: LocalMultiredditStore

    @Environment(LocalLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var subreddits: [String]
    @State private var newSubreddit = ""
    @State private var isConfirmingDeletion = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, subreddit }

    init(destination: MultiredditEditorDestination, store: LocalMultiredditStore) {
        self.destination = destination
        self.store = store
        _name = State(initialValue: destination.feed?.name ?? "")
        _subreddits = State(initialValue: destination.feed?.subreddits ?? [])
    }

    private var canSave: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanName.isEmpty && cleanName.count <= 40 && !subreddits.isEmpty
    }

    private var suggestions: [String] {
        library.subscriptions
            .filter { !subreddits.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("News, hobbies, favorites…", text: $name)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .subreddit }
                }

                Section {
                    HStack(spacing: 8) {
                        TextField("Add a subreddit", text: $newSubreddit)
                            .focused($focusedField, equals: .subreddit)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(addSubreddit)
                        Button(action: addSubreddit) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(normalizedNewSubreddit.isEmpty)
                        .accessibilityLabel("Add subreddit")
                    }

                    ForEach(subreddits, id: \.self) { subreddit in
                        HStack {
                            Label("r/\(subreddit)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.primary, AppTheme.tint)
                            Spacer()
                            Button(role: .destructive) {
                                subreddits.removeAll { $0 == subreddit }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove r/\(subreddit)")
                        }
                    }
                } header: {
                    Text("Communities")
                } footer: {
                    Text("Custom feeds are saved only on this device and never require a Reddit account.")
                }

                if !suggestions.isEmpty {
                    Section("Your Subscriptions") {
                        ForEach(suggestions, id: \.self) { subreddit in
                            Button {
                                subreddits.append(subreddit)
                                subreddits = LocalMultireddit.cleanedSubreddits(subreddits)
                            } label: {
                                HStack {
                                    Text("r/\(subreddit)")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus")
                                        .foregroundStyle(AppTheme.tint)
                                        .frame(width: 44, height: 44)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add r/\(subreddit)")
                        }
                    }
                }

                if destination.feed != nil {
                    Section {
                        Button(role: .destructive) {
                            focusedField = nil
                            isConfirmingDeletion = true
                        } label: {
                            Label("Delete Custom Feed", systemImage: "trash")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityHint("Permanently removes this local custom feed")
                    } footer: {
                        Text("Deleting a custom feed does not unsubscribe you from its communities.")
                    }
                }
            }
            .navigationTitle(destination.feed == nil ? "New Custom Feed" : "Edit Custom Feed")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if destination.feed == nil { focusedField = .name }
            }
            .alert("Delete custom feed?", isPresented: $isConfirmingDeletion) {
                Button("Delete", role: .destructive, action: deleteFeed)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\u{201c}\(destination.feed?.name ?? name)\u{201d} will be removed from this device. Its communities will stay subscribed.")
            }
        }
    }

    private var normalizedNewSubreddit: String {
        let value = newSubreddit.removingSubredditPrefix.redditNormalized
        guard value.count <= 21,
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return "" }
        return value
    }

    private func addSubreddit() {
        let value = normalizedNewSubreddit
        guard !value.isEmpty else { return }
        subreddits.append(value)
        subreddits = LocalMultireddit.cleanedSubreddits(subreddits)
        newSubreddit = ""
        HapticFeedback.selection(enabled: library.hapticsEnabled)
    }

    private func save() {
        guard canSave else { return }
        if let feed = destination.feed {
            store.update(feed, name: name, subreddits: subreddits)
        } else {
            store.create(name: name, subreddits: subreddits)
        }
        HapticFeedback.success(enabled: library.hapticsEnabled)
        dismiss()
    }

    private func deleteFeed() {
        guard let feed = destination.feed else { return }
        store.delete(feed)
        HapticFeedback.success(enabled: library.hapticsEnabled)
        dismiss()
    }
}

struct CombinedFeedView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let subreddits: [String]
    let client: RedditClient
    var presentsAsRoot = false

    @Environment(LocalLibrary.self) private var library
    @State private var sort: FeedSort = .hot
    @State private var posts: [RedditPost] = []
    @State private var communities: [String: RedditCommunity] = [:]
    @State private var cursors: [String: String] = [:]
    @State private var selectedPost: RedditPost?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadIssue: ContentLoadIssue?
    @State private var appliedPreferences = false
    @State private var scrollPosition: String?

    private var sources: [String] {
        LocalMultireddit.cleanedSubreddits(subreddits)
    }

    private var taskID: String {
        "\(sort.rawValue):\(sources.joined(separator: ",")):\(library.showNSFWContent)"
    }

    private var feedID: String { "feed:combined:\(title.redditNormalized)" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !presentsAsRoot {
                    header
                    Hairline()
                }

                if isLoading && posts.isEmpty {
                    LoadingFeedCards()
                } else if let loadIssue, posts.isEmpty {
                    LoadIssueView(issue: loadIssue) {
                        Task { await load(reset: true) }
                    }
                    .frame(minHeight: 340)
                    .padding(.horizontal, AppTheme.contentPadding)
                } else if posts.isEmpty {
                    ContentUnavailableView(
                        "No posts yet",
                        systemImage: "tray",
                        description: Text("Try another sort or pull down to refresh.")
                    )
                    .frame(minHeight: 340)
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
                            community: communities[post.subreddit.redditNormalized],
                            isNew: library.isNewSinceLastVisit(post, feedID: feedID)
                        ) {
                            open(post)
                        }
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
        .navigationTitle(title, enabled: !presentsAsRoot)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(sort: $sort)
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(post: post, client: client)
        }
        .refreshable { await load(reset: true) }
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
        .task(id: taskID) { await load(reset: true) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 12)
    }

    private func open(_ post: RedditPost) {
        library.recordViewed(post)
        HapticFeedback.impact(enabled: library.hapticsEnabled)
        selectedPost = post
    }

    private func load(reset: Bool) async {
        guard !isLoading, !sources.isEmpty else { return }
        isLoading = true
        if reset {
            cursors = [:]
            loadIssue = nil
        }
        defer { isLoading = false }

        let batch = await fetchPages(sources.map { ($0, nil as String?) })
        guard !Task.isCancelled else { return }
        if batch.pages.isEmpty {
            loadIssue = ContentLoadIssue.preferred(in: batch.issues)
            if posts.isEmpty { posts = cachedPosts }
            return
        }

        posts = library.filterPosts(mixed(batch.pages.map(\.posts), appendingTo: []))
        library.updateRecentPostsWidget(posts)
        cursors = Dictionary(uniqueKeysWithValues: batch.pages.compactMap { page in
            page.after.map { (page.subreddit, $0) }
        })
        // Aggregate endpoints such as Popular and All contain posts from many real
        // communities. Resolve those communities, not the synthetic endpoint name,
        // so their cards keep the same recognizable icons as the rest of the app.
        communities = await loadCommunities(metadataCommunityNames(for: posts))
    }

    private func loadMore() async {
        guard !isLoadingMore, !cursors.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let batch = await fetchPages(cursors.map { ($0.key, Optional($0.value)) })
        guard !Task.isCancelled else { return }
        guard !batch.pages.isEmpty else {
            loadIssue = ContentLoadIssue.preferred(in: batch.issues)
            return
        }
        posts = library.filterPosts(mixed(batch.pages.map(\.posts), appendingTo: posts))
        library.updateRecentPostsWidget(posts)
        for page in batch.pages {
            if let after = page.after { cursors[page.subreddit] = after }
            else { cursors.removeValue(forKey: page.subreddit) }
        }

        let missingNames = metadataCommunityNames(for: posts).filter {
            communities[$0.redditNormalized] == nil
        }
        if !missingNames.isEmpty {
            communities.merge(await loadCommunities(missingNames)) { current, _ in current }
        }
    }

    private func fetchPages(_ requests: [(String, String?)]) async -> BrowseFetchBatch {
        let activeSort = sort
        let client = client
        return await withTaskGroup(of: BrowseFetchResult.self, returning: BrowseFetchBatch.self) { group in
            for (subreddit, cursor) in requests {
                group.addTask {
                    do {
                        let page = try await client.posts(subreddit: subreddit, sort: activeSort, after: cursor)
                        return BrowseFetchResult(
                            page: BrowseSourcePage(subreddit: subreddit, posts: page.posts, after: page.after),
                            issue: nil
                        )
                    } catch {
                        return BrowseFetchResult(page: nil, issue: ContentLoadIssue(error: error))
                    }
                }
            }
            var pages: [BrowseSourcePage] = []
            var issues: [ContentLoadIssue] = []
            for await result in group {
                if let page = result.page { pages.append(page) }
                if let issue = result.issue { issues.append(issue) }
            }
            return BrowseFetchBatch(pages: pages, issues: issues)
        }
    }

    private var cachedPosts: [RedditPost] {
        let sourceNames = Set(sources.map(\.redditNormalized))
        let includesAggregate = !sourceNames.isDisjoint(with: ["popular", "all"])
        return library.filterPosts(library.allLocalPosts)
            .filter { includesAggregate || sourceNames.contains($0.subreddit.redditNormalized) }
            .sorted { $0.createdUTC > $1.createdUTC }
    }

    private func mixed(_ pages: [[RedditPost]], appendingTo existing: [RedditPost]) -> [RedditPost] {
        var unique = existing
        var known = Set(existing.map(\.id))
        let longest = pages.map(\.count).max() ?? 0
        for index in 0..<longest {
            for page in pages where page.indices.contains(index) {
                let post = page[index]
                if known.insert(post.id).inserted { unique.append(post) }
            }
        }

        switch sort {
        case .new:
            return Array(unique.sorted { $0.createdUTC > $1.createdUTC }.prefix(240))
        case .top:
            return Array(unique.sorted { $0.score > $1.score }.prefix(240))
        default:
            return Array(unique.prefix(240))
        }
    }

    private func loadCommunities(_ names: [String]) async -> [String: RedditCommunity] {
        let client = client
        return await withTaskGroup(of: RedditCommunity?.self, returning: [String: RedditCommunity].self) { group in
            for name in names where name != "popular" && name != "all" {
                group.addTask { try? await client.community(named: name) }
            }
            var result: [String: RedditCommunity] = [:]
            for await community in group {
                if let community { result[community.id] = community }
            }
            return result
        }
    }

    private func metadataCommunityNames(for posts: [RedditPost]) -> [String] {
        var seen = Set<String>()
        return (sources + posts.map(\.subreddit))
            .map { $0.removingSubredditPrefix.redditNormalized }
            .filter {
                $0 != "popular" && $0 != "all" && seen.insert($0).inserted
            }
            .prefix(24)
            .map(\.self)
    }
}

private struct BrowseSourcePage {
    let subreddit: String
    let posts: [RedditPost]
    let after: String?
}

private struct BrowseFetchResult: Sendable {
    let page: BrowseSourcePage?
    let issue: ContentLoadIssue?
}

private struct BrowseFetchBatch: Sendable {
    let pages: [BrowseSourcePage]
    let issues: [ContentLoadIssue]
}
