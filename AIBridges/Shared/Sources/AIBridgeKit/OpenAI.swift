import Vapor

/// The subset of the OpenAI REST schema the optimizer uses: chat completions, model listing and errors.
public enum OpenAI {

    // MARK: - Chat Completions

    public struct ChatCompletionRequest: Content {
        public var model: String
        public var messages: [Message]
        public var temperature: Float?
        public var topP: Float?
        public var maxTokens: Int?

        public init(model: String, messages: [Message], temperature: Float? = nil, topP: Float? = nil, maxTokens: Int? = nil) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.topP = topP
            self.maxTokens = maxTokens
        }

        public enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case topP = "top_p"
            case maxTokens = "max_tokens"
        }

        public struct Message: Codable, Sendable {
            public var role: String
            public var content: MessageContent

            public init(role: String, content: String) {
                self.role = role
                self.content = .text(content)
            }

            public init(role: String, content: MessageContent) {
                self.role = role
                self.content = content
            }
        }

        public enum MessageContent: Codable, Sendable {
            case text(String)
            case parts([ContentPart])

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    self = .text("")  // OpenAI allows null content (e.g. assistant messages)
                } else if let str = try? container.decode(String.self) {
                    self = .text(str)
                } else {
                    self = .parts(try container.decode([ContentPart].self))
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let str): try container.encode(str)
                case .parts(let parts): try container.encode(parts)
                }
            }

            public var rawText: String {
                switch self {
                case .text(let str):
                    return str
                case .parts(let parts):
                    return parts.compactMap(\.text).joined(separator: "\n")
                }
            }
        }

        /// A content part. Only `text` is processed; other types (images, audio, documents) are rejected.
        public struct ContentPart: Codable, Sendable {
            public var type: String
            public var text: String?

            public init(type: String = "text", text: String?) {
                self.type = type
                self.text = text
            }
        }
    }

    public struct ChatCompletionResponse: Content {
        public let id: String
        public var object: String
        public let created: Int
        public let model: String
        public let choices: [Choice]
        public let usage: Usage?

        public init(id: String, created: Int, model: String, choices: [Choice], usage: Usage? = nil, object: String = "chat.completion") {
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

    public struct ModelListResponse: Content {
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

            public init(id: String, created: Int = Int(Date().timeIntervalSince1970), ownedBy: String = "apple", object: String = "model") {
                self.id = id
                self.object = object
                self.created = created
                self.ownedBy = ownedBy
            }

            public enum CodingKeys: String, CodingKey {
                case id, object, created
                case ownedBy = "owned_by"
            }
        }
    }

    // MARK: - Errors

    public struct ErrorResponse: Content {
        public let error: ErrorDetail

        public init(error: ErrorDetail) {
            self.error = error
        }

        public struct ErrorDetail: Codable, Sendable {
            public let message: String
            public let type: String
            public let param: String?
            public let code: String?

            public init(message: String, type: String, param: String? = nil, code: String? = nil) {
                self.message = message
                self.type = type
                self.param = param
                self.code = code
            }
        }
    }
}

// MARK: - Request Prompt Helpers

public extension OpenAI.ChatCompletionRequest {
    /// System messages, passed to the session as instructions.
    var systemInstructions: String {
        messages
            .filter { $0.role == "system" }
            .map { $0.content.rawText }
            .joined(separator: "\n\n")
    }

    /// All other messages, joined into a single prompt.
    var combinedPrompt: String {
        messages
            .filter { $0.role != "system" }
            .map { $0.content.rawText }
            .joined(separator: "\n\n")
    }
}
