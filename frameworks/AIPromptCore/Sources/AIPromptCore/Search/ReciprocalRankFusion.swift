import Foundation

/// Standard Reciprocal Rank Fusion (RRF) algorithm combining lexical and vector ranks.
/// Score(d) = sum( weight / (k + rank) )
public struct ReciprocalRankFusion: RankFusionStrategy {
    public let k: Double
    public let lexicalWeight: Double
    public let vectorWeight: Double

    public init(k: Double = 60.0, lexicalWeight: Double = 1.0, vectorWeight: Double = 1.0) {
        self.k = k
        self.lexicalWeight = lexicalWeight
        self.vectorWeight = vectorWeight
    }

    public func fuse(
        lexicalResults: [OpenAI.SearchResult],
        vectorResults: [OpenAI.SearchResult],
        limit: Int
    ) -> [OpenAI.SearchResult] {
        var scoreMap: [String: (score: Double, result: OpenAI.SearchResult)] = [:]

        // 1. Accumulate Spotlight Lexical RRF ranks
        for (rank, item) in lexicalResults.enumerated() {
            let rrfScore = lexicalWeight / (k + Double(rank + 1))
            scoreMap[item.id] = (score: rrfScore, result: item)
        }

        // 2. Accumulate Vector RRF ranks
        for (rank, item) in vectorResults.enumerated() {
            let rrfScore = vectorWeight / (k + Double(rank + 1))
            if let existing = scoreMap[item.id] {
                scoreMap[item.id] = (score: existing.score + rrfScore, result: existing.result)
            } else {
                scoreMap[item.id] = (score: rrfScore, result: item)
            }
        }

        // 3. Sort by fused score descending and slice to limit
        return scoreMap.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { entry in
                var finalResult = entry.result
                finalResult.score = entry.score
                return finalResult
            }
    }
}
