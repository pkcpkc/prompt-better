import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Lexical and string search engine integrating with CoreSpotlight and in-memory full-text indexing.
public actor SpotlightSearchEngine {
    public static let shared = SpotlightSearchEngine()

    public struct SpotlightRecord: Sendable {
        public let id: String
        public let title: String
        public let content: String
        public let metadata: [String: String]?
        public let keywords: Set<String>
    }

    private var localCache: [String: SpotlightRecord] = [:]
    private let domainIdentifier = "com.apple.aipromptcore.rag"

    public init() {}

    /// Indexes a document into CoreSpotlight and the local lexical cache.
    public func add(id: String, title: String, content: String, metadata: [String: String]? = nil) async {
        let words = extractTokens(from: "\(title) \(content)")
        let record = SpotlightRecord(
            id: id,
            title: title,
            content: content,
            metadata: metadata,
            keywords: words
        )
        localCache[id] = record

        // Index in system CoreSpotlight
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = title
        attributeSet.textContent = content
        attributeSet.keywords = Array(words)
        
        let item = CSSearchableItem(
            uniqueIdentifier: id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )

        try? await CSSearchableIndex.default().indexSearchableItems([item])
    }

    /// Deletes a document by ID.
    public func delete(id: String) async {
        localCache.removeValue(forKey: id)
        try? await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id])
    }

    /// Clears all indexed items.
    public func clear() async {
        localCache.removeAll()
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
    }

    /// Returns count of indexed documents.
    public var count: Int {
        localCache.count
    }

    /// Performs exact and token-based lexical string search.
    public func search(query: String, limit: Int = 5) -> [OpenAI.SearchResult] {
        let queryTokens = extractTokens(from: query)
        guard !queryTokens.isEmpty else { return [] }

        var scored: [(score: Double, record: SpotlightRecord)] = []
        let lowerQuery = query.lowercased()

        for record in localCache.values {
            var score: Double = 0.0

            // 1. Exact full-string match in title or content (highest boost)
            if record.title.lowercased().contains(lowerQuery) {
                score += 5.0
            }
            if record.content.lowercased().contains(lowerQuery) {
                score += 3.0
            }

            // 2. Token overlap score
            let intersection = record.keywords.intersection(queryTokens)
            if !intersection.isEmpty {
                score += Double(intersection.count) * 1.5
            }

            if score > 0 {
                scored.append((score: score, record: record))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { item in
                OpenAI.SearchResult(
                    id: item.record.id,
                    score: item.score,
                    title: item.record.title,
                    content: item.record.content,
                    metadata: item.record.metadata
                )
            }
    }

    private func extractTokens(from text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        return Set(words)
    }
}
