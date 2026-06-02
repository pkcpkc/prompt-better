import Foundation
import FoundationModels

// MARK: - Core Promotion Types

/// Represents a prompt definition loaded from a JSON file.
/// This is the single source of truth for both structural field definitions and AI instructions.
public struct AIPrompt: Codable {
    public let name: String
    public let instructions: String
    public let metadata: Metadata
    public let config: Config
    public let fields: [String: FieldDefinition]

    public struct Metadata: Codable {
        public let version: String
        public let author: String
    }

    public struct Config: Codable {
        public let modelId: String
        public let temperature: Double
        public let topP: Double
        public let topK: Int
        public let maxTokens: Int
        public let stopSequences: [String]

        enum CodingKeys: String, CodingKey {
            case modelId = "model_id"
            case temperature
            case topP = "top_p"
            case topK = "top_k"
            case maxTokens = "max_tokens"
            case stopSequences = "stop_sequences"
        }
    }

    public struct FieldDefinition: Codable {
        public let type: String
        public let desc: String
        public let items: String?
        public let minCount: Int?
        public let maxCount: Int?

        enum CodingKeys: String, CodingKey {
            case type
            case desc
            case items
            case minCount = "min_count"
            case maxCount = "max_count"
        }
    }
}


// MARK: - Bridge to Apple's GenerationOptions

public extension AIPrompt.Config {
    /// Converts the JSON configuration to Apple's `LanguageModel.GenerationOptions`.
    @available(iOS 26.0, *)
    func toGenerationOptions() -> GenerationOptions {
        var options = GenerationOptions()
        if temperature > 0.0 {
            options.sampling = .random(probabilityThreshold: topP)
        } else {
            options.sampling = .greedy
        }
        options.maximumResponseTokens = maxTokens
        return options
    }
}
