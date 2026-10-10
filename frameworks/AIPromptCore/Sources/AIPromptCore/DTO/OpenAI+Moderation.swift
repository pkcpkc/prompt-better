import Foundation

public extension OpenAI {
    
    // MARK: - Moderations
    
    struct ModerationRequest: Codable, Sendable {
        public var model: String?
        public var input: Input
        
        public init(input: String, model: String? = "apple-sensitive-content") {
            self.input = .text(input)
            self.model = model
        }
        
        public init(input: Input, model: String? = "apple-sensitive-content") {
            self.input = input
            self.model = model
        }
        
        /// Matches OpenAI's moderation `input`: a string, an array of strings, or an array of typed parts
        /// (`{"type": "image_url", "image_url": {"url": ...}}` / `{"type": "text", "text": ...}`).
        public enum Input: Codable, Sendable {
            case text(String)
            case texts([String])
            case parts([Part])
            
            public struct Part: Codable, Sendable {
                public let type: String
                public let text: String?
                public let imageUrl: ImageURL?
                
                public struct ImageURL: Codable, Sendable {
                    public let url: String
                    public init(url: String) { self.url = url }
                }
                
                public init(type: String, text: String? = nil, imageUrl: ImageURL? = nil) {
                    self.type = type
                    self.text = text
                    self.imageUrl = imageUrl
                }
                
                public static func image(url: String) -> Part { .init(type: "image_url", imageUrl: .init(url: url)) }
                public static func text(_ text: String) -> Part { .init(type: "text", text: text) }
                
                public enum CodingKeys: String, CodingKey {
                    case type, text
                    case imageUrl = "image_url"
                }
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let s = try? container.decode(String.self) {
                    self = .text(s)
                } else if let strings = try? container.decode([String].self) {
                    self = .texts(strings)
                } else {
                    self = .parts(try container.decode([Part].self))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let s): try container.encode(s)
                case .texts(let a): try container.encode(a)
                case .parts(let p): try container.encode(p)
                }
            }
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
