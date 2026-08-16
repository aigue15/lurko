import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await saveSharedItem() }
    }

    private func saveSharedItem() async {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
               let url = (item as? URL) ?? (item as? String).flatMap(URL.init(string:)) {
                ThreadlineSharedStore.enqueue(SharedSavedLink(url: url))
                extensionContext?.completeRequest(returningItems: nil)
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
               let text = item as? String,
               let url = URL(string: text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) {
                ThreadlineSharedStore.enqueue(SharedSavedLink(url: url))
                extensionContext?.completeRequest(returningItems: nil)
                return
            }
        }

        extensionContext?.cancelRequest(withError: ShareError.noURL)
    }

    private enum ShareError: LocalizedError {
        case noURL
        var errorDescription: String? { "Lurko could not find a URL to save." }
    }
}
