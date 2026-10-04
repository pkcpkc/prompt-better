import Foundation

/// Pluggable rank fusion protocol for combining lexical and semantic search results.
public protocol RankFusionStrategy: Sendable {
    func fuse(
        lexicalResults: [OpenAI.SearchResult],
        vectorResults: [OpenAI.SearchResult],
        limit: Int
    ) -> [OpenAI.SearchResult]
}
