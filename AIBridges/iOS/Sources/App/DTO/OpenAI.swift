import Vapor

enum OpenAI {
    struct ChatCompletionRequest: Content {
        let model: String
        let messages: [Message]
        let temperature: Float?
        let topP: Float?
        let maxTokens: Int?
        let stream: Bool?
        let stop: [String]?
        
        struct Message: Content {
            let role: String
            let content: String
        }
        
        enum CodingKeys: String, CodingKey {
            case model, messages, temperature, stream, stop
            case topP = "top_p"
            case maxTokens = "max_tokens"
        }
    }
    
    struct ChatCompletionResponse: Content {
        let id: String
        var object: String = "chat.completion"
        let created: Int
        let model: String
        let choices: [Choice]
        let usage: Usage?
        
        struct Choice: Content {
            let index: Int
            let message: Message
            let finishReason: String?
            
            enum CodingKeys: String, CodingKey {
                case index, message
                case finishReason = "finish_reason"
            }
        }
        
        struct Message: Content {
            var role: String = "assistant"
            let content: String
        }
        
        struct Usage: Content {
            let promptTokens: Int
            let completionTokens: Int
            let totalTokens: Int
            
            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
            }
        }
    }
    
    struct ModelListResponse: Content {
        var object: String = "list"
        let data: [Model]
        
        struct Model: Content {
            let id: String
            var object: String = "model"
            var created: Int = Int(Date().timeIntervalSince1970)
            var ownedBy: String = "apple"
            
            enum CodingKeys: String, CodingKey {
                case id, object, created
                case ownedBy = "owned_by"
            }
        }
    }
}

extension OpenAI.ChatCompletionRequest {
    var systemInstructions: String {
        messages
            .filter { $0.role == "system" }
            .map { $0.content }
            .joined(separator: "\n\n")
    }

    var combinedPrompt: String {
        messages
            .filter { $0.role != "system" }
            .map { $0.content }
            .joined(separator: "\n\n")
    }
}
