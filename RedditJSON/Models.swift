import Foundation

struct ListingEnvelope: Decodable {
    let data: ListingData
}

struct ArchivePostEnvelope: Decodable {
    let data: [RedditPost]
}

struct ArchiveCommentEnvelope: Decodable {
    let data: [RedditComment]
}

struct ArchiveCommunityEnvelope: Decodable {
    let data: [RedditCommunity]
}

struct CommunityAboutEnvelope: Decodable {
    let data: RedditCommunity
}

struct ListingData: Decodable {
    let children: [PostChild]
    let after: String?
}

struct PostChild: Decodable {
    let data: RedditPost
}

enum RedditDataSource: String, Codable, Sendable {
    case redditJSON
    case redditHTML
    case archive
}

struct RedditPostPage {
    let posts: [RedditPost]
    let after: String?
    let source: RedditDataSource
}

struct RedditCommunityPage {
    let communities: [RedditCommunity]
    let after: String?
    let source: RedditDataSource
}

struct RedditPost: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let subreddit: String
    let selftext: String
    var score: Int
    var numComments: Int
    let permalink: String
    let url: String
    let thumbnail: String?
    let postHint: String?
    let createdUTC: TimeInterval
    let isVideo: Bool
    let spoiler: Bool
    let over18: Bool
    let secureMedia: SecureMedia?
    let media: SecureMedia?
    let preview: Preview?
    let galleryData: GalleryData?
    let mediaMetadata: [String: RedditMediaMetadata]?
    let crosspostParentList: [RedditPost]?
    let linkFlairText: String?
    let authorFlairText: String?
    let upvoteRatio: Double?
    let totalAwardsReceived: Int?
    let subredditSubscribers: Int?
    let isSelf: Bool
    let isGallery: Bool
    let stickied: Bool
    let locked: Bool
    let distinguished: String?
    let name: String?
    let subredditID: String?

    enum CodingKeys: String, CodingKey {
        case id, title, author, subreddit, selftext, score, permalink, url, thumbnail, spoiler, media
        case numComments = "num_comments"
        case postHint = "post_hint"
        case createdUTC = "created_utc"
        case isVideo = "is_video"
        case over18 = "over_18"
        case secureMedia = "secure_media"
        case preview
        case galleryData = "gallery_data"
        case mediaMetadata = "media_metadata"
        case crosspostParentList = "crosspost_parent_list"
        case linkFlairText = "link_flair_text"
        case authorFlairText = "author_flair_text"
        case upvoteRatio = "upvote_ratio"
        case totalAwardsReceived = "total_awards_received"
        case subredditSubscribers = "subreddit_subscribers"
        case isSelf = "is_self"
        case isGallery = "is_gallery"
        case stickied, locked, distinguished, name
        case subredditID = "subreddit_id"
    }

    init(
        id: String,
        title: String,
        author: String,
        subreddit: String,
        selftext: String = "",
        score: Int = 0,
        numComments: Int = 0,
        permalink: String,
        url: String,
        thumbnail: String? = nil,
        postHint: String? = nil,
        createdUTC: TimeInterval = 0,
        isVideo: Bool = false,
        spoiler: Bool = false,
        over18: Bool = false,
        secureMedia: SecureMedia? = nil,
        media: SecureMedia? = nil,
        preview: Preview? = nil,
        galleryData: GalleryData? = nil,
        mediaMetadata: [String: RedditMediaMetadata]? = nil,
        crosspostParentList: [RedditPost]? = nil,
        linkFlairText: String? = nil,
        authorFlairText: String? = nil,
        upvoteRatio: Double? = nil,
        totalAwardsReceived: Int? = nil,
        subredditSubscribers: Int? = nil,
        isSelf: Bool = false,
        isGallery: Bool = false,
        stickied: Bool = false,
        locked: Bool = false,
        distinguished: String? = nil,
        name: String? = nil,
        subredditID: String? = nil
    ) {
        self.id = id.removingRedditThingPrefix
        self.title = title
        self.author = author
        self.subreddit = subreddit.removingSubredditPrefix
        self.selftext = selftext
        self.score = score
        self.numComments = numComments
        self.permalink = permalink
        self.url = url
        self.thumbnail = thumbnail
        self.postHint = postHint
        self.createdUTC = createdUTC
        self.isVideo = isVideo
        self.spoiler = spoiler
        self.over18 = over18
        self.secureMedia = secureMedia
        self.media = media
        self.preview = preview
        self.galleryData = galleryData
        self.mediaMetadata = mediaMetadata
        self.crosspostParentList = crosspostParentList
        self.linkFlairText = linkFlairText
        self.authorFlairText = authorFlairText
        self.upvoteRatio = upvoteRatio
        self.totalAwardsReceived = totalAwardsReceived
        self.subredditSubscribers = subredditSubscribers
        self.isSelf = isSelf
        self.isGallery = isGallery
        self.stickied = stickied
        self.locked = locked
        self.distinguished = distinguished
        self.name = name
        self.subredditID = subredditID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)
        id = (decodedID ?? decodedName ?? UUID().uuidString).removingRedditThingPrefix
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled post"
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "[deleted]"
        subreddit = (try container.decodeIfPresent(String.self, forKey: .subreddit) ?? "unknown").removingSubredditPrefix
        selftext = try container.decodeIfPresent(String.self, forKey: .selftext) ?? ""
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        numComments = try container.decodeIfPresent(Int.self, forKey: .numComments) ?? 0
        permalink = try container.decodeIfPresent(String.self, forKey: .permalink)
            ?? "/r/\(subreddit)/comments/\(id)/"
        url = try container.decodeIfPresent(String.self, forKey: .url)
            ?? "https://www.reddit.com\(permalink)"
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        postHint = try container.decodeIfPresent(String.self, forKey: .postHint)
        createdUTC = try container.decodeIfPresent(TimeInterval.self, forKey: .createdUTC) ?? 0
        isVideo = try container.decodeIfPresent(Bool.self, forKey: .isVideo) ?? false
        spoiler = try container.decodeIfPresent(Bool.self, forKey: .spoiler) ?? false
        over18 = try container.decodeIfPresent(Bool.self, forKey: .over18) ?? false
        secureMedia = (try? container.decodeIfPresent(SecureMedia.self, forKey: .secureMedia)) ?? nil
        media = (try? container.decodeIfPresent(SecureMedia.self, forKey: .media)) ?? nil
        preview = (try? container.decodeIfPresent(Preview.self, forKey: .preview)) ?? nil
        galleryData = (try? container.decodeIfPresent(GalleryData.self, forKey: .galleryData)) ?? nil
        mediaMetadata = (try? container.decodeIfPresent([String: RedditMediaMetadata].self, forKey: .mediaMetadata)) ?? nil
        crosspostParentList = (try? container.decodeIfPresent([RedditPost].self, forKey: .crosspostParentList)) ?? nil
        linkFlairText = try container.decodeIfPresent(String.self, forKey: .linkFlairText)
        authorFlairText = try container.decodeIfPresent(String.self, forKey: .authorFlairText)
        upvoteRatio = try container.decodeIfPresent(Double.self, forKey: .upvoteRatio)
        totalAwardsReceived = try container.decodeIfPresent(Int.self, forKey: .totalAwardsReceived)
        subredditSubscribers = try container.decodeIfPresent(Int.self, forKey: .subredditSubscribers)
        isSelf = try container.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
        isGallery = try container.decodeIfPresent(Bool.self, forKey: .isGallery) ?? (galleryData != nil)
        stickied = try container.decodeIfPresent(Bool.self, forKey: .stickied) ?? false
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        distinguished = try container.decodeIfPresent(String.self, forKey: .distinguished)
        name = decodedName
        subredditID = try container.decodeIfPresent(String.self, forKey: .subredditID)
    }

    var redditURL: URL? { URL(string: "https://www.reddit.com\(permalink)") }

    var externalURL: URL? { URL(string: url.htmlDecoded) }

    var videoURL: URL? {
        let redditVideo = secureMedia?.redditVideo
            ?? media?.redditVideo
            ?? preview?.redditVideoPreview
        let raw = redditVideo?.hlsURL
            ?? redditVideo?.fallbackURL
            ?? crosspostParentList?.first?.videoURL?.absoluteString
        if let raw, let url = URL(string: raw.htmlDecoded) { return url }

        guard let externalURL,
              let resource = ExternalMediaClassifier.immediateResource(for: externalURL),
              resource.kind == .video else { return nil }
        return resource.mediaURL
    }

    var galleryImageURLs: [URL] {
        galleryMedia.compactMap { item in
            switch item.kind {
            case .image, .animatedImage: item.url
            case .video: item.posterURL
            }
        }
    }

    var galleryMedia: [RedditGalleryMedia] {
        guard let galleryData, let mediaMetadata else { return [] }
        return galleryData.items.compactMap { item in
            guard let metadata = mediaMetadata[item.mediaID],
                  let source = metadata.source else { return nil }

            let mimeType = metadata.mimeType?.lowercased() ?? ""
            let metadataType = metadata.type?.lowercased() ?? ""
            let isAnimated = mimeType == "image/gif" || metadataType == "animatedimage"
            let isVideo = mimeType.hasPrefix("video/") || (!isAnimated && source.mp4 != nil)
            let kind: RedditGalleryMedia.Kind = isVideo ? .video : (isAnimated ? .animatedImage : .image)

            let rawURL: String?
            switch kind {
            case .video:
                rawURL = source.mp4 ?? source.url ?? source.gif
            case .animatedImage:
                rawURL = source.gif ?? source.mp4 ?? source.url
            case .image:
                rawURL = source.url ?? source.gif ?? source.mp4
            }

            guard let rawURL, let url = URL(string: rawURL.htmlDecoded) else { return nil }
            let posterURL = metadata.previews?.last.flatMap { preview in
                (preview.url ?? preview.gif).flatMap { URL(string: $0.htmlDecoded) }
            } ?? (kind == .video ? source.url.flatMap { URL(string: $0.htmlDecoded) } : nil)

            return RedditGalleryMedia(
                id: item.mediaID,
                url: url,
                posterURL: posterURL,
                kind: kind,
                caption: item.caption?.htmlDecoded,
                outboundURL: item.outboundURL.flatMap { URL(string: $0.htmlDecoded) },
                width: source.width,
                height: source.height
            )
        }
    }

    var imageURL: URL? {
        if let firstGalleryImage = galleryImageURLs.first { return firstGalleryImage }
        if let externalURL,
           let resource = ExternalMediaClassifier.immediateResource(for: externalURL),
           resource.kind == .image || resource.kind == .animatedImage {
            return resource.mediaURL
        }
        if let raw = preview?.images.first?.source.url,
           let previewURL = URL(string: raw.htmlDecoded) {
            return previewURL
        }
        return crosspostParentList?.first?.imageURL
    }

    var thumbnailURL: URL? {
        guard let thumbnail,
              let url = URL(string: thumbnail.htmlDecoded),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else { return nil }
        return url
    }

    var mediaURLs: [URL] {
        var urls = galleryMedia.flatMap { [$0.url, $0.posterURL].compactMap { $0 } }
        if let imageURL, !urls.contains(imageURL) { urls.append(imageURL) }
        if let videoURL, !urls.contains(videoURL) { urls.append(videoURL) }
        return urls
    }

    var domain: String {
        externalURL?.host?.replacingOccurrences(of: "www.", with: "") ?? "reddit.com"
    }

    var hasSupportedExternalMedia: Bool {
        externalURL.map(ExternalMediaClassifier.isSupportedSource) ?? false
    }
}

struct RedditGalleryMedia: Identifiable, Hashable {
    enum Kind: Hashable {
        case image
        case animatedImage
        case video
    }

    let id: String
    let url: URL
    let posterURL: URL?
    let kind: Kind
    let caption: String?
    let outboundURL: URL?
    let width: Int?
    let height: Int?

    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
}

enum ExternalMediaKind: String, Hashable, Sendable {
    case image
    case animatedImage
    case video
    case embed
}

enum ExternalMediaProvider: String, Hashable, Sendable {
    case direct
    case imgur
    case redGIFs
    case giphy
    case tenor
    case streamable
    case youtube
    case vimeo
    case reddit

    var title: String {
        switch self {
        case .direct: "Media"
        case .imgur: "Imgur"
        case .redGIFs: "RedGIFs"
        case .giphy: "GIPHY"
        case .tenor: "Tenor"
        case .streamable: "Streamable"
        case .youtube: "YouTube"
        case .vimeo: "Vimeo"
        case .reddit: "Reddit"
        }
    }
}

struct ExternalMediaResource: Identifiable, Hashable, Sendable {
    let mediaURL: URL
    let originalURL: URL
    let posterURL: URL?
    let kind: ExternalMediaKind
    let provider: ExternalMediaProvider
    let loops: Bool

    var id: String { "\(kind.rawValue):\(mediaURL.absoluteString)" }
}

/// URL-only media recognition. This deliberately supports a small allowlist of
/// stable URL shapes and keeps the original URL available whenever a provider
/// changes its delivery format.
enum ExternalMediaClassifier {
    private static let imageExtensions = Set(["jpg", "jpeg", "png", "webp", "heic", "avif", "bmp", "tif", "tiff"])
    private static let videoExtensions = Set(["mp4", "m4v", "mov", "m3u8"])

    static func isSupportedSource(_ url: URL) -> Bool {
        immediateResource(for: url) != nil || provider(for: url) != nil
    }

    static func immediateResource(for url: URL) -> ExternalMediaResource? {
        guard isWebURL(url) else { return nil }
        let host = normalizedHost(url)
        let pathExtension = url.pathExtension.lowercased()
        let sourceProvider = Self.provider(for: url) ?? .direct

        if pathExtension == "gifv", host == "imgur.com" || host == "i.imgur.com" {
            let mp4URL = url.deletingPathExtension().appendingPathExtension("mp4")
            return ExternalMediaResource(
                mediaURL: mp4URL,
                originalURL: url,
                posterURL: url.deletingPathExtension().appendingPathExtension("jpg"),
                kind: .video,
                provider: .imgur,
                loops: true
            )
        }

        if pathExtension == "gif" || pathExtension == "apng" {
            return ExternalMediaResource(
                mediaURL: url,
                originalURL: url,
                posterURL: nil,
                kind: .animatedImage,
                provider: sourceProvider,
                loops: true
            )
        }

        if imageExtensions.contains(pathExtension) {
            return ExternalMediaResource(
                mediaURL: url,
                originalURL: url,
                posterURL: nil,
                kind: .image,
                provider: sourceProvider,
                loops: false
            )
        }

        if videoExtensions.contains(pathExtension) {
            return ExternalMediaResource(
                mediaURL: url,
                originalURL: url,
                posterURL: nil,
                kind: .video,
                provider: sourceProvider,
                loops: false
            )
        }

        if ["webm", "ogv", "ogg"].contains(pathExtension) {
            return ExternalMediaResource(
                mediaURL: url,
                originalURL: url,
                posterURL: nil,
                kind: .embed,
                provider: sourceProvider,
                loops: false
            )
        }

        if let giphyID = giphyIdentifier(from: url),
           let gifURL = URL(string: "https://media.giphy.com/media/\(giphyID)/giphy.gif") {
            return ExternalMediaResource(
                mediaURL: gifURL,
                originalURL: url,
                posterURL: nil,
                kind: .animatedImage,
                provider: .giphy,
                loops: true
            )
        }

        if let embedURL = embedURL(for: url),
           let embeddedProvider = Self.provider(for: url),
           embeddedProvider != .imgur,
           embeddedProvider != .redGIFs {
            return ExternalMediaResource(
                mediaURL: embedURL,
                originalURL: url,
                posterURL: nil,
                kind: .embed,
                provider: embeddedProvider,
                loops: false
            )
        }

        return nil
    }

    static func provider(for url: URL) -> ExternalMediaProvider? {
        let host = normalizedHost(url)
        if host == "imgur.com" || host == "i.imgur.com" || host.hasSuffix(".imgur.com") { return .imgur }
        if host == "redgifs.com" || host.hasSuffix(".redgifs.com") { return .redGIFs }
        if host == "giphy.com" || host.hasSuffix(".giphy.com") { return .giphy }
        if host == "tenor.com" || host.hasSuffix(".tenor.com") { return .tenor }
        if host == "streamable.com" || host.hasSuffix(".streamable.com") { return .streamable }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" { return .youtube }
        if host == "vimeo.com" || host.hasSuffix(".vimeo.com") { return .vimeo }
        if host == "reddit.com" || host.hasSuffix(".reddit.com") {
            let components = url.pathComponents.map { $0.lowercased() }
            if components.contains("video") && components.contains("player") { return .reddit }
        }
        return nil
    }

    static func imgurIdentifier(from url: URL) -> String? {
        guard provider(for: url) == .imgur else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let first = components.first else { return nil }
        let reserved = Set(["a", "gallery", "t", "r", "user"])
        guard !reserved.contains(first.lowercased()), components.count == 1 else { return nil }
        let identifier = first.split(separator: ".", maxSplits: 1).first.map(String.init) ?? first
        return identifier.range(of: #"^[A-Za-z0-9]{5,}$"#, options: .regularExpression) == nil ? nil : identifier
    }

    static func redGIFIdentifier(from url: URL) -> String? {
        guard provider(for: url) == .redGIFs else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let markerIndex = components.firstIndex(where: { ["watch", "ifr"].contains($0.lowercased()) }),
              components.indices.contains(markerIndex + 1) else { return nil }
        let identifier = components[markerIndex + 1]
        return identifier.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) == nil ? nil : identifier
    }

    static func redGIFEmbedResource(for url: URL) -> ExternalMediaResource? {
        guard let identifier = redGIFIdentifier(from: url),
              let embedURL = URL(string: "https://www.redgifs.com/ifr/\(identifier)?controls=1") else { return nil }
        return ExternalMediaResource(
            mediaURL: embedURL,
            originalURL: url,
            posterURL: nil,
            kind: .embed,
            provider: .redGIFs,
            loops: true
        )
    }

    private static func giphyIdentifier(from url: URL) -> String? {
        guard provider(for: url) == .giphy else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        if let mediaIndex = components.firstIndex(where: { $0.lowercased() == "media" }),
           components.indices.contains(mediaIndex + 1) {
            return components[mediaIndex + 1]
        }
        guard let last = components.last else { return nil }
        let candidate = last.split(separator: "-").last.map(String.init) ?? last
        return candidate.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) == nil ? nil : candidate
    }

    private static func embedURL(for url: URL) -> URL? {
        guard let provider = Self.provider(for: url) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }

        switch provider {
        case .giphy:
            guard let identifier = giphyIdentifier(from: url) else { return nil }
            return URL(string: "https://giphy.com/embed/\(identifier)")
        case .tenor:
            guard let last = components.last,
                  let identifier = last.split(separator: "-").last,
                  identifier.allSatisfy(\.isNumber) else { return nil }
            return URL(string: "https://tenor.com/embed/\(identifier)")
        case .streamable:
            guard let identifier = components.first, !identifier.isEmpty else { return nil }
            return URL(string: "https://streamable.com/e/\(identifier)")
        case .youtube:
            let host = normalizedHost(url)
            var identifier: String?
            if host == "youtu.be" {
                identifier = components.first
            } else if let index = components.firstIndex(where: { ["shorts", "embed"].contains($0.lowercased()) }),
                      components.indices.contains(index + 1) {
                identifier = components[index + 1]
            } else {
                identifier = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            }
            guard let identifier,
                  identifier.range(of: #"^[A-Za-z0-9_-]{6,}$"#, options: .regularExpression) != nil else { return nil }
            return URL(string: "https://www.youtube-nocookie.com/embed/\(identifier)?playsinline=1")
        case .vimeo:
            guard let identifier = components.last, identifier.allSatisfy(\.isNumber) else { return nil }
            return URL(string: "https://player.vimeo.com/video/\(identifier)")
        case .reddit:
            return url
        case .imgur, .redGIFs, .direct:
            return nil
        }
    }

    private static func normalizedHost(_ url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }
}

actor ExternalMediaResolver {
    static let shared = ExternalMediaResolver()

    private let session: URLSession
    private var redGIFToken: String?
    private var redGIFTokenDate: Date?
    private var resolvedResources: [URL: ExternalMediaResource] = [:]
    private var unsupportedSources: Set<URL> = []

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json, image/*, video/*;q=0.9, */*;q=0.5",
            "User-Agent": "Lurko/1.0 (anonymous Reddit media reader)"
        ]
        session = URLSession(configuration: configuration)
    }

    func resolve(_ sourceURL: URL) async -> ExternalMediaResource? {
        if let immediate = ExternalMediaClassifier.immediateResource(for: sourceURL) { return immediate }
        if let cached = resolvedResources[sourceURL] { return cached }
        if unsupportedSources.contains(sourceURL) { return nil }

        let resolved: ExternalMediaResource?
        switch ExternalMediaClassifier.provider(for: sourceURL) {
        case .imgur:
            resolved = await resolveImgurPage(sourceURL)
        case .redGIFs:
            resolved = await resolveRedGIF(sourceURL) ?? ExternalMediaClassifier.redGIFEmbedResource(for: sourceURL)
        default:
            resolved = nil
        }

        if let resolved { resolvedResources[sourceURL] = resolved }
        else { unsupportedSources.insert(sourceURL) }
        return resolved
    }

    private func resolveImgurPage(_ sourceURL: URL) async -> ExternalMediaResource? {
        guard let identifier = ExternalMediaClassifier.imgurIdentifier(from: sourceURL) else { return nil }

        if let videoURL = URL(string: "https://i.imgur.com/\(identifier).mp4"),
           await hasExpectedContent(at: videoURL, prefix: "video/") {
            return ExternalMediaResource(
                mediaURL: videoURL,
                originalURL: sourceURL,
                posterURL: URL(string: "https://i.imgur.com/\(identifier).jpg"),
                kind: .video,
                provider: .imgur,
                loops: true
            )
        }

        guard let imageURL = URL(string: "https://i.imgur.com/\(identifier).jpg"),
              await hasExpectedContent(at: imageURL, prefix: "image/") else { return nil }
        return ExternalMediaResource(
            mediaURL: imageURL,
            originalURL: sourceURL,
            posterURL: nil,
            kind: .image,
            provider: .imgur,
            loops: false
        )
    }

    private func resolveRedGIF(_ sourceURL: URL) async -> ExternalMediaResource? {
        guard let identifier = ExternalMediaClassifier.redGIFIdentifier(from: sourceURL) else { return nil }

        do {
            let token = try await temporaryRedGIFToken()
            guard let endpoint = URL(string: "https://api.redgifs.com/v2/gifs/\(identifier)") else { return nil }
            var request = URLRequest(url: endpoint)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            let payload = try JSONDecoder().decode(RedGIFResponse.self, from: data)
            guard let rawVideoURL = payload.gif.urls.hd ?? payload.gif.urls.sd,
                  let videoURL = URL(string: rawVideoURL.htmlDecoded) else { return nil }
            let posterURL = (payload.gif.urls.poster ?? payload.gif.urls.thumbnail)
                .flatMap { URL(string: $0.htmlDecoded) }
            return ExternalMediaResource(
                mediaURL: videoURL,
                originalURL: sourceURL,
                posterURL: posterURL,
                kind: .video,
                provider: .redGIFs,
                loops: true
            )
        } catch {
            return nil
        }
    }

    private func temporaryRedGIFToken() async throws -> String {
        if let redGIFToken, let redGIFTokenDate,
           Date().timeIntervalSince(redGIFTokenDate) < 9 * 60 {
            return redGIFToken
        }

        guard let endpoint = URL(string: "https://api.redgifs.com/v2/auth/temporary") else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: endpoint)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.userAuthenticationRequired)
        }
        let payload = try JSONDecoder().decode(RedGIFTokenResponse.self, from: data)
        redGIFToken = payload.token
        redGIFTokenDate = Date()
        return payload.token
    }

    private func hasExpectedContent(at url: URL, prefix: String) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<400 ~= http.statusCode,
                  let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else { return false }
            return contentType.hasPrefix(prefix)
        } catch {
            return false
        }
    }
}

private struct RedGIFTokenResponse: Decodable {
    let token: String
}

private struct RedGIFResponse: Decodable {
    let gif: RedGIFPayload
}

private struct RedGIFPayload: Decodable {
    let urls: RedGIFURLs
}

private struct RedGIFURLs: Decodable {
    let hd: String?
    let sd: String?
    let poster: String?
    let thumbnail: String?
}

struct PostEngagement: Sendable {
    let score: Int
    let commentCount: Int
}

struct SecureMedia: Codable, Hashable {
    let redditVideo: RedditVideo?

    enum CodingKeys: String, CodingKey {
        case redditVideo = "reddit_video"
    }
}

struct RedditVideo: Codable, Hashable {
    let fallbackURL: String?
    let dashURL: String?
    let hlsURL: String?
    let height: Int?
    let width: Int?
    let duration: Int?
    let hasAudio: Bool?

    enum CodingKeys: String, CodingKey {
        case fallbackURL = "fallback_url"
        case dashURL = "dash_url"
        case hlsURL = "hls_url"
        case height, width, duration
        case hasAudio = "has_audio"
    }
}

struct Preview: Codable, Hashable {
    let images: [PreviewImage]
    let redditVideoPreview: RedditVideo?

    enum CodingKeys: String, CodingKey {
        case images
        case redditVideoPreview = "reddit_video_preview"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        images = try container.decodeIfPresent([PreviewImage].self, forKey: .images) ?? []
        redditVideoPreview = try container.decodeIfPresent(RedditVideo.self, forKey: .redditVideoPreview)
    }
}

struct PreviewImage: Codable, Hashable {
    let source: PreviewSource
    let resolutions: [PreviewSource]?
    let variants: [String: PreviewVariant]?
}

struct PreviewVariant: Codable, Hashable {
    let source: PreviewSource?
    let resolutions: [PreviewSource]?
}

struct PreviewSource: Codable, Hashable {
    let url: String
    let width: Int?
    let height: Int?
}

struct GalleryData: Codable, Hashable {
    let items: [GalleryItem]
}

struct GalleryItem: Codable, Hashable {
    let mediaID: String
    let id: Int?
    let caption: String?
    let outboundURL: String?

    enum CodingKeys: String, CodingKey {
        case mediaID = "media_id"
        case id, caption
        case outboundURL = "outbound_url"
    }
}

struct RedditMediaMetadata: Codable, Hashable {
    let status: String?
    let type: String?
    let mimeType: String?
    let source: RedditMediaSource?
    let previews: [RedditMediaSource]?

    enum CodingKeys: String, CodingKey {
        case status
        case type = "e"
        case mimeType = "m"
        case source = "s"
        case previews = "p"
    }
}

struct RedditMediaSource: Codable, Hashable {
    let url: String?
    let gif: String?
    let mp4: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case url = "u"
        case gif, mp4
        case width = "x"
        case height = "y"
    }
}

struct CommunityListing: Decodable {
    let data: CommunityListingData
}

struct CommunityListingData: Decodable {
    let children: [CommunityChild]
    let after: String?
}

struct CommunityChild: Decodable {
    let data: RedditCommunity
}

struct RedditCommunity: Decodable, Identifiable, Hashable {
    let displayName: String
    let title: String
    let publicDescription: String
    let subscribers: Int?
    let iconImg: String?
    let communityIcon: String?
    let bannerImg: String?
    let bannerBackgroundImage: String?
    let over18: Bool
    let createdUTC: TimeInterval?
    let url: String?
    let primaryColor: String?
    let keyColor: String?
    let activeUserCount: Int?

    var id: String { displayName.redditNormalized }

    var iconURL: URL? {
        [communityIcon, iconImg]
            .compactMap { $0 }
            .lazy
            .compactMap { URL(string: $0.htmlDecoded) }
            .first
    }

    var bannerURL: URL? {
        [bannerBackgroundImage, bannerImg]
            .compactMap { $0 }
            .lazy
            .compactMap { URL(string: $0.htmlDecoded) }
            .first
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case title
        case publicDescription = "public_description"
        case subscribers
        case iconImg = "icon_img"
        case communityIcon = "community_icon"
        case bannerImg = "banner_img"
        case bannerBackgroundImage = "banner_background_image"
        case over18
        case createdUTC = "created_utc"
        case url
        case primaryColor = "primary_color"
        case keyColor = "key_color"
        case activeUserCount = "active_user_count"
    }

    init(
        displayName: String,
        title: String,
        publicDescription: String,
        subscribers: Int?,
        iconImg: String?,
        over18: Bool,
        communityIcon: String? = nil,
        bannerImg: String? = nil,
        bannerBackgroundImage: String? = nil,
        createdUTC: TimeInterval? = nil,
        url: String? = nil,
        primaryColor: String? = nil,
        keyColor: String? = nil,
        activeUserCount: Int? = nil
    ) {
        self.displayName = displayName.removingSubredditPrefix
        self.title = title
        self.publicDescription = publicDescription
        self.subscribers = subscribers
        self.iconImg = iconImg
        self.communityIcon = communityIcon
        self.bannerImg = bannerImg
        self.bannerBackgroundImage = bannerBackgroundImage
        self.over18 = over18
        self.createdUTC = createdUTC
        self.url = url
        self.primaryColor = primaryColor
        self.keyColor = keyColor
        self.activeUserCount = activeUserCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = (try container.decodeIfPresent(String.self, forKey: .displayName) ?? "unknown")
            .removingSubredditPrefix
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "r/\(displayName)"
        publicDescription = try container.decodeIfPresent(String.self, forKey: .publicDescription) ?? ""
        subscribers = try container.decodeIfPresent(Int.self, forKey: .subscribers)
        iconImg = try container.decodeIfPresent(String.self, forKey: .iconImg)
        communityIcon = try container.decodeIfPresent(String.self, forKey: .communityIcon)
        bannerImg = try container.decodeIfPresent(String.self, forKey: .bannerImg)
        bannerBackgroundImage = try container.decodeIfPresent(String.self, forKey: .bannerBackgroundImage)
        over18 = try container.decodeIfPresent(Bool.self, forKey: .over18) ?? false
        createdUTC = try container.decodeIfPresent(TimeInterval.self, forKey: .createdUTC)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        primaryColor = try container.decodeIfPresent(String.self, forKey: .primaryColor)
        keyColor = try container.decodeIfPresent(String.self, forKey: .keyColor)
        activeUserCount = try container.decodeIfPresent(Int.self, forKey: .activeUserCount)
    }
}

// Snapshot derived from FarhanAli97/Reddit-Top-200-Communities (2024-11-28),
// distributed under Apache-2.0:
// https://github.com/FarhanAli97/Reddit-Top-200-Communities
struct CatalogCommunity: Identifiable, Hashable {
    let rank: Int
    let name: String
    let subscribers: Int

    var id: String { name.redditNormalized }

    var redditCommunity: RedditCommunity {
        RedditCommunity(
            displayName: name,
            title: "r/\(name)",
            publicDescription: "Popular community from the bundled catalog.",
            subscribers: subscribers,
            iconImg: nil,
            over18: false
        )
    }
}

enum CommunityCatalog {
    static let sourceURL = URL(string: "https://github.com/FarhanAli97/Reddit-Top-200-Communities")!

    static let entries: [CatalogCommunity] = rawRows
        .split(separator: "\n")
        .compactMap { row in
            let fields = row.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let rank = Int(fields[0]),
                  let subscribers = Int(fields[2]) else { return nil }
            return CatalogCommunity(rank: rank, name: String(fields[1]), subscribers: subscribers)
        }

    static func search(_ query: String, limit: Int = 25) -> [CatalogCommunity] {
        let term = query.removingSubredditPrefix.redditNormalized
        guard !term.isEmpty else { return [] }

        return entries
            .filter { $0.id.contains(term) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.id.hasPrefix(term)
                let rhsPrefix = rhs.id.hasPrefix(term)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.rank < rhs.rank
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    static func randomPopular(
        limit: Int = 8,
        excluding excludedNames: Set<String> = []
    ) -> [CatalogCommunity] {
        guard limit > 0 else { return [] }
        return entries
            .filter { !excludedNames.contains($0.id) }
            .shuffled()
            .prefix(limit)
            .map { $0 }
    }

    private static let rawRows = """
    1|funny|65310000
    2|AskReddit|49290000
    3|gaming|44430000
    4|worldnews|42850000
    5|todayilearned|38720000
    6|aww|37170000
    7|Music|35320000
    8|memes|35010000
    9|movies|33970000
    10|Showerthoughts|33250000
    11|science|33180000
    12|pics|31230000
    13|Jokes|30220000
    14|news|28990000
    15|space|27010000
    16|videos|26820000
    17|askscience|25900000
    18|DIY|25700000
    19|books|25420000
    20|nottheonion|25080000
    21|mildlyinteresting|24130000
    22|food|24060000
    23|EarthPorn|23700000
    24|GetMotivated|23410000
    25|explainlikeimfive|22960000
    26|gadgets|22720000
    27|LifeProTips|22720000
    28|IAmA|22520000
    29|Art|22380000
    30|gifs|21600000
    31|sports|21560000
    32|dataisbeautiful|21320000
    33|Futurology|21060000
    34|Documentaries|20360000
    35|UpliftingNews|20110000
    36|personalfinance|20080000
    37|photoshopbattles|20070000
    38|WritingPrompts|18680000
    39|tifu|18610000
    40|OldSchoolCool|18610000
    41|history|18280000
    42|Damnthatsinteresting|18270000
    43|philosophy|18130000
    44|nosleep|18040000
    45|listentothis|17980000
    46|wholesomememes|17720000
    47|technology|17420000
    48|television|17400000
    49|wallstreetbets|16120000
    50|InternetIsBeautiful|14990000
    51|NatureIsFuckingLit|14880000
    52|creepy|14610000
    53|relationship_advice|14050000
    54|lifehacks|13860000
    55|nba|13770000
    56|pcmasterrace|12950000
    57|interestingasfuck|12580000
    58|ContagiousLaughter|12330000
    59|travel|12060000
    60|Fitness|11980000
    61|HistoryMemes|11900000
    62|dadjokes|11750000
    63|anime|11590000
    64|oddlysatisfying|11140000
    65|Unexpected|11050000
    66|nfl|10760000
    67|NetflixBestOf|10700000
    68|EatCheapAndHealthy|10630000
    69|MadeMeSmile|9950000
    70|AdviceAnimals|9610000
    71|tattoos|9040000
    72|CryptoCurrency|8700000
    73|mildlyinfuriating|8680000
    74|politics|8410000
    75|BeAmazed|8380000
    76|AnimalsBeingDerps|8230000
    77|FoodPorn|8220000
    78|facepalm|8090000
    79|ChatGPT|7900000
    80|Minecraft|7900000
    81|europe|7880000
    82|soccer|7780000
    83|leagueoflegends|7750000
    84|Parenting|7630000
    85|PS5|7570000
    86|WatchPeopleDieInside|7550000
    87|rarepuppers|7490000
    88|buildapc|7440000
    89|NintendoSwitch|7410000
    90|gardening|7340000
    91|FunnyAnimals|7330000
    92|Bitcoin|7330000
    93|cats|7090000
    94|itookapicture|7020000
    95|cars|6890000
    96|AnimalsBeingBros|6630000
    97|programming|6560000
    98|AnimalsBeingJerks|6490000
    99|CozyPlaces|6470000
    100|HumansBeingBros|6470000
    101|MakeupAddiction|6280000
    102|starterpacks|5990000
    103|malefashionadvice|5940000
    104|Tinder|5930000
    105|Overwatch|5910000
    106|Frugal|5900000
    107|Awwducational|5860000
    108|nevertellmetheodds|5860000
    109|apple|5790000
    110|socialskills|5650000
    111|coolguides|5640000
    112|woodworking|5550000
    113|PS4|5540000
    114|entertainment|5530000
    115|dating|5520000
    116|foodhacks|5510000
    117|nutrition|5460000
    118|femalefashionadvice|5450000
    119|CrappyDesign|5450000
    120|photography|5430000
    121|YouShouldKnow|5430000
    122|nasa|5430000
    123|drawing|5340000
    124|bestof|5280000
    125|FortNiteBR|5240000
    126|technicallythetruth|5210000
    127|ModernWarfareII|5170000
    128|MealPrepSunday|5130000
    129|NoStupidQuestions|5120000
    130|TravelHacks|5120000
    131|Sneakers|5110000
    132|pokemongo|5090000
    133|backpacking|5070000
    134|boardgames|5060000
    135|trippinthroughtime|5050000
    136|anime_irl|5040000
    137|battlestations|5000000
    138|Outdoors|4900000
    139|MapPorn|4890000
    140|Economics|4870000
    141|biology|4870000
    142|streetwear|4840000
    143|Survival|4830000
    144|Shoestring|4810000
    145|OnePiece|4730000
    146|camping|4610000
    147|BikiniBottomTwitter|4590000
    148|strength_training|4590000
    149|pettyrevenge|4580000
    150|PremierLeague|4570000
    151|dating_advice|4550000
    152|pokemon|4550000
    153|slowcooking|4410000
    154|formula1|4400000
    155|HomeImprovement|4390000
    156|unpopularopinion|4360000
    157|Steam|4350000
    158|Eyebleach|4350000
    159|popculturechat|4320000
    160|marvelstudios|4320000
    161|unitedkingdom|4270000
    162|scifi|4270000
    163|SkincareAddiction|4230000
    164|Entrepreneur|4220000
    165|bodyweightfitness|4220000
    166|careerguidance|4180000
    167|homeautomation|4160000
    168|Daytrading|4150000
    169|woahdude|4150000
    170|hardware|4140000
    171|learnprogramming|4140000
    172|MovieDetails|4110000
    173|Cooking|4110000
    174|psychology|4100000
    175|solotravel|4090000
    176|MaliciousCompliance|4080000
    177|CFB|4070000
    178|MyPeopleNeedMe|4060000
    179|IdiotsInCars|4040000
    180|iphone|4000000
    181|ProgrammerHumor|3980000
    182|loseit|3950000
    183|marvelmemes|3950000
    184|Design|3930000
    185|Fauxmoi|3910000
    186|HighQualityGifs|3890000
    187|DnD|3880000
    188|Hair|3870000
    189|spaceporn|3830000
    190|reactiongifs|3800000
    191|comicbooks|3770000
    192|StarWars|3750000
    193|Eldenring|3740000
    194|keto|3740000
    195|compsci|3730000
    196|ThriftStoreHauls|3720000
    197|changemyview|3710000
    198|roadtrip|3700000
    199|standupshots|3700000
    200|Fantasy|3670000
    """
}

final class RedditComment: Decodable, Identifiable {
    let id: String
    let author: String
    let body: String
    let score: Int
    let createdUTC: TimeInterval
    var replies: [RedditComment]
    let parentID: String?
    let linkID: String?
    let depth: Int?
    let permalink: String?
    let stickied: Bool
    let distinguished: String?
    let editedUTC: TimeInterval?
    let bodyHTML: String?
    let mediaMetadata: [String: RedditMediaMetadata]?
    let inlineMediaURLs: [URL]
    let displayBody: String

    var isEdited: Bool { editedUTC != nil }

    enum CodingKeys: String, CodingKey {
        case id, author, body, score, replies, depth, permalink, stickied, distinguished, edited
        case createdUTC = "created_utc"
        case parentID = "parent_id"
        case linkID = "link_id"
        case bodyHTML = "body_html"
        case mediaMetadata = "media_metadata"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString)
            .removingRedditThingPrefix
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "[deleted]"
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        bodyHTML = try container.decodeIfPresent(String.self, forKey: .bodyHTML)
        mediaMetadata = (try? container.decodeIfPresent([String: RedditMediaMetadata].self, forKey: .mediaMetadata)) ?? nil
        inlineMediaURLs = CommentMediaParser.mediaURLs(
            body: body,
            bodyHTML: bodyHTML,
            metadata: mediaMetadata
        )
        displayBody = CommentMediaParser.displayBody(from: body)
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        createdUTC = try container.decodeIfPresent(TimeInterval.self, forKey: .createdUTC) ?? 0
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        linkID = try container.decodeIfPresent(String.self, forKey: .linkID)
        depth = try container.decodeIfPresent(Int.self, forKey: .depth)
        permalink = try container.decodeIfPresent(String.self, forKey: .permalink)
        stickied = try container.decodeIfPresent(Bool.self, forKey: .stickied) ?? false
        distinguished = try container.decodeIfPresent(String.self, forKey: .distinguished)
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .edited) {
            editedUTC = timestamp
        } else if (try? container.decode(Bool.self, forKey: .edited)) == true {
            editedUTC = createdUTC
        } else {
            editedUTC = nil
        }

        if let listing = try? container.decode(CommentListingEnvelope.self, forKey: .replies) {
            replies = listing.data.children.compactMap(\.data)
        } else {
            replies = []
        }
    }
}

private enum CommentMediaParser {
    static func mediaURLs(
        body: String,
        bodyHTML: String?,
        metadata: [String: RedditMediaMetadata]?
    ) -> [URL] {
        var candidates: [URL] = []

        for key in metadata?.keys.sorted() ?? [] {
            guard let item = metadata?[key] else { continue }
            let isAnimated = item.mimeType?.lowercased() == "image/gif" || item.type?.lowercased() == "animatedimage"
            let rawURL: String?
            if isAnimated {
                rawURL = item.source?.gif ?? item.source?.mp4 ?? item.source?.url
                    ?? item.previews?.last?.gif ?? item.previews?.last?.url
            } else if item.mimeType?.lowercased().hasPrefix("video/") == true {
                rawURL = item.source?.mp4 ?? item.source?.url
                    ?? item.previews?.last?.mp4 ?? item.previews?.last?.url
            } else {
                rawURL = item.source?.url ?? item.source?.gif ?? item.source?.mp4
                    ?? item.previews?.last?.url ?? item.previews?.last?.gif
            }
            if let rawURL, let url = validatedURL(rawURL) { candidates.append(url) }
        }

        for match in captures(
            pattern: #"!\[gif\]\(giphy\|([A-Za-z0-9]+)(?:\|[^\)]*)?\)"#,
            text: body,
            captureGroup: 1
        ) {
            if let url = URL(string: "https://media.giphy.com/media/\(match)/giphy.gif") {
                candidates.append(url)
            }
        }

        let decodedHTML = bodyHTML?.htmlDecoded ?? ""
        for match in captures(
            pattern: #"(?:href|src)\s*=\s*[\"'](https?://[^\"']+)[\"']"#,
            text: decodedHTML,
            captureGroup: 1
        ) {
            if let url = validatedURL(match), ExternalMediaClassifier.isSupportedSource(url) {
                candidates.append(url)
            }
        }

        for match in captures(
            pattern: #"https?://[^\s<>\[\]\(\)\"']+"#,
            text: body.htmlDecoded,
            captureGroup: 0
        ) {
            let cleaned = match.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            if let url = validatedURL(cleaned), ExternalMediaClassifier.isSupportedSource(url) {
                candidates.append(url)
            }
        }

        var seen: Set<String> = []
        return candidates.filter { url in
            let canonical = ExternalMediaClassifier.immediateResource(for: url)?.mediaURL.absoluteString
                ?? url.absoluteString
            return seen.insert(canonical).inserted
        }
    }

    static func displayBody(from body: String) -> String {
        let decoded = body.htmlDecoded
        let mediaMarkdownPattern = #"!\[(?:gif|img|image)\]\([^\)]*\)"#
        guard let expression = try? NSRegularExpression(pattern: mediaMarkdownPattern, options: [.caseInsensitive]) else {
            return decoded
        }
        let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
        let stripped = expression.stringByReplacingMatches(in: decoded, range: range, withTemplate: "")
        return stripped
            .replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validatedURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.htmlDecoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private static func captures(pattern: String, text: String, captureGroup: Int) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges > captureGroup,
                  let range = Range(match.range(at: captureGroup), in: text) else { return nil }
            return String(text[range])
        }
    }
}

struct CommentListingEnvelope: Decodable {
    let data: CommentListingData
}

struct CommentThreadEnvelope: Decodable {
    let comments: CommentListingEnvelope

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        _ = try container.decode(ListingEnvelope.self)
        comments = try container.decode(CommentListingEnvelope.self)
    }
}

struct CommentListingData: Decodable {
    let children: [CommentChild]
}

struct CommentChild: Decodable {
    let kind: String
    let data: RedditComment?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        data = kind == "t1" ? try container.decodeIfPresent(RedditComment.self, forKey: .data) : nil
    }

    enum CodingKeys: String, CodingKey { case kind, data }
}

extension String {
    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    var redditNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
    }

    var removingRedditThingPrefix: String {
        guard count > 3, self[index(startIndex, offsetBy: 2)] == "_" else { return self }
        return String(dropFirst(3))
    }

    var removingSubredditPrefix: String {
        var result = trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("/") { result.removeFirst() }
        if result.lowercased().hasPrefix("r/") { result = String(result.dropFirst(2)) }
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

extension Int {
    var compactCount: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fK", Double(self) / 1_000) }
        return String(self)
    }

    var upvoteLabel: String { "\(compactCount) \(self == 1 ? "upvote" : "upvotes")" }
    var commentLabel: String { "\(compactCount) \(self == 1 ? "comment" : "comments")" }
}
