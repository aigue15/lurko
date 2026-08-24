# Lyra

Native iOS Reddit client in the spirit of Apollo: feed-first, compact, and account-free.

Subscriptions, saves, history, and filters stay on this device. No Reddit login.

The Xcode target is still named `RedditJSON` (`com.proof.RedditJSON`). The user-facing name is Lyra.

## Features

- Home, Popular, and All as the first screen
- Compact vote-column posts, with comfortable and media layouts
- Local library: saved posts, queue, favorites, collections, comments
- Share extension and Home Screen widgets
- Encrypted on-device backup

## Open

```bash
open RedditJSON.xcodeproj
```

Or regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

Requires iOS 17+, Xcode, and the `PTYK65EU6A` development team already set in `project.yml`.

## Layout

- `RedditJSON/` — app sources
- `ShareExtension/` — share sheet
- `WidgetExtension/` — widgets
- `Shared/` — code used by the app and extensions
- `Tests/` — local library core tests
- `Package.swift` — SwiftPM test target for that core

Lyra is independent and not affiliated with Reddit, Inc.
