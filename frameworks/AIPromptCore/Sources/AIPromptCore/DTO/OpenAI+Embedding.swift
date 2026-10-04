import Foundation

public extension OpenAI {
    
    // MARK: - Embeddings
    
    struct EmbeddingRequest: Codable, Sendable {
        public var model: String
        public var input: EmbeddingInput
        public var user: String?
        
        public init(model: String = "apple-sentence-embedding", input: EmbeddingInput, user: String? = nil) {
            self.model = model
            self.input = input
            self.user = user
        }
        
        public init(model: String = "apple-sentence-embedding", string: String, user: String? = nil) {
            self.model = model
            self.input = .single(string)
            self.user = user
        }
        
        public init(model: String = "apple-sentence-embedding", strings: [String], user: String? = nil) {
            self.model = model
            self.input = .multiple(strings)
            self.user = user
        }
        
        public enum EmbeddingInput: Codable, Sendable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
            case single(String)
            case multiple([String])
            
            public init(stringLiteral value: String) {
                self = .single(value)
            }
            
            public init(arrayLiteral elements: String...) {
                self = .multiple(elements)
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let str = try? container.decode(String.self) {
                    self = .single(str)
                } else if let arr = try? container.decode([String].self) {
                    self = .multiple(arr)
                } else {
                    self = .multiple([])
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .single(let str):
                    try container.encode(str)
                case .multiple(let arr):
                    try container.encode(arr)
                }
            }
            
            public var strings: [String] {
                switch self {
                case .single(let s): return [s]
                case .multiple(let a): return a
                }
            }
        }
    }
    
    struct EmbeddingResponse: Codable, Sendable {
        public var object: String
        public let data: [EmbeddingObject]
        public let model: String
        public let usage: Usage
        
        public init(data: [EmbeddingObject], model: String, usage: Usage = .init(), object: String = "list") {
            self.object = object
            self.data = data
            self.model = model
            self.usage = usage
        }
        
        public struct Usage: Codable, Sendable {
            public let promptTokens: Int
            public let totalTokens: Int
            
            public init(promptTokens: Int = 0, totalTokens: Int = 0) {
                self.promptTokens = promptTokens
                self.totalTokens = totalTokens
            }
            
            public enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case totalTokens = "total_tokens"
            }
        }
    }
    
    struct EmbeddingObject: Codable, Sendable {
        public var object: String
        public let index: Int
        public let embedding: [Float]
        
        public init(index: Int, embedding: [Float], object: String = "embedding") {
            self.object = object
            self.index = index
            self.embedding = embedding
        }
    }
}
