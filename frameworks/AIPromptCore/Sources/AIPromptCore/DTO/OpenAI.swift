import Foundation

public enum OpenAI {
    
    // MARK: - Chat Completions
    
    public struct ChatCompletionRequest: Codable, Sendable {
        public var model: String
        public var messages: [Message]
        public var temperature: Float?
        public var topP: Float?
        public var maxTokens: Int?
        public var stream: Bool?
        public var stop: [String]?
        public var responseFormat: ResponseFormat?
        public var rag: RAGConfiguration?
        
        public init(
            model: String,
            messages: [Message],
            temperature: Float? = nil,
            topP: Float? = nil,
            maxTokens: Int? = nil,
            stream: Bool? = nil,
            stop: [String]? = nil,
            responseFormat: ResponseFormat? = nil,
            rag: RAGConfiguration? = nil
        ) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.topP = topP
            self.maxTokens = maxTokens
            self.stream = stream
            self.stop = stop
            self.responseFormat = responseFormat
            self.rag = rag
        }
        
        public enum CodingKeys: String, CodingKey {
            case model, messages, temperature, stream, stop, rag
            case topP = "top_p"
            case maxTokens = "max_tokens"
            case responseFormat = "response_format"
        }
        
        public struct ResponseFormat: Codable, Sendable {
            public var type: String // "text", "json_object", "json_schema"
            public var jsonSchema: JSONSchemaDefinition?
            
            public init(type: String, jsonSchema: JSONSchemaDefinition? = nil) {
                self.type = type
                self.jsonSchema = jsonSchema
            }
            
            public enum CodingKeys: String, CodingKey {
                case type
                case jsonSchema = "json_schema"
            }
        }
        
        public struct JSONSchemaDefinition: Codable, Sendable {
            public var name: String
            public var strict: Bool?
            public var schema: [String: AnyCodableValue]?
            
            public init(name: String, strict: Bool? = nil, schema: [String: AnyCodableValue]? = nil) {
                self.name = name
                self.strict = strict
                self.schema = schema
            }
        }
        
        public struct RAGConfiguration: Codable, Sendable {
            public var enabled: Bool?
            public var indexId: String?
            public var mode: String? // "vector", "spotlight", "hybrid"
            public var limit: Int?
            public var minScore: Double?
            
            public init(
                enabled: Bool? = true,
                indexId: String? = nil,
                mode: String? = nil,
                limit: Int? = nil,
                minScore: Double? = nil
            ) {
                self.enabled = enabled
                self.indexId = indexId
                self.mode = mode
                self.limit = limit
                self.minScore = minScore
            }
            
            public enum CodingKeys: String, CodingKey {
                case enabled, mode, limit
                case indexId = "index_id"
                case minScore = "min_score"
            }
        }
        
        public struct Message: Codable, Sendable {
            public var role: String
            public var content: MessageContent
            public var name: String?
            
            public init(role: String, content: String, name: String? = nil) {
                self.role = role
                self.content = .text(content)
                self.name = name
            }
            
            public init(role: String, content: MessageContent, name: String? = nil) {
                self.role = role
                self.content = content
                self.name = name
            }
            
            public init(role: String, parts: [ContentPart], name: String? = nil) {
                self.role = role
                self.content = .parts(parts)
                self.name = name
            }
        }
        
        public enum MessageContent: Codable, Sendable, ExpressibleByStringLiteral {
            case text(String)
            case parts([ContentPart])
            
            public init(stringLiteral value: String) {
                self = .text(value)
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    self = .text("")  // OpenAI allows null content (e.g. assistant messages)
                } else if let str = try? container.decode(String.self) {
                    self = .text(str)
                } else {
                    // Propagate decoding errors instead of falling back to empty text.
                    self = .parts(try container.decode([ContentPart].self))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let str):
                    try container.encode(str)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }
            
            public var rawText: String {
                switch self {
                case .text(let str):
                    return str
                case .parts(let parts):
                    return parts.compactMap { part in
                        switch part {
                        case .text(let t): return t
                        default: return nil
                        }
                    }.joined(separator: "\n")
                }
            }
        }
        
        public enum ContentPart: Codable, Sendable {
            case text(String)
            case imageUrl(ImageURL)
            case inputAudio(InputAudio)
            case document(DocumentAttachment)
            
            public enum CodingKeys: String, CodingKey {
                case type, text
                case imageUrl = "image_url"
                case inputAudio = "input_audio"
                case document
            }
            
            public struct ImageURL: Codable, Sendable {
                public var url: String
                public var detail: String?
                
                public init(url: String, detail: String? = nil) {
                    self.url = url
                    self.detail = detail
                }
            }
            
            public struct InputAudio: Codable, Sendable {
                public var data: String // base64
                public var format: String // "wav", "mp3", "m4a"
                
                public init(data: String, format: String) {
                    self.data = data
                    self.format = format
                }
            }
            
            public struct DocumentAttachment: Codable, Sendable {
                public var data: String // base64
                public var format: String // "pdf", "txt"
                public var filename: String?
                
                public init(data: String, format: String, filename: String? = nil) {
                    self.data = data
                    self.format = format
                    self.filename = filename
                }
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)
                switch type {
                case "text":
                    let text = try container.decode(String.self, forKey: .text)
                    self = .text(text)
                case "image_url":
                    let img = try container.decode(ImageURL.self, forKey: .imageUrl)
                    self = .imageUrl(img)
                case "input_audio":
                    let audio = try container.decode(InputAudio.self, forKey: .inputAudio)
                    self = .inputAudio(audio)
                case "document":
                    let doc = try container.decode(DocumentAttachment.self, forKey: .document)
                    self = .document(doc)
                default:
                    throw DecodingError.dataCorruptedError(
                        forKey: .type,
                        in: container,
                        debugDescription: "Unsupported content part type '\(type)'. Supported: text, image_url, input_audio, document."
                    )
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let t):
                    try container.encode("text", forKey: .type)
                    try container.encode(t, forKey: .text)
                case .imageUrl(let img):
                    try container.encode("image_url", forKey: .type)
                    try container.encode(img, forKey: .imageUrl)
                case .inputAudio(let audio):
                    try container.encode("input_audio", forKey: .type)
                    try container.encode(audio, forKey: .inputAudio)
                case .document(let doc):
                    try container.encode("document", forKey: .type)
                    try container.encode(doc, forKey: .document)
                }
            }
        }
    }
    
    public struct ChatCompletionResponse: Codable, Sendable {
        public let id: String
        public var object: String
        public let created: Int
        public let model: String
        public let choices: [Choice]
        public let usage: Usage?
        
        public init(
            id: String,
            created: Int,
            model: String,
            choices: [Choice],
            usage: Usage? = nil,
            object: String = "chat.completion"
        ) {
            self.id = id
            self.object = object
            self.created = created
            self.model = model
            self.choices = choices
            self.usage = usage
        }
        
        public struct Choice: Codable, Sendable {
            public let index: Int
            public let message: Message
            public let finishReason: String?
            
            public init(index: Int, message: Message, finishReason: String? = "stop") {
                self.index = index
                self.message = message
                self.finishReason = finishReason
            }
            
            public enum CodingKeys: String, CodingKey {
                case index, message
                case finishReason = "finish_reason"
            }
        }
        
        public struct Message: Codable, Sendable {
            public let role: String
            public let content: String
            
            public init(role: String = "assistant", content: String) {
                self.role = role
                self.content = content
            }
        }
        
        public struct Usage: Codable, Sendable {
            public let promptTokens: Int
            public let completionTokens: Int
            public let totalTokens: Int
            
            public init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int = 0) {
                self.promptTokens = promptTokens
                self.completionTokens = completionTokens
                self.totalTokens = totalTokens
            }
            
            public enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
            }
        }
    }
    
    // MARK: - Models Listing
    
    public struct ModelListResponse: Codable, Sendable {
        public var object: String
        public let data: [Model]
        
        public init(data: [Model], object: String = "list") {
            self.object = object
            self.data = data
        }
        
        public struct Model: Codable, Sendable, Identifiable {
            public let id: String
            public var object: String
            public let created: Int
            public let ownedBy: String
            /// Model type (`llm`, `multimodal`, `ocr`, `stt`, `embedding`, ...). Extension to the OpenAI schema.
            public let type: String?
            /// Accepted input kinds (`text`, `image`, `audio`, `document`). Extension to the OpenAI schema.
            public let inputModalities: [String]?
            
            public init(
                id: String,
                created: Int = Int(Date().timeIntervalSince1970),
                ownedBy: String = "apple",
                object: String = "model",
                type: ModelType? = nil,
                inputModalities: Set<InputModality>? = nil
            ) {
                self.id = id
                self.object = object
                self.created = created
                self.ownedBy = ownedBy
                self.type = type?.rawValue
                self.inputModalities = inputModalities.map { $0.map(\.rawValue).sorted() }
            }
            
            public enum CodingKeys: String, CodingKey {
                case id, object, created, type
                case ownedBy = "owned_by"
                case inputModalities = "input_modalities"
            }
        }
    }
    
    // MARK: - Generic AnyCodable Helper
    
    public enum AnyCodableValue: Codable, Sendable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case array([AnyCodableValue])
        case dictionary([String: AnyCodableValue])
        case null

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let b = try? container.decode(Bool.self) {
                self = .bool(b)
            } else if let i = try? container.decode(Int.self) {
                self = .int(i)
            } else if let d = try? container.decode(Double.self) {
                self = .double(d)
            } else if let s = try? container.decode(String.self) {
                self = .string(s)
            } else if let a = try? container.decode([AnyCodableValue].self) {
                self = .array(a)
            } else if let dict = try? container.decode([String: AnyCodableValue].self) {
                self = .dictionary(dict)
            } else {
                self = .null
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let b): try container.encode(b)
            case .int(let i): try container.encode(i)
            case .double(let d): try container.encode(d)
            case .string(let s): try container.encode(s)
            case .array(let a): try container.encode(a)
            case .dictionary(let d): try container.encode(d)
            }
        }
    }
}

// MARK: - Request Prompt Helpers

public extension OpenAI.ChatCompletionRequest {
    var systemInstructions: String {
        messages
            .filter { $0.role == "system" }
            .map { $0.content.rawText }
            .joined(separator: "\n\n")
    }

    var combinedPrompt: String {
        messages
            .filter { $0.role != "system" }
            .map { $0.content.rawText }
            .joined(separator: "\n\n")
    }
}
