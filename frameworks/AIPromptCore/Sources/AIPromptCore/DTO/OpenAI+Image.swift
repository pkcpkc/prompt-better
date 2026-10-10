import Foundation

public extension OpenAI {
    
    // MARK: - Image Generation
    
    struct ImageGenerationRequest: Codable, Sendable {
        public var prompt: String
        public var model: String
        public var n: Int?
        public var quality: String? // "standard", "hd"
        public var responseFormat: String? // "b64_json", "url"
        public var size: String? // "1024x1024", "512x512", etc.
        public var style: String? // "vivid", "natural", or Apple styles: "animation", "illustration", "sketch"
        public var user: String?
        
        public init(
            prompt: String,
            model: String = "apple-image-playground",
            n: Int? = 1,
            quality: String? = "standard",
            responseFormat: String? = "b64_json",
            size: String? = "1024x1024",
            style: String? = nil,
            user: String? = nil
        ) {
            self.prompt = prompt
            self.model = model
            self.n = n
            self.quality = quality
            self.responseFormat = responseFormat
            self.size = size
            self.style = style
            self.user = user
        }
        
        public enum CodingKeys: String, CodingKey {
            case prompt, model, n, quality, size, style, user
            case responseFormat = "response_format"
        }
    }
    
    struct ImageGenerationResponse: Codable, Sendable {
        public var created: Int
        public var data: [ImageObject]
        
        public init(created: Int = Int(Date().timeIntervalSince1970), data: [ImageObject]) {
            self.created = created
            self.data = data
        }
    }
    
    struct ImageObject: Codable, Sendable {
        public var b64Json: String?
        public var url: String?
        public var revisedPrompt: String?
        
        public init(b64Json: String? = nil, url: String? = nil, revisedPrompt: String? = nil) {
            self.b64Json = b64Json
            self.url = url
            self.revisedPrompt = revisedPrompt
        }
        
        public enum CodingKeys: String, CodingKey {
            case url
            case b64Json = "b64_json"
            case revisedPrompt = "revised_prompt"
        }
    }
}
