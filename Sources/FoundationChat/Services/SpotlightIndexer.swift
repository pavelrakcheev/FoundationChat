import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

actor SpotlightIndexer {
    struct Item: Sendable {
        var id: String
        var title: String
        var model: String
    }

    static let shared = SpotlightIndexer()
    private let domain = "dev.pavelrakcheev.FoundationChat.conversations"

    func index(_ values: [Item]) async {
        let items = values.map { value in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = value.title
            attributes.contentDescription = "\(value.model) · Foundation Chat"
            attributes.keywords = ["Foundation Chat", "Apple Intelligence", value.model]
            return CSSearchableItem(
                uniqueIdentifier: value.id,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(
                withDomainIdentifiers: [domain]
            )
            try await CSSearchableIndex.default().indexSearchableItems(items)
        } catch {
            // Spotlight is supplementary; chat persistence must never fail with indexing.
        }
    }
}
