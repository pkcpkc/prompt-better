import Foundation

/// Coordinates hybrid search execution and prompt context assembly for RAG.
public struct HybridRAGFusion: Sendable {
    
    /// Executes search using the designated SearchMode.
    public static func search(
        query: String,
        limit: Int = 5,
        mode: SearchMode = .hybrid(),
        minScore: Double? = nil
    ) async -> [OpenAI.SearchResult] {
        switch mode {
        case .vectorOnly:
            return await VectorSearchEngine.shared.search(query: query, limit: limit, minScore: minScore)
            
        case .spotlightOnly:
            let results = await SpotlightSearchEngine.shared.search(query: query, limit: limit)
            if let threshold = minScore {
                return results.filter { $0.score >= threshold }
            }
            return results
            
        case .hybrid(let strategy):
            async let vectorResults = VectorSearchEngine.shared.search(query: query, limit: limit * 2, minScore: minScore)
            async let lexicalResults = SpotlightSearchEngine.shared.search(query: query, limit: limit * 2)
            
            let v = await vectorResults
            let l = await lexicalResults
            return strategy.fuse(lexicalResults: l, vectorResults: v, limit: limit)
        }
    }

    /// Formats retrieved search results into a clean markdown context block to prepend to user prompts.
    public static func formatContext(results: [OpenAI.SearchResult]) -> String {
        guard !results.isEmpty else { return "" }
        
        var sections = ["[LOCAL KNOWLEDGE BASE CONTEXT (Top \(results.count) Sources)]:"]
        for (idx, item) in results.enumerated() {
            sections.append("""
            Source \(idx + 1) (id: "\(item.id)", title: "\(item.title)", relevance: \(String(format: "%.3f", item.score))):
            "\(item.content)"
            """)
        }
        sections.append("""
        [GROUNDING DIRECTIVE]:
        Answer the following query using the context provided above. If the context does not contain the answer, state clearly that the answer is not in the knowledge base.
        """)
        
        return sections.joined(separator: "\n\n")
    }
}
