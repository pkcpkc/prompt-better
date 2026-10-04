import Foundation

/// In-process index and search client for local document management and RAG.
@MainActor
public final class IndexClient: Sendable {
    public init() {}
    
    /// Indexes a document into both CoreSpotlight and Vector search engines.
    public func add(
        id: String,
        title: String,
        content: String,
        metadata: [String: String]? = nil
    ) async {
        await SpotlightSearchEngine.shared.add(id: id, title: title, content: content, metadata: metadata)
        await VectorSearchEngine.shared.add(id: id, title: title, content: content, metadata: metadata)
    }
    
    /// Searches indexed documents using the specified SearchMode.
    public func search(
        query: String,
        limit: Int = 5,
        mode: SearchMode = .hybrid(),
        minScore: Double? = nil
    ) async -> [OpenAI.SearchResult] {
        return await HybridRAGFusion.search(query: query, limit: limit, mode: mode, minScore: minScore)
    }
    
    /// Deletes a document by ID from all indexes.
    public func delete(id: String) async {
        await SpotlightSearchEngine.shared.delete(id: id)
        await VectorSearchEngine.shared.delete(id: id)
    }
    
    /// Clears all indexed items.
    public func clear() async {
        await SpotlightSearchEngine.shared.clear()
        await VectorSearchEngine.shared.clear()
    }
    
    /// Returns counts of indexed items in both engines.
    public func count() async -> (spotlight: Int, vector: Int) {
        let s = await SpotlightSearchEngine.shared.count
        let v = await VectorSearchEngine.shared.count
        return (s, v)
    }
}
