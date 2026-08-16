import SwiftUI
import UniformTypeIdentifiers

struct ContentFiltersView: View {
    @Environment(LocalLibrary.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Toggle("Hide NSFW posts", isOn: $library.contentFilters.hideNSFW)
                Toggle("Hide likely reposts", isOn: $library.contentFilters.hideReposts)
            } footer: {
                Text("Reposts are detected locally from normalized title and domain. Nothing is uploaded.")
            }

            Section("Post types") {
                ForEach(LocalPostKind.allCases) { kind in
                    Toggle(
                        "Block \(kind.title.lowercased())",
                        isOn: Binding(
                            get: { library.contentFilters.blockedPostKinds.contains(kind) },
                            set: { blocked in
                                if blocked { library.contentFilters.blockedPostKinds.insert(kind) }
                                else { library.contentFilters.blockedPostKinds.remove(kind) }
                            }
                        )
                    )
                }
            }

            FilterValueEditor(
                title: "Muted authors",
                placeholder: "username",
                prefix: "u/",
                values: valuesBinding(\.mutedAuthors)
            )
            FilterValueEditor(
                title: "Muted communities",
                placeholder: "subreddit",
                prefix: "r/",
                values: valuesBinding(\.mutedSubreddits)
            )
            FilterValueEditor(
                title: "Muted domains",
                placeholder: "example.com",
                values: valuesBinding(\.mutedDomains)
            )
            FilterValueEditor(
                title: "Blocked keywords",
                placeholder: "word or phrase",
                values: valuesBinding(\.keywords)
            )
            FilterValueEditor(
                title: "Muted flairs",
                placeholder: "flair text",
                values: valuesBinding(\.mutedFlairs)
            )

            if !library.hiddenPostIDs.isEmpty {
                Section {
                    LabeledContent("Individually hidden", value: library.hiddenPostIDs.count.compactCount)
                    Button("Unhide all posts", role: .destructive) {
                        library.clearHiddenPosts()
                    }
                }
            }
        }
        .navigationTitle("Filters & Mutes")
    }

    private func valuesBinding(_ keyPath: WritableKeyPath<LocalContentFilters, [String]>) -> Binding<[String]> {
        Binding(
            get: { library.contentFilters[keyPath: keyPath] },
            set: { values in
                library.contentFilters[keyPath: keyPath] = values
                library.contentFilters = library.contentFilters.cleaned()
            }
        )
    }
}

private struct FilterValueEditor: View {
    let title: String
    let placeholder: String
    var prefix = ""
    @Binding var values: [String]
    @State private var draft = ""

    var body: some View {
        Section(title) {
            HStack {
                TextField(placeholder, text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ForEach(values, id: \.self) { value in
                HStack {
                    Text("\(prefix)\(value)")
                    Spacer()
                    Button(role: .destructive) {
                        values.removeAll { $0 == value }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(value)")
                }
            }
        }
    }

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        values.append(value)
        draft = ""
    }
}

struct PostLibraryEditorView: View {
    let post: RedditPost

    @Environment(LocalLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var tagText = ""
    @State private var selectedCollections = Set<UUID>()
    @State private var newCollectionName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Favorite",
                        isOn: Binding(
                            get: { library.isFavorite(post) },
                            set: { _ in library.toggleFavorite(post) }
                        )
                    )
                    Toggle(
                        "Reading queue",
                        isOn: Binding(
                            get: { library.isQueued(post) },
                            set: { _ in library.toggleReadingQueue(post) }
                        )
                    )
                }

                Section("Note") {
                    TextEditor(text: $note)
                        .frame(minHeight: 110)
                }

                Section("Tags") {
                    TextField("swift, learning, reference", text: $tagText)
                        .textInputAutocapitalization(.never)
                    Text("Separate tags with commas. Search uses tags and notes locally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Collections") {
                    ForEach(library.collections) { collection in
                        Button {
                            if selectedCollections.contains(collection.id) {
                                selectedCollections.remove(collection.id)
                            } else {
                                selectedCollections.insert(collection.id)
                            }
                        } label: {
                            HStack {
                                Text(collection.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedCollections.contains(collection.id) {
                                    Image(systemName: "checkmark").foregroundStyle(AppTheme.tint)
                                }
                            }
                        }
                    }

                    HStack {
                        TextField("New collection", text: $newCollectionName)
                        Button("Add") {
                            library.addCollection(named: newCollectionName)
                            if let collection = library.collections.first(where: {
                                $0.name.caseInsensitiveCompare(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                            }) {
                                selectedCollections.insert(collection.id)
                            }
                            newCollectionName = ""
                        }
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Local Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.updateMetadata(
                            for: post,
                            note: note,
                            tags: tagText.split(separator: ",").map(String.init),
                            collectionIDs: Array(selectedCollections)
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                let metadata = library.metadata(for: post.id)
                note = metadata.note
                tagText = metadata.tags.joined(separator: ", ")
                selectedCollections = Set(metadata.collectionIDs)
            }
        }
    }
}

struct LocalBackupView: View {
    @Environment(LocalLibrary.self) private var library
    @State private var passphrase = ""
    @State private var backupDocument: ThreadlineBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                SecureField("Backup passphrase", text: $passphrase)
                    .textContentType(.newPassword)

                Button {
                    do {
                        backupDocument = ThreadlineBackupDocument(data: try library.encryptedBackup(passphrase: passphrase))
                        isExporting = true
                    } catch {
                        message = error.localizedDescription
                    }
                } label: {
                    Label("Export encrypted backup", systemImage: "lock.doc")
                }
                .disabled(passphrase.isEmpty)

                Button {
                    isImporting = true
                } label: {
                    Label("Import encrypted backup", systemImage: "square.and.arrow.down")
                }
                .disabled(passphrase.isEmpty)
            } footer: {
                Text("The passphrase never leaves this iPhone. It cannot be recovered if forgotten.")
            }

            Section("Included") {
                Text("Communities, custom library metadata, filters, saves, history, notes, tags, collections, offline snapshots, saved comments, and reading positions.")
            }
        }
        .navigationTitle("Private Backup")
        .fileExporter(
            isPresented: $isExporting,
            document: backupDocument,
            contentType: .threadlineBackup,
            defaultFilename: "Lurko-Backup"
        ) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
            else { message = "Encrypted backup exported." }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.threadlineBackup, .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try library.importEncryptedBackup(Data(contentsOf: url), passphrase: passphrase)
                message = "Backup imported."
            } catch {
                message = error.localizedDescription
            }
        }
        .alert("Private Backup", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

struct ThreadlineBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.threadlineBackup] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let threadlineBackup = UTType(exportedAs: "com.proof.threadline.encrypted-backup")
}

struct LocalPostCollectionList: View {
    let title: String
    let posts: [RedditPost]
    let client: RedditClient

    var body: some View {
        List(posts) { post in
            NavigationLink {
                PostDetailView(post: post, client: client)
            } label: {
                PostRow(post: post)
            }
            .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .overlay {
            if posts.isEmpty {
                ContentUnavailableView("No posts", systemImage: "tray")
            }
        }
    }
}

struct OfflineCommentThreadView: View {
    let comment: OfflineComment
    let depth: Int
    @Environment(LocalLibrary.self) private var library

    private var collapsed: Bool { library.isCommentCollapsed(comment.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                library.toggleCommentCollapsed(comment.id)
            } label: {
                HStack {
                    Text("u/\(comment.author)")
                        .font(.caption.weight(.semibold))
                    Text("· \(comment.createdUTC.relativeRedditTime)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(comment.score.compactCount, systemImage: "arrow.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: collapsed ? "plus.circle" : "minus.circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if !collapsed {
                Text(comment.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if !comment.replies.isEmpty, depth < 7 {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(comment.replies) {
                            OfflineCommentThreadView(comment: $0, depth: depth + 1)
                        }
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(AppTheme.tint.opacity(0.35)).frame(width: 2)
                    }
                }
            }
        }
        .padding(.vertical, 3)
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
        .id("offline-comment-\(comment.id)")
    }
}
