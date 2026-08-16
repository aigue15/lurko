import Foundation

actor RedditClient {
    enum ClientError: LocalizedError {
        case badURL
        case badResponse(Int)
        case invalidCommunity
        case emptyQuery
        case noContent

        var errorDescription: String? {
            switch self {
            case .badURL:
                "Reddit URL could not be created."
            case .badResponse(let code):
                "Reddit returned HTTP \(code). Try again shortly."
            case .invalidCommunity:
                "That community name is not valid."
            case .emptyQuery:
                "Enter something to search for."
            case .noContent:
                "Reddit did not return any readable content."
            }
        }
    }

    private struct CachedEngagement {
        let value: PostEngagement
        let fetchedAt: Date
    }

    private struct LivePostSummary {
        let id: String
        let title: String
        let author: String
        let subreddit: String
        let permalink: String
        let contentURL: String
        let score: Int
        let commentCount: Int
        let createdUTC: TimeInterval
        let isVideo: Bool
        let spoiler: Bool
        let over18: Bool
        let upvoteRatio: Double?
        let thumbnail: String?

        var fallbackPost: RedditPost {
            RedditPost(
                id: id,
                title: title,
                author: author,
                subreddit: subreddit,
                score: score,
                numComments: commentCount,
                permalink: permalink,
                url: contentURL,
                thumbnail: thumbnail,
                postHint: isVideo ? "hosted:video" : nil,
                createdUTC: createdUTC,
                isVideo: isVideo,
                spoiler: spoiler,
                over18: over18,
                upvoteRatio: upvoteRatio
            )
        }
    }

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var engagementCache: [String: CachedEngagement] = [:]
    private var communityCache: [String: RedditCommunity] = [:]

    private let jsonUserAgent = "ios:com.proof.RedditJSON:0.3 (anonymous read-only Reddit viewer)"
    private let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    private let engagementCacheLifetime: TimeInterval = 90
    private let pageSize = 25

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1_024 * 1_024,
            diskCapacity: 80 * 1_024 * 1_024
        )
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpAdditionalHeaders = [
            "User-Agent": jsonUserAgent,
            "Accept": "application/json"
        ]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Listings

    func posts(
        subreddit: String,
        sort: FeedSort,
        after: String? = nil
    ) async throws -> (posts: [RedditPost], after: String?) {
        let page = try await postPage(subreddit: subreddit, sort: sort, after: after)
        return (page.posts, page.after)
    }

    func postPage(
        subreddit: String,
        sort: FeedSort,
        after: String? = nil
    ) async throws -> RedditPostPage {
        let safeName = try normalizedSubreddit(subreddit)

        if let after, after.hasPrefix("html-feed:") {
            return try await shredditPostPage(subreddit: safeName, sort: sort, cursor: after)
        }
        if let after, after.hasPrefix("archive-feed:") {
            return try await archivePostPage(subreddit: safeName, sort: sort, cursor: after)
        }

        do {
            return try await redditJSONPostPage(subreddit: safeName, sort: sort, after: after)
        } catch let jsonError {
            // Do not replace a failed official continuation with page one (which would
            // duplicate the feed). Refresh Reddit's anonymous browser cookie and retry it.
            if after != nil {
                _ = try? await shredditHTML(url: URL(string: "https://sh.reddit.com/r/\(safeName)/\(sort.path)/"))
                if let retry = try? await redditJSONPostPage(subreddit: safeName, sort: sort, after: after) {
                    return retry
                }
                throw jsonError
            }
            do {
                return try await shredditPostPage(subreddit: safeName, sort: sort, cursor: nil)
            } catch {
                return try await archivePostPage(subreddit: safeName, sort: sort, cursor: nil)
            }
        }
    }

    private func redditJSONPostPage(
        subreddit: String,
        sort: FeedSort,
        after: String?
    ) async throws -> RedditPostPage {
        var components = URLComponents(string: "https://www.reddit.com/r/\(subreddit)/\(sort.path).json")
        var items = [
            URLQueryItem(name: "raw_json", value: "1"),
            URLQueryItem(name: "limit", value: String(pageSize))
        ]
        if sort == .top { items.append(URLQueryItem(name: "t", value: "week")) }
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        components?.queryItems = items

        let listing: ListingEnvelope = try await fetch(components?.url)
        return RedditPostPage(
            posts: listing.data.children.map(\.data),
            after: listing.data.after,
            source: .redditJSON
        )
    }

    private func shredditPostPage(
        subreddit: String,
        sort: FeedSort,
        cursor: String?
    ) async throws -> RedditPostPage {
        let isContinuation = cursor != nil
        let initialURL: URL
        if let cursor {
            guard let decoded = decodeCursor(cursor, prefix: "html-feed:"),
                  let url = absoluteShredditURL(from: decoded) else { throw ClientError.badURL }
            initialURL = url
        } else {
            var components = URLComponents(string: "https://sh.reddit.com/r/\(subreddit)/\(sort.path)/")
            if sort == .top {
                components?.queryItems = [URLQueryItem(name: "t", value: "week")]
            }
            guard let url = components?.url else { throw ClientError.badURL }
            initialURL = url
        }

        let html = try await shredditHTML(url: initialURL)
        var summaries = livePostSummaries(in: html)
        var continuation = shredditContinuation(in: html, pathContains: "/community-more-posts/")

        // Reddit server-renders only a few cards on the first community document.
        // Pull its own continuation once so a fresh feed still opens with a useful page.
        if !isContinuation, summaries.count < 10,
           let continuationPath = continuation,
           let continuationURL = absoluteShredditURL(from: continuationPath),
           let extraHTML = try? await shredditHTML(url: continuationURL) {
            let known = Set(summaries.map(\.id))
            summaries.append(contentsOf: livePostSummaries(in: extraHTML).filter { !known.contains($0.id) })
            continuation = shredditContinuation(in: extraHTML, pathContains: "/community-more-posts/")
        }

        var seen = Set<String>()
        summaries = summaries.filter { seen.insert($0.id).inserted }

        guard !summaries.isEmpty else { throw ClientError.noContent }
        engagementCacheFrom(summaries)
        return RedditPostPage(
            posts: try await enrichedPosts(from: summaries),
            after: continuation.map { encodeCursor($0, prefix: "html-feed:") },
            source: .redditHTML
        )
    }

    private func archivePostPage(
        subreddit: String,
        sort: FeedSort,
        cursor: String?
    ) async throws -> RedditPostPage {
        let before = cursor.flatMap { decodeCursor($0, prefix: "archive-feed:") }
        var archived = try await archivePosts(
            subreddit: subreddit,
            query: nil,
            limit: pageSize,
            before: before
        )

        // The archive is chronological. If Reddit HTML is also unavailable, top still
        // benefits from a score ordering within the fetched window; hot/rising remain fresh.
        if sort == .top {
            archived.sort {
                if $0.score == $1.score { return $0.createdUTC > $1.createdUTC }
                return $0.score > $1.score
            }
        }

        if let live = try? await communityEngagement(subreddit: subreddit) {
            for index in archived.indices {
                guard let engagement = live[archived[index].id] else { continue }
                archived[index].score = engagement.score
                archived[index].numComments = engagement.commentCount
                engagementCache[archived[index].id] = CachedEngagement(value: engagement, fetchedAt: Date())
            }
        }

        let next: String?
        if archived.count == pageSize, let oldest = archived.min(by: { $0.createdUTC < $1.createdUTC }) {
            next = encodeCursor(iso8601String(oldest.createdUTC - 0.001), prefix: "archive-feed:")
        } else {
            next = nil
        }
        return RedditPostPage(posts: archived, after: next, source: .archive)
    }

    // MARK: - Post search

    func searchPosts(_ query: String) async throws -> [RedditPost] {
        try await searchPostPage(query).posts
    }

    func searchPosts(_ query: String, in subreddit: String) async throws -> [RedditPost] {
        try await searchPostPage(query, subreddit: subreddit).posts
    }

    func searchPostPage(
        _ query: String,
        subreddit: String? = nil,
        sort: SearchSort = .relevance,
        after: String? = nil
    ) async throws -> RedditPostPage {
        let cleanQuery = try normalizedQuery(query)
        let safeSubreddit = try subreddit.map(normalizedSubreddit)

        if let after, after.hasPrefix("html-search:") {
            return try await shredditSearchPostPage(
                query: cleanQuery,
                subreddit: safeSubreddit,
                sort: sort,
                cursor: after
            )
        }
        if let after, after.hasPrefix("archive-search:") {
            guard let safeSubreddit else { throw ClientError.noContent }
            return try await archiveSearchPostPage(
                query: cleanQuery,
                subreddit: safeSubreddit,
                cursor: after
            )
        }

        do {
            return try await redditJSONSearchPage(
                query: cleanQuery,
                subreddit: safeSubreddit,
                sort: sort,
                after: after
            )
        } catch let jsonError {
            if after != nil {
                let warmURL = safeSubreddit
                    .flatMap { URL(string: "https://sh.reddit.com/r/\($0)/") }
                    ?? URL(string: "https://sh.reddit.com/")
                _ = try? await shredditHTML(url: warmURL)
                if let retry = try? await redditJSONSearchPage(
                    query: cleanQuery,
                    subreddit: safeSubreddit,
                    sort: sort,
                    after: after
                ) {
                    return retry
                }
                throw jsonError
            }
            do {
                return try await shredditSearchPostPage(
                    query: cleanQuery,
                    subreddit: safeSubreddit,
                    sort: sort,
                    cursor: nil
                )
            } catch {
                guard let safeSubreddit else { throw error }
                return try await archiveSearchPostPage(
                    query: cleanQuery,
                    subreddit: safeSubreddit,
                    cursor: nil
                )
            }
        }
    }

    private func redditJSONSearchPage(
        query: String,
        subreddit: String?,
        sort: SearchSort,
        after: String?
    ) async throws -> RedditPostPage {
        var components: URLComponents?
        if let subreddit {
            components = URLComponents(string: "https://www.reddit.com/r/\(subreddit)/search.json")
        } else {
            components = URLComponents(string: "https://www.reddit.com/search.json")
        }
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: sort.path),
            URLQueryItem(name: "type", value: "link"),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "raw_json", value: "1")
        ]
        if subreddit != nil { items.append(URLQueryItem(name: "restrict_sr", value: "on")) }
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        components?.queryItems = items
        let listing: ListingEnvelope = try await fetch(components?.url)
        return RedditPostPage(
            posts: listing.data.children.map(\.data),
            after: listing.data.after,
            source: .redditJSON
        )
    }

    private func shredditSearchPostPage(
        query: String,
        subreddit: String?,
        sort: SearchSort,
        cursor: String?
    ) async throws -> RedditPostPage {
        let initialURL: URL
        if let cursor {
            guard let decoded = decodeCursor(cursor, prefix: "html-search:"),
                  let url = absoluteShredditURL(from: decoded) else { throw ClientError.badURL }
            initialURL = url
        } else {
            let base = subreddit.map { "https://sh.reddit.com/r/\($0)/search/" }
                ?? "https://sh.reddit.com/search/"
            var components = URLComponents(string: base)
            var items = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "posts"),
                URLQueryItem(name: "sort", value: sort.path)
            ]
            if subreddit != nil { items.append(URLQueryItem(name: "restrict_sr", value: "on")) }
            components?.queryItems = items
            guard let url = components?.url else { throw ClientError.badURL }
            initialURL = url
        }

        let html = try await shredditHTML(url: initialURL)
        let summaries = searchPostSummaries(in: html)
        guard !summaries.isEmpty else { throw ClientError.noContent }
        engagementCacheFrom(summaries)
        let continuation = shredditContinuation(in: html, pathContains: "/svc/shreddit/search/")
        return RedditPostPage(
            posts: try await enrichedPosts(from: summaries),
            after: continuation.map { encodeCursor($0, prefix: "html-search:") },
            source: .redditHTML
        )
    }

    private func archiveSearchPostPage(
        query: String,
        subreddit: String,
        cursor: String?
    ) async throws -> RedditPostPage {
        let before = cursor.flatMap { decodeCursor($0, prefix: "archive-search:") }
        let posts = try await archivePosts(
            subreddit: subreddit,
            query: query,
            limit: pageSize,
            before: before
        )
        let next = posts.count == pageSize
            ? posts.last.map { encodeCursor(iso8601String($0.createdUTC - 0.001), prefix: "archive-search:") }
            : nil
        return RedditPostPage(posts: posts, after: next, source: .archive)
    }

    // MARK: - Communities

    func community(named subreddit: String) async throws -> RedditCommunity {
        let safeName = try normalizedSubreddit(subreddit)
        if let cached = communityCache[safeName] { return cached }

        do {
            let url = URL(string: "https://www.reddit.com/r/\(safeName)/about.json?raw_json=1")
            let envelope: CommunityAboutEnvelope = try await fetch(url)
            communityCache[safeName] = envelope.data
            return envelope.data
        } catch {
            if let archived = try? await archiveCommunity(named: safeName) {
                communityCache[safeName] = archived
                return archived
            }

            let html = try await shredditHTML(url: URL(string: "https://sh.reddit.com/r/\(safeName)/"))
            guard let live = liveCommunity(named: safeName, in: html) else { throw ClientError.noContent }
            communityCache[safeName] = live
            return live
        }
    }

    func searchCommunities(_ query: String) async throws -> [RedditCommunity] {
        try await searchCommunityPage(query).communities
    }

    func searchCommunityPage(_ query: String, after: String? = nil) async throws -> RedditCommunityPage {
        let cleanQuery = try normalizedQuery(query)

        if let after, after.hasPrefix("html-community-search:") {
            return try await shredditCommunitySearchPage(query: cleanQuery, cursor: after)
        }

        do {
            return try await redditJSONCommunitySearchPage(query: cleanQuery, after: after)
        } catch let jsonError {
            if after != nil {
                _ = try? await shredditHTML(url: URL(string: "https://sh.reddit.com/"))
                if let retry = try? await redditJSONCommunitySearchPage(query: cleanQuery, after: after) {
                    return retry
                }
                throw jsonError
            }
            do {
                return try await shredditCommunitySearchPage(query: cleanQuery, cursor: nil)
            } catch {
                let archived = try await archiveCommunitySearch(prefix: cleanQuery)
                archived.forEach { communityCache[$0.id] = $0 }
                return RedditCommunityPage(communities: archived, after: nil, source: .archive)
            }
        }
    }

    private func redditJSONCommunitySearchPage(
        query: String,
        after: String?
    ) async throws -> RedditCommunityPage {
        var components = URLComponents(string: "https://www.reddit.com/subreddits/search.json")
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "raw_json", value: "1")
        ]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        components?.queryItems = items
        let listing: CommunityListing = try await fetch(components?.url)
        let communities = listing.data.children.map(\.data)
        communities.forEach { communityCache[$0.id] = $0 }
        return RedditCommunityPage(
            communities: communities,
            after: listing.data.after,
            source: .redditJSON
        )
    }

    private func shredditCommunitySearchPage(
        query: String,
        cursor: String?
    ) async throws -> RedditCommunityPage {
        let url: URL
        if let cursor {
            guard let decoded = decodeCursor(cursor, prefix: "html-community-search:"),
                  let decodedURL = absoluteShredditURL(from: decoded) else { throw ClientError.badURL }
            url = decodedURL
        } else {
            var components = URLComponents(string: "https://sh.reddit.com/search/")
            components?.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "communities")
            ]
            guard let initialURL = components?.url else { throw ClientError.badURL }
            url = initialURL
        }

        let html = try await shredditHTML(url: url)
        var communities = communitySearchResults(in: html)
        guard !communities.isEmpty else { throw ClientError.noContent }

        // Prefix metadata adds subscriber counts and richer banners where the archive has it,
        // while keeping Reddit's live fuzzy result order and current icons/descriptions.
        if let archived = try? await archiveCommunitySearch(prefix: query) {
            var byName: [String: RedditCommunity] = [:]
            archived.forEach { byName[$0.id] = $0 }
            communities = communities.map { live in
                guard let archive = byName[live.id] else { return live }
                return mergedCommunity(live: live, archive: archive)
            }
        }
        communities.forEach { communityCache[$0.id] = $0 }
        let continuation = shredditContinuation(in: html, pathContains: "/svc/shreddit/search/")
        return RedditCommunityPage(
            communities: communities,
            after: continuation.map { encodeCursor($0, prefix: "html-community-search:") },
            source: .redditHTML
        )
    }

    // MARK: - Comments and live engagement

    func comments(postID: String, subreddit: String) async throws -> [RedditComment] {
        let safeID = postID.removingRedditThingPrefix
        let safeSubreddit = try normalizedSubreddit(subreddit)
        guard safeID.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil else {
            throw ClientError.badURL
        }

        let url = URL(string: "https://www.reddit.com/r/\(safeSubreddit)/comments/\(safeID).json?raw_json=1&limit=100&depth=10")
        do {
            let data = try await data(for: url)
            let thread = try decoder.decode(CommentThreadEnvelope.self, from: data)
            return thread.comments.data.children.compactMap(\.data)
        } catch {
            let archived = try await archiveComments(postID: safeID, maximum: 500)
            return reconstructCommentTree(archived)
        }
    }

    func engagement(for post: RedditPost) async throws -> PostEngagement {
        if let cached = engagementCache[post.id],
           Date().timeIntervalSince(cached.fetchedAt) < engagementCacheLifetime {
            return cached.value
        }

        let url = URL(string: "https://sh.reddit.com\(post.permalink)?embed=true&ref=share&ref_source=embed&utm_name=post_embed")
        let html = try await shredditHTML(url: url)
        guard let summary = livePostSummaries(in: html).first(where: { $0.id == post.id }) else {
            throw ClientError.noContent
        }
        let engagement = PostEngagement(score: summary.score, commentCount: summary.commentCount)
        engagementCache[post.id] = CachedEngagement(value: engagement, fetchedAt: Date())
        return engagement
    }

    private func archiveComments(postID: String, maximum: Int) async throws -> [RedditComment] {
        var result: [RedditComment] = []
        var seen = Set<String>()
        var after: String?

        for _ in 0..<max(1, min(5, Int(ceil(Double(maximum) / 100.0)))) {
            var components = URLComponents(string: "https://arctic-shift.photon-reddit.com/api/comments/search")
            var items = [
                URLQueryItem(name: "link_id", value: postID),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "sort", value: "asc")
            ]
            if let after { items.append(URLQueryItem(name: "after", value: after)) }
            components?.queryItems = items

            let envelope: ArchiveCommentEnvelope = try await fetch(components?.url)
            let newComments = envelope.data.filter { seen.insert($0.id).inserted }
            result.append(contentsOf: newComments)

            guard envelope.data.count == 100,
                  !newComments.isEmpty,
                  result.count < maximum,
                  let last = envelope.data.max(by: { $0.createdUTC < $1.createdUTC }) else { break }
            after = iso8601String(last.createdUTC + 0.001)
        }
        return Array(result.prefix(maximum))
    }

    private func reconstructCommentTree(_ flatComments: [RedditComment]) -> [RedditComment] {
        var commentsByID: [String: RedditComment] = [:]
        for comment in flatComments where commentsByID[comment.id] == nil {
            comment.replies = []
            commentsByID[comment.id] = comment
        }

        var roots: [RedditComment] = []
        for comment in flatComments {
            guard commentsByID[comment.id] === comment else { continue }
            if let parentID = comment.parentID,
               parentID.hasPrefix("t1_"),
               let parent = commentsByID[parentID.removingRedditThingPrefix] {
                parent.replies.append(comment)
            } else {
                roots.append(comment)
            }
        }

        func sortReplies(_ comments: inout [RedditComment]) {
            comments.sort {
                if $0.stickied != $1.stickied { return $0.stickied }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.createdUTC < $1.createdUTC
            }
            for comment in comments.indices {
                sortReplies(&comments[comment].replies)
            }
        }
        sortReplies(&roots)
        return roots
    }

    // MARK: - Archive transport

    private func archivePosts(
        subreddit: String,
        query: String?,
        limit: Int,
        before: String?
    ) async throws -> [RedditPost] {
        var components = URLComponents(string: "https://arctic-shift.photon-reddit.com/api/posts/search")
        var items = [
            URLQueryItem(name: "subreddit", value: subreddit),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100))),
            URLQueryItem(name: "sort", value: "desc")
        ]
        if let query, !query.isEmpty {
            // Arctic Shift requires an author or subreddit scope for FTS. Supplying both
            // fields searches the title/self-text corpus for this one community.
            items.append(URLQueryItem(name: "title", value: query))
            items.append(URLQueryItem(name: "selftext", value: query))
        }
        if let before { items.append(URLQueryItem(name: "before", value: before)) }
        components?.queryItems = items
        let archived: ArchivePostEnvelope = try await fetch(components?.url)
        return archived.data
    }

    private func archivedPosts(ids: [String]) async throws -> [RedditPost] {
        let uniqueIDs = ids.reduce(into: [String]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
        guard !uniqueIDs.isEmpty else { return [] }
        var components = URLComponents(string: "https://arctic-shift.photon-reddit.com/api/posts/ids")
        components?.queryItems = [URLQueryItem(name: "ids", value: uniqueIDs.joined(separator: ","))]
        let envelope: ArchivePostEnvelope = try await fetch(components?.url)
        return envelope.data
    }

    private func archiveCommunity(named name: String) async throws -> RedditCommunity {
        var components = URLComponents(string: "https://arctic-shift.photon-reddit.com/api/subreddits/search")
        components?.queryItems = [URLQueryItem(name: "subreddit", value: name)]
        let envelope: ArchiveCommunityEnvelope = try await fetch(components?.url)
        guard let community = envelope.data.first(where: { $0.id == name.redditNormalized }) else {
            throw ClientError.noContent
        }
        return community
    }

    private func archiveCommunitySearch(prefix: String) async throws -> [RedditCommunity] {
        let normalizedPrefix = prefix.removingSubredditPrefix.redditNormalized
        var components = URLComponents(string: "https://arctic-shift.photon-reddit.com/api/subreddits/search")
        components?.queryItems = [
            URLQueryItem(name: "subreddit_prefix", value: normalizedPrefix),
            URLQueryItem(name: "limit", value: String(pageSize))
        ]
        let envelope: ArchiveCommunityEnvelope = try await fetch(components?.url)
        return envelope.data
    }

    // MARK: - Reddit HTML parsing

    private func enrichedPosts(from summaries: [LivePostSummary]) async throws -> [RedditPost] {
        let archived = (try? await archivedPosts(ids: summaries.map(\.id))) ?? []
        var byID: [String: RedditPost] = [:]
        archived.forEach { byID[$0.id] = $0 }
        return summaries.map { summary in
            var post = byID[summary.id] ?? summary.fallbackPost
            post.score = summary.score
            post.numComments = summary.commentCount
            return post
        }
    }

    private func engagementCacheFrom(_ summaries: [LivePostSummary]) {
        let now = Date()
        for summary in summaries {
            engagementCache[summary.id] = CachedEngagement(
                value: PostEngagement(score: summary.score, commentCount: summary.commentCount),
                fetchedAt: now
            )
        }
    }

    private func livePostSummaries(in html: String) -> [LivePostSummary] {
        shredditPostTags(in: html).compactMap { tag in
            guard let rawID = attribute("id", in: tag), rawID.hasPrefix("t3_"),
                  let title = attribute("post-title", in: tag),
                  let permalink = attribute("permalink", in: tag) else { return nil }

            let id = rawID.removingRedditThingPrefix
            let subreddit = attribute("subreddit-name", in: tag)
                ?? attribute("subreddit-prefixed-name", in: tag)?.removingSubredditPrefix
                ?? permalink.split(separator: "/").dropFirst().first.map(String.init)
                ?? "unknown"
            let contentURL = attribute("content-href", in: tag)?.htmlDecoded
                ?? "https://www.reddit.com\(permalink)"
            let postType = attribute("post-type", in: tag)?.lowercased()
            let timestamp = attribute("created-timestamp", in: tag)
                .flatMap(parseISO8601)
                ?? 0

            return LivePostSummary(
                id: id,
                title: title.htmlDecoded,
                author: attribute("author", in: tag)?.htmlDecoded ?? "[deleted]",
                subreddit: subreddit.removingSubredditPrefix,
                permalink: permalink.htmlDecoded,
                contentURL: contentURL,
                score: attribute("score", in: tag).flatMap(Int.init) ?? 0,
                commentCount: attribute("comment-count", in: tag).flatMap(Int.init) ?? 0,
                createdUTC: timestamp,
                isVideo: postType == "video" || hasAttribute("is-video-post", in: tag),
                spoiler: hasAttribute("is-spoiler", in: tag),
                over18: hasAttribute("is-nsfw", in: tag) || hasAttribute("over-18", in: tag),
                upvoteRatio: attribute("upvote-ratio", in: tag).flatMap(Double.init),
                thumbnail: nil
            )
        }
    }

    private func searchPostSummaries(in html: String) -> [LivePostSummary] {
        let pattern = #"<search-telemetry-tracker\b[^>]*data-testid="search-sdui-post"[^>]*>"#
        let matches = regexMatches(pattern, in: html)
        guard !matches.isEmpty else { return [] }

        return matches.enumerated().compactMap { index, match in
            guard let openingRange = Range(match.range, in: html) else { return nil }
            let endIndex: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range, in: html) {
                endIndex = nextRange.lowerBound
            } else {
                endIndex = html.endIndex
            }
            let openingTag = String(html[openingRange])
            let segment = String(html[openingRange.lowerBound..<endIndex])

            let context = trackingContext(in: openingTag)
            let postContext = context?["post"] as? [String: Any]
            let profileContext = context?["profile"] as? [String: Any]
            let subredditContext = context?["subreddit"] as? [String: Any]
            let rawID = attribute("data-thingid", in: openingTag)
                ?? postContext?["id"] as? String
            guard let rawID,
                  let linkTag = capture(#"(<a\b[^>]*data-testid="post-title"[^>]*>)"#, in: segment),
                  let permalink = attribute("href", in: linkTag) else { return nil }

            let title = (postContext?["title"] as? String)
                ?? attribute("aria-label", in: linkTag)
                ?? "Untitled post"
            let numbers = captures(#"<faceplate-number\b[^>]*number="(-?[0-9]+)""#, in: segment)
            let timestamp = capture(#"<faceplate-timeago\b[^>]*ts="([^"]+)""#, in: segment)
                .flatMap(parseISO8601)
                ?? 0
            let thumbnailTag = capture(#"(<(?:faceplate-img|img)\b[^>]*data-testid="search_post_thumbnail"[^>]*>)"#, in: segment)
            let thumbnail = thumbnailTag.flatMap { attribute("src", in: $0) }?.htmlDecoded

            return LivePostSummary(
                id: rawID.removingRedditThingPrefix,
                title: title.htmlDecoded,
                author: (profileContext?["name"] as? String) ?? "[deleted]",
                subreddit: ((subredditContext?["name"] as? String) ?? "unknown").removingSubredditPrefix,
                permalink: permalink.htmlDecoded,
                contentURL: "https://www.reddit.com\(permalink.htmlDecoded)",
                score: numbers.first.flatMap(Int.init) ?? 0,
                commentCount: numbers.dropFirst().first.flatMap(Int.init) ?? 0,
                createdUTC: timestamp,
                isVideo: false,
                spoiler: (postContext?["spoiler"] as? Bool) ?? false,
                over18: (postContext?["nsfw"] as? Bool) ?? false,
                upvoteRatio: nil,
                thumbnail: thumbnail
            )
        }
    }

    private func communitySearchResults(in html: String) -> [RedditCommunity] {
        let pattern = #"<search-telemetry-tracker\b[^>]*view-events="search/view/subreddit"[^>]*>"#
        let matches = regexMatches(pattern, in: html)
        guard !matches.isEmpty else { return [] }

        return matches.enumerated().compactMap { index, match in
            guard let openingRange = Range(match.range, in: html) else { return nil }
            let endIndex: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range, in: html) {
                endIndex = nextRange.lowerBound
            } else {
                endIndex = html.endIndex
            }
            let openingTag = String(html[openingRange])
            let segment = String(html[openingRange.lowerBound..<endIndex])
            let context = trackingContext(in: openingTag)
            guard let subreddit = context?["subreddit"] as? [String: Any],
                  let name = subreddit["name"] as? String else { return nil }

            let iconTag = capture(#"(<img\b[^>]*shreddit-subreddit-icon[^>]*>)"#, in: segment)
            let icon = iconTag.flatMap { attribute("src", in: $0) }?.htmlDecoded
            let rawDescription = capture(
                #"<p\b[^>]*data-testid="search-subreddit-desc-text"[^>]*>([\s\S]*?)</p>"#,
                in: segment
            )
            let description = rawDescription.map(stripHTML) ?? ""

            return RedditCommunity(
                displayName: name,
                title: "r/\(name)",
                publicDescription: description,
                subscribers: nil,
                iconImg: icon,
                over18: (subreddit["nsfw"] as? Bool) ?? false,
                communityIcon: icon,
                url: "/r/\(name)/"
            )
        }
    }

    private func liveCommunity(named name: String, in html: String) -> RedditCommunity? {
        guard let header = capture(#"(<shreddit-subreddit-header\b[^>]*>)"#, in: html) else { return nil }
        let recentDataTag = capture(#"(<shreddit-recent-page-data\b[^>]*>)"#, in: html)
        let recentContext = recentDataTag.flatMap { attribute("data", in: $0) }
            .flatMap(jsonObject)
        let icon = recentContext?["communityIcon"] as? String
        let description = attribute("description", in: header)?.htmlDecoded ?? ""
        let displayName = attribute("name", in: header) ?? name
        let title = attribute("display-name", in: header)?.htmlDecoded ?? "r/\(displayName)"
        let activeUsers = attribute("weekly-active-users", in: header).flatMap(Int.init)
        return RedditCommunity(
            displayName: displayName,
            title: title,
            publicDescription: description,
            subscribers: nil,
            iconImg: icon,
            over18: hasAttribute("is-nsfw", in: header),
            communityIcon: icon,
            url: "/r/\(displayName)/",
            keyColor: recentContext?["keyColor"] as? String,
            activeUserCount: activeUsers
        )
    }

    private func mergedCommunity(live: RedditCommunity, archive: RedditCommunity) -> RedditCommunity {
        RedditCommunity(
            displayName: live.displayName,
            title: archive.title.isEmpty ? live.title : archive.title,
            publicDescription: live.publicDescription.isEmpty ? archive.publicDescription : live.publicDescription,
            subscribers: archive.subscribers,
            iconImg: live.iconImg ?? archive.iconImg,
            over18: live.over18 || archive.over18,
            communityIcon: live.communityIcon ?? archive.communityIcon,
            bannerImg: archive.bannerImg,
            bannerBackgroundImage: archive.bannerBackgroundImage,
            createdUTC: archive.createdUTC,
            url: archive.url ?? live.url,
            primaryColor: archive.primaryColor,
            keyColor: archive.keyColor,
            activeUserCount: archive.activeUserCount ?? live.activeUserCount
        )
    }

    private func communityEngagement(subreddit: String) async throws -> [String: PostEngagement] {
        let url = URL(string: "https://sh.reddit.com/r/\(subreddit)/new/")
        let html = try await shredditHTML(url: url)
        var result: [String: PostEngagement] = [:]
        livePostSummaries(in: html).forEach {
            result[$0.id] = PostEngagement(score: $0.score, commentCount: $0.commentCount)
        }
        return result
    }

    private func shredditHTML(url: URL?) async throws -> String {
        guard let url else { throw ClientError.badURL }
        let firstHTML = try await htmlRequest(url: url, referer: nil, acceptsErrorStatus: true)

        // A normal Shreddit document mentions its challenge system in bundled script text.
        // Only solve when the actual seed and hidden token form are both present.
        guard let seed = capture(#"await.*?\)\(\"([0-9a-f]+)\"\)"#, in: firstHTML),
              let token = capture(#"name=\"token\" value=\"([^\"]+)"#, in: firstHTML),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return firstHTML
        }

        var items = (components.queryItems ?? []).filter {
            !["solution", "js_challenge", "token", "jsc_orig_r"].contains($0.name)
        }
        items.append(contentsOf: [
            URLQueryItem(name: "solution", value: seed + seed),
            URLQueryItem(name: "js_challenge", value: "1"),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "jsc_orig_r", value: "")
        ])
        components.queryItems = items
        return try await htmlRequest(url: components.url, referer: url, acceptsErrorStatus: false)
    }

    private func htmlRequest(url: URL?, referer: URL?, acceptsErrorStatus: Bool) async throws -> String {
        guard let url else { throw ClientError.badURL }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard acceptsErrorStatus || (200..<300).contains(status) else {
            throw ClientError.badResponse(status)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw ClientError.noContent }
        return html
    }

    private func shredditPostTags(in html: String) -> [String] {
        captures(#"(<shreddit-post(?=[\s>])[^>]*>)"#, in: html)
    }

    private func shredditContinuation(in html: String, pathContains: String) -> String? {
        captures(#"\bsrc="([^"]+)""#, in: html)
            .map(\.htmlDecoded)
            .last { $0.contains(pathContains) }
    }

    private func trackingContext(in tag: String) -> [String: Any]? {
        attribute("data-faceplate-tracking-context", in: tag)
            .flatMap(jsonObject)
    }

    private func jsonObject(_ encoded: String) -> [String: Any]? {
        guard let data = encoded.htmlDecoded.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func attribute(_ name: String, in tag: String) -> String? {
        capture("\\b\(NSRegularExpression.escapedPattern(for: name))=\\\"([^\\\"]*)\\\"", in: tag)
    }

    private func hasAttribute(_ name: String, in tag: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return tag.range(of: "(?:^|\\s)\(escaped)(?:\\s|=|>)", options: .regularExpression) != nil
    }

    private func stripHTML(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return withoutTags.htmlDecoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cursor, validation, and transport helpers

    private func normalizedSubreddit(_ raw: String) throws -> String {
        let clean = raw.removingSubredditPrefix.redditNormalized
        guard clean.range(of: #"^[a-z0-9_]{2,32}$"#, options: .regularExpression) != nil else {
            throw ClientError.invalidCommunity
        }
        return clean
    }

    private func normalizedQuery(_ raw: String) throws -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ClientError.emptyQuery }
        return String(clean.prefix(128))
    }

    private func absoluteShredditURL(from path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        guard var components = URLComponents(string: "https://sh.reddit.com") else { return nil }
        if let pathComponents = URLComponents(string: path) {
            components.path = pathComponents.path
            components.queryItems = pathComponents.queryItems
        } else {
            components.path = path
        }
        return components.url
    }

    private func encodeCursor(_ value: String, prefix: String) -> String {
        let base64 = Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + base64
    }

    private func decodeCursor(_ cursor: String, prefix: String) -> String? {
        guard cursor.hasPrefix(prefix) else { return nil }
        var base64 = String(cursor.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func parseISO8601(_ string: String) -> TimeInterval? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }

    private func iso8601String(_ timestamp: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text).first
    }

    private func captures(_ pattern: String, in text: String) -> [String] {
        regexMatches(pattern, in: text).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    private func regexMatches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range)
    }

    private func fetch<T: Decodable>(_ url: URL?) async throws -> T {
        let data = try await data(for: url)
        return try decoder.decode(T.self, from: data)
    }

    private func data(for url: URL?) async throws -> Data {
        guard let url else { throw ClientError.badURL }
        var lastStatus = 0

        for attempt in 0...1 {
            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
            request.setValue(jsonUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return data }
            lastStatus = status

            guard attempt == 0, status == 429 || (500..<600).contains(status) else { break }
            try await Task.sleep(nanoseconds: 350_000_000)
        }
        throw ClientError.badResponse(lastStatus)
    }
}

enum FeedSort: String, CaseIterable, Identifiable {
    case hot, new, top, rising

    var id: Self { self }
    var path: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum SearchSort: String, CaseIterable, Identifiable {
    case relevance, hot, top, new, comments

    var id: Self { self }
    var path: String { rawValue }
    var label: String { rawValue.capitalized }
}
