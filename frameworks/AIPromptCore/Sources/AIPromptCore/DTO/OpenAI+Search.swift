import Foundation

public extension OpenAI {
    
    // MARK: - Search & Indexing
    
    struct SearchRequest: Codable, Sendable {
        public var query: String
        public var limit: Int?
        public var mode: String? // "vector", "spotlight", "hybrid"
        public var minScore: Double?
        public var fusion: FusionConfig?
        
        public init(
            query: String,
            limit: Int? = 5,
            mode: String? = "hybrid",
            minScore: Double? = nil,
            fusion: FusionConfig? = nil
        ) {
            self.query = query
            self.limit = limit
            self.mode = mode
            self.minScore = minScore
            self.fusion = fusion
        }
        
        public enum CodingKeys: String, CodingKey {
            case query, limit, mode, fusion
            case minScore = "min_score"
        }
        
        public struct FusionConfig: Codable, Sendable {
            public var type: String? // "rrf", "linear"
            public var k: Double?
            public var vectorWeight: Double?
            public var lexicalWeight: Double?
            
            public init(
                type: String? = "rrf",
                k: Double? = 60.0,
                vectorWeight: Double? = 1.0,
                lexicalWeight: Double? = 1.0
            ) {
                self.type = type
                self.k = k
                self.vectorWeight = vectorWeight
                self.lexicalWeight = lexicalWeight
            }
            
            public enum CodingKeys: String, CodingKey {
                case type, k
                case vectorWeight = "vector_weight"
                case lexicalWeight = "lexical_weight"
            }
        }
    }
    
    struct SearchResponse: Codable, Sendable {
        public var object: String
        public let data: [SearchResult]
        public let query: String
        public let mode: String
        
        public init(data: [SearchResult], query: String, mode: String, object: String = "list") {
            self.object = object
            self.data = data
            self.query = query
            self.mode = mode
        }
    }
    
    struct SearchResult: Codable, Sendable, Identifiable {
        public let id: String
        public var score: Double
        public let title: String
        public let content: String
        public let metadata: [String: String]?
        
        public init(
            id: String,
            score: Double,
            title: String,
            content: String,
            metadata: [String: String]? = nil
        ) {
            self.id = id
            self.score = score
            self.title = title
            self.content = content
            self.metadata = metadata
        }
    }
    
    struct IndexDocumentRequest: Codable, Sendable {
        public let id: String
        public let title: String
        public let content: String
        public let metadata: [String: String]?
        
        public init(
            id: String,
            title: String,
            content: String,
            metadata: [String: String]? = nil
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.metadata = metadata
        }
    }
    
    struct IndexDocumentResponse: Codable, Sendable {
        public let id: String
        public let status: String
        public let chunkCount: Int
        
        public init(id: String, status: String = "indexed", chunkCount: Int = 1) {
            self.id = id
            self.status = status
            self.chunkCount = chunkCount
        }
        
        public enum CodingKeys: String, CodingKey {
            case id, status
            case chunkCount = "chunk_count"
        }
    }
}
