import Foundation

/// Defines how local search executes across Vector and CoreSpotlight engines.
public enum SearchMode: Sendable {
    /// Pure semantic vector search using NaturalLanguage (NLEmbedding) and Accelerate (vDSP).
    case vectorOnly
    
    /// Pure string / lexical search using Apple's native CoreSpotlight engine.
    case spotlightOnly
    
    /// Parallel hybrid search combining both engines with a pluggable fusion strategy.
    case hybrid(strategy: any RankFusionStrategy)
    
    /// Default hybrid search using Reciprocal Rank Fusion (RRF with k = 60).
    public static func hybrid(
        k: Double = 60.0,
        lexicalWeight: Double = 1.0,
        vectorWeight: Double = 1.0
    ) -> SearchMode {
        return .hybrid(strategy: ReciprocalRankFusion(k: k, lexicalWeight: lexicalWeight, vectorWeight: vectorWeight))
    }
}
