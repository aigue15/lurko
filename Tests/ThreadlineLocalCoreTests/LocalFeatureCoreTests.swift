import XCTest
@testable import ThreadlineLocalCore

final class LocalFeatureCoreTests: XCTestCase {
    func testFiltersBlockMutedContentKindsAndDuplicateReposts() {
        var filters = LocalContentFilters()
        filters.mutedAuthors = ["muted-user"]
        filters.keywords = ["spoiler phrase"]
        filters.blockedPostKinds = [.video]
        filters.hideReposts = true

        let allowed = post(id: "1", title: "A useful Swift post", author: "alice")
        let muted = post(id: "2", title: "Anything", author: "Muted-User")
        let keyword = post(id: "3", title: "Contains SPOILER PHRASE", author: "bob")
        let video = post(id: "4", title: "A clip", author: "carol", isVideo: true)
        let repost = post(id: "5", title: allowed.title, author: "dave")

        XCTAssertEqual(filters.filtered([allowed, muted, keyword, video, repost]).map(\.id), ["1"])
    }

    func testLocalSearchFindsPostMetadataAndOfflineComments() {
        let saved = post(id: "saved", title: "Swift concurrency", author: "alice")
        let snapshot = OfflinePostSnapshot(
            post: saved,
            comments: [
                OfflineComment(
                    id: "comment",
                    author: "bob",
                    body: "Actors eliminate this race condition",
                    score: 8,
                    createdUTC: 1,
                    replies: []
                )
            ]
        )
        let metadata = LocalPostMetadata(postID: saved.id, note: "Review before the interview", tags: ["learning"])

        let results = LocalSearchEngine.search(
            query: "race condition",
            posts: [saved],
            metadata: [saved.id: metadata],
            snapshots: [saved.id: snapshot]
        )

        XCTAssertEqual(results.map(\.post.id), [saved.id])
        XCTAssertTrue(results[0].matchedFields.contains(.comments))
    }

    func testMetadataNormalizesTagsAndBoundsNotes() {
        let metadata = LocalPostMetadata(
            postID: "abc",
            note: String(repeating: "n", count: 5_000),
            tags: [" Swift ", "swift", "iOS", ""]
        ).cleaned()

        XCTAssertEqual(metadata.tags, ["ios", "swift"])
        XCTAssertEqual(metadata.note.count, LocalFeatureLimits.maximumNoteLength)
    }

    func testCommunityCatalogContainsAndSearchesTop200Snapshot() {
        XCTAssertEqual(CommunityCatalog.entries.count, 200)
        XCTAssertEqual(CommunityCatalog.entries.first?.name, "funny")

        let results = CommunityCatalog.search("r/apple")
        XCTAssertEqual(results.first?.name, "apple")
        XCTAssertEqual(results.first?.rank, 109)
    }

    func testRandomPopularSelectionIsUniqueAndHonorsExclusions() {
        let excluded = Set(CommunityCatalog.entries.prefix(192).map(\.id))
        let selection = CommunityCatalog.randomPopular(limit: 8, excluding: excluded)

        XCTAssertEqual(selection.count, 8)
        XCTAssertEqual(Set(selection.map(\.id)).count, 8)
        XCTAssertTrue(selection.allSatisfy { !excluded.contains($0.id) })
    }

    func testGalleryMediaPreservesMixedTypesAndCaptions() {
        let imageSource = RedditMediaSource(
            url: "https://i.redd.it/image.jpg",
            gif: nil,
            mp4: nil,
            width: 1200,
            height: 800
        )
        let videoSource = RedditMediaSource(
            url: nil,
            gif: nil,
            mp4: "https://v.redd.it/gallery-video.mp4",
            width: 720,
            height: 1280
        )
        let gallery = RedditPost(
            id: "gallery",
            title: "Mixed gallery",
            author: "alice",
            subreddit: "swift",
            permalink: "/r/swift/comments/gallery/",
            url: "https://www.reddit.com/gallery/gallery",
            galleryData: GalleryData(items: [
                GalleryItem(mediaID: "image", id: 1, caption: "A still", outboundURL: nil),
                GalleryItem(mediaID: "video", id: 2, caption: "A clip", outboundURL: "https://example.com")
            ]),
            mediaMetadata: [
                "image": RedditMediaMetadata(status: "valid", type: "Image", mimeType: "image/jpeg", source: imageSource, previews: nil),
                "video": RedditMediaMetadata(status: "valid", type: "RedditVideo", mimeType: "video/mp4", source: videoSource, previews: nil)
            ],
            isGallery: true
        )

        XCTAssertEqual(gallery.galleryMedia.map(\.kind), [.image, .video])
        XCTAssertEqual(gallery.galleryMedia.map(\.caption), ["A still", "A clip"])
        XCTAssertEqual(gallery.galleryMedia[0].aspectRatio, 1.5)
        XCTAssertTrue(gallery.mediaURLs.contains(URL(string: "https://v.redd.it/gallery-video.mp4")!))
    }

    func testEncryptedBackupRoundTripsAndRejectsWrongPassphrase() throws {
        let saved = post(id: "saved", title: "Private reading list", author: "alice")
        let payload = LocalBackupPayload(
            subscriptions: ["swift"],
            savedPosts: [saved],
            history: [],
            readPostDates: [saved.id: Date(timeIntervalSince1970: 1)],
            filters: LocalContentFilters(),
            hiddenPostIDs: [],
            metadata: [saved.id: LocalPostMetadata(postID: saved.id, tags: ["ios"])],
            collections: [],
            archive: LocalArchivePayload(),
            readingCheckpoints: [:],
            feedLastVisitedAt: [:],
            collapsedCommentIDs: [],
            skippedPostDates: [saved.id: Date(timeIntervalSince1970: 2)]
        )

        let encrypted = try LocalBackupCrypto.encrypt(payload, passphrase: "correct horse")
        XCTAssertFalse(encrypted.isEmpty)
        let restored = try LocalBackupCrypto.decrypt(encrypted, passphrase: "correct horse")
        XCTAssertEqual(restored.subscriptions, ["swift"])
        XCTAssertEqual(restored.savedPosts.map(\.id), [saved.id])
        XCTAssertEqual(restored.skippedPostDates[saved.id], Date(timeIntervalSince1970: 2))
        XCTAssertThrowsError(try LocalBackupCrypto.decrypt(encrypted, passphrase: "wrong"))
    }

    private func post(
        id: String,
        title: String,
        author: String,
        isVideo: Bool = false
    ) -> RedditPost {
        RedditPost(
            id: id,
            title: title,
            author: author,
            subreddit: "swift",
            permalink: "/r/swift/comments/\(id)/",
            url: isVideo ? "https://v.redd.it/\(id)" : "https://example.com/\(id)",
            postHint: isVideo ? "hosted:video" : "link",
            createdUTC: 1,
            isVideo: isVideo
        )
    }
}
