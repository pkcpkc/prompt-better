import Foundation

/// Linear Score Combination strategy that normalizes raw scores to [0, 1] and blends:
/// Score(d) = alpha * vectorScore + (1 - alpha) * lexicalScore
public struct LinearRankFusion: RankFusionStrategy {
    public let alpha: Double // Weight given to vector score (0.0 to 1.0)

    public init(alpha: Double = 0.5) {
        self.alpha = min(max(alpha, 0.0), 1.0)
    }

    public func fuse(
        lexicalResults: [OpenAI.SearchResult],
        vectorResults: [OpenAI.SearchResult],
        limit: Int
    ) -> [OpenAI.SearchResult] {
        // Find min and max for normalization
        let maxLex = lexicalResults.map(\.score).max() ?? 1.0
        let minLex = lexicalResults.map(\.score).min() ?? 0.0
        let lexRange = max(maxLex - minLex, 0.0001)

        let maxVec = vectorResults.map(\.score).max() ?? 1.0
        let minVec = vectorResults.map(\.score).min() ?? 0.0
        let vecRange = max(maxVec - minVec, 0.0001)

        var map: [String: (score: Double, result: OpenAI.SearchResult)] = [:]

        for item in lexicalResults {
            let normalized = (item.score - minLex) / lexRange
            let weighted = (1.0 - alpha) * normalized
            map[item.id] = (score: weighted, result: item)
        }

        for item in vectorResults {
            let normalized = (item.score - minVec) / vecRange
            let weighted = alpha * normalized
            if let existing = map[item.id] {
                map[item.id] = (score: existing.score + weighted, result: existing.result)
            } else {
                map[item.id] = (score: weighted, result: item)
            }
        }

        return map.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { entry in
                var r = entry.result
                r.score = entry.score
                return r
            }
    }
}
