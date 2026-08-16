# Lurko

Native iOS Reddit client. Local library, feed browsing, share extension, and home-screen widgets.

The Xcode target is still named `RedditJSON` (`com.proof.RedditJSON`). The user-facing name is Lurko.

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
