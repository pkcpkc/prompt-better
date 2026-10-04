import Foundation

public extension OpenAI {
    
    // MARK: - Moderations
    
    struct ModerationRequest: Codable, Sendable {
        public var model: String?
        public var input: String
        
        public init(input: String, model: String? = "apple-sensitive-content") {
            self.input = input
            self.model = model
        }
    }
    
    struct ModerationResponse: Codable, Sendable {
        public let id: String
        public let model: String
        public let results: [ModerationResult]
        
        public init(
            id: String = "modr-\(UUID().uuidString)",
            model: String = "apple-sensitive-content",
            results: [ModerationResult]
        ) {
            self.id = id
            self.model = model
            self.results = results
        }
        
        public struct ModerationResult: Codable, Sendable {
            public let flagged: Bool
            public let categories: [String: Bool]
            public let categoryScores: [String: Double]
            
            public init(
                flagged: Bool,
                categories: [String: Bool],
                categoryScores: [String: Double]
            ) {
                self.flagged = flagged
                self.categories = categories
                self.categoryScores = categoryScores
            }
            
            public enum CodingKeys: String, CodingKey {
                case flagged, categories
                case categoryScores = "category_scores"
            }
        }
    }
}
