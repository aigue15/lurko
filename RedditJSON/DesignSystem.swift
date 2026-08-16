import SwiftUI
import UIKit

enum ContentLoadIssue: Equatable, Sendable {
    case offline
    case timedOut
    case redditBlocked
    case rateLimited
    case redditUnavailable
    case unreadableResponse
    case unknown(String)

    init(error: Error) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            case .timedOut:
                self = .timedOut
            default:
                self = .unknown(urlError.localizedDescription)
            }
            return
        }

        if let clientError = error as? RedditClient.ClientError {
            switch clientError {
            case .badResponse(let status) where [401, 403, 451].contains(status):
                self = .redditBlocked
            case .badResponse(429):
                self = .rateLimited
            case .badResponse(let status) where status == 0 || (500..<600).contains(status):
                self = .redditUnavailable
            case .noContent:
                self = .unreadableResponse
            default:
                self = .unknown(clientError.localizedDescription)
            }
            return
        }

        if error is DecodingError {
            self = .unreadableResponse
        } else {
            self = .unknown(error.localizedDescription)
        }
    }

    static func preferred(in issues: [ContentLoadIssue]) -> ContentLoadIssue {
        for preferred in [
            ContentLoadIssue.offline,
            .redditBlocked,
            .rateLimited,
            .timedOut,
            .redditUnavailable,
            .unreadableResponse
        ] where issues.contains(preferred) {
            return preferred
        }
        return issues.first ?? .unreadableResponse
    }

    var title: String {
        switch self {
        case .offline: "You’re offline"
        case .timedOut: "Reddit took too long"
        case .redditBlocked: "Reddit blocked this request"
        case .rateLimited: "Reddit is limiting requests"
        case .redditUnavailable: "Reddit is unavailable"
        case .unreadableResponse: "Reddit returned an unreadable response"
        case .unknown: "Couldn’t load from Reddit"
        }
    }

    var message: String {
        switch self {
        case .offline:
            "Reconnect to refresh. Locally saved and previously opened content is still available."
        case .timedOut:
            "Your connection may be slow, or Reddit may be busy. Try again in a moment."
        case .redditBlocked:
            "Reddit refused anonymous access from this connection. You can retry or continue with locally cached content."
        case .rateLimited:
            "Too many anonymous requests were made recently. Wait briefly, then retry."
        case .redditUnavailable:
            "Reddit’s public endpoints are not responding right now. Try again shortly."
        case .unreadableResponse:
            "The public response did not contain content Lurko could read. Retrying may use another anonymous fallback."
        case .unknown(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .timedOut: "clock.badge.exclamationmark"
        case .redditBlocked: "hand.raised.fill"
        case .rateLimited: "hourglass"
        case .redditUnavailable: "server.rack"
        case .unreadableResponse: "doc.questionmark"
        case .unknown: "wifi.exclamationmark"
        }
    }
}

struct LoadIssueView: View {
    let issue: ContentLoadIssue
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(issue.title, systemImage: issue.systemImage)
        } description: {
            Text(issue.message)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct CachedContentBanner: View {
    let issue: ContentLoadIssue
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: issue.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.subheadline.weight(.semibold))
                Text("Showing content stored on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(AppTheme.tintSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

enum AppTheme {
    static let tint = Color(red: 1.00, green: 0.36, blue: 0.20)
    static let tintSoft = tint.opacity(0.12)
    static let cardRadius: CGFloat = 18
    static let contentPadding: CGFloat = 16

    static func communityColor(_ name: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.96, green: 0.34, blue: 0.23),
            Color(red: 0.25, green: 0.49, blue: 0.96),
            Color(red: 0.35, green: 0.68, blue: 0.48),
            Color(red: 0.61, green: 0.39, blue: 0.91),
            Color(red: 0.96, green: 0.60, blue: 0.18),
            Color(red: 0.17, green: 0.65, blue: 0.70)
        ]
        let value = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(value) % palette.count]
    }
}

struct CommunityAvatar: View {
    let name: String
    var iconURL: URL?
    var size: CGFloat = 32

    var body: some View {
        AsyncImage(url: iconURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.communityColor(name).opacity(0.14))
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.primary.opacity(0.06)) }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.communityColor(name), AppTheme.communityColor(name).opacity(0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.43, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

struct CountLabel: View {
    let value: Int
    let systemImage: String
    let accessibilityText: String

    var body: some View {
        Label(value.compactCount, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(accessibilityText)
    }
}

struct CapsuleActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : AppTheme.tint)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(prominent ? AppTheme.tint : AppTheme.tintSoft, in: Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A finger-friendly utility action used for high-frequency post controls.
/// The 44-point minimum remains comfortable without making feed cards feel heavy.
struct PostUtilityActionStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? AppTheme.tint : Color.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(
                isActive ? AppTheme.tintSoft : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.62 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06))
            }
    }
}

extension View {
    func appCard() -> some View { modifier(CardBackground()) }
}

@MainActor
enum HapticFeedback {
    static func selection(enabled: Bool) {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension TimeInterval {
    var relativeRedditTime: String {
        let date = Date(timeIntervalSince1970: self)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
