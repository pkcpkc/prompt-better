import Foundation
import FoundationModels

// MARK: - Compatibility Mocks for compilation in OS 26 (Sequoia/macOS 15) environment
#if !canImport(ClaudeForFoundationModels)
public protocol LanguageModel: Sendable {}

extension SystemLanguageModel: LanguageModel {}

public struct PrivateCloudComputeLanguageModel: LanguageModel {
    public init() {}
}

extension LanguageModelSession {
    public convenience init(model: any LanguageModel, instructions: String? = nil) {
        let systemModel = (model as? SystemLanguageModel) ?? SystemLanguageModel.default
        self.init(model: systemModel, tools: [], instructions: instructions)
    }
}
#endif

// MARK: - Canonical Model Enumeration

public enum CanonicalModel: String, CaseIterable, Sendable {
    // 1. Raw AFM Models (Direct text inference without perception/RAG)
    case defaultAFM = "default"
    case foundationModel3B = "apple-foundation-model-3-core-3b"
    case foundationModelGeneric = "apple-foundation-model"
    case privateCloudCompute = "apple-intelligence-private-cloud-compute"

    // 2. Multimodal & RAG Model
    case foundationOmni = "apple-foundation-omni"

    // 3. Standalone Direct Models (Bypass LLM)
    case visionOCR = "apple-vision-ocr"
    case pdfExtractor = "apple-pdf-extractor"
    case translation = "apple-translation"
    case nlTagger = "apple-nl-tagger"

    // 4. Audio Models
    case speechTranscribe = "apple-speech-transcribe"
    case speechSynthesize = "apple-speech-synthesize"
    case speechTranslate = "apple-speech-translate"

    // 5. Embedding Models
    case sentenceEmbedding = "apple-sentence-embedding"
    case wordEmbedding = "apple-word-embedding"
    case visionFeaturePrint = "apple-vision-featureprint"

    // 6. Moderation Model
    case sensitiveContent = "apple-sensitive-content"

    // 7. Search & RAG Model
    case localSearch = "apple-local-search"

    // 8. Image Generation Models
    case imagePlayground = "apple-image-playground"
    case imageCreator = "apple-image-creator"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .defaultAFM, .foundationModel3B, .foundationModelGeneric:
            return "Apple Foundation Model (On-Device): \(ModelRegistry.systemDefaultConcreteName)"
        case .privateCloudCompute:
            return "Apple Intelligence Private Cloud Compute (PCC)"
        case .foundationOmni:
            return "Apple Foundation Omni (Multimodal Speech/Vision + Local RAG)"
        case .visionOCR:
            return "Apple Vision OCR (On-Device Text Recognition)"
        case .pdfExtractor:
            return "Apple PDFKit Text & Vector Extractor"
        case .translation:
            return "Apple Neural Machine Translation"
        case .nlTagger:
            return "Apple Natural Language Linguistic Tagger & NER"
        case .speechTranscribe:
            return "Apple Speech-to-Text (On-Device Neural Engine)"
        case .speechSynthesize:
            return "Apple Speech Synthesis (Siri Neural)"
        case .speechTranslate:
            return "Apple Speech-to-English Translation"
        case .sentenceEmbedding:
            return "Apple Sentence Embedding (512-dim Dense Vectors)"
        case .wordEmbedding:
            return "Apple Word Embedding"
        case .visionFeaturePrint:
            return "Apple Vision Feature Print (Visual Embeddings)"
        case .sensitiveContent:
            return "Apple Sensitive Content & Safety Moderation"
        case .localSearch:
            return "Apple Local Hybrid Search (CoreSpotlight + Vector RAG)"
        case .imagePlayground:
            return "Apple Image Playground (Interactive UI Generation)"
        case .imageCreator:
            return "Apple Image Creator (Programmatic On-Device Image Generation)"
        }
    }
}

// MARK: - Model Registry

public enum ModelRegistry: Sendable {
    
    public static var defaultModelId: String { CanonicalModel.defaultAFM.rawValue }
    public static var omniModelId: String { CanonicalModel.foundationOmni.rawValue }

    /// Concrete on-device model backing `SystemLanguageModel.default`, as reported by the system.
    public static var systemDefaultConcreteName: String {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            return SystemLanguageModel.default.variant.displayName
        }
        return "Apple On-Device Foundation Model (3B)"
    }

    /// Diagnostics string for startup logging.
    public static var systemModelDiagnostics: String {
        let model = SystemLanguageModel.default
        var parts = ["System model: \(systemDefaultConcreteName)"]
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            switch model.variant {
            case .coreAdvanced3: parts.append("variant: coreAdvanced3")
            case .core3: parts.append("variant: core3")
            default: parts.append("variant: unknown")
            }
        }
        parts.append("context: \(model.contextSize) tokens")
        parts.append("availability: \(model.availability)")
        return parts.joined(separator: ", ")
    }

    /// Resolves any model name (handling custom aliases and standard OpenAI aliases) to its canonical model ID.
    public static func resolveCanonicalId(_ modelId: String) -> String {
        return AliasConfiguration.shared.resolve(modelName: modelId)
    }

    /// Checks if a model name is supported (either natively, via custom alias, or standard OpenAI alias).
    public static func isSupported(modelId: String) -> Bool {
        let canonical = resolveCanonicalId(modelId)
        return CanonicalModel.allCases.contains { $0.rawValue == canonical }
    }

    /// Returns true if the requested model is a direct raw AFM model (bypassing perception and RAG).
    public static func isRawAFM(modelId: String) -> Bool {
        let canonical = resolveCanonicalId(modelId)
        switch canonical {
        case CanonicalModel.defaultAFM.rawValue,
             CanonicalModel.foundationModel3B.rawValue,
             CanonicalModel.foundationModelGeneric.rawValue,
             CanonicalModel.privateCloudCompute.rawValue:
            return true
        default:
            return false
        }
    }

    /// Lists canonical model identifiers for UI pickers.
    public static var availableModelIds: [String] {
        CanonicalModel.allCases.map(\.rawValue)
    }

    /// Resolves the concrete LanguageModel instance for FoundationModels execution.
    public static func resolveLanguageModel(name: String) -> any LanguageModel {
        let canonical = resolveCanonicalId(name)
        if canonical == CanonicalModel.privateCloudCompute.rawValue {
            return PrivateCloudComputeLanguageModel()
        }
        return SystemLanguageModel.default
    }

    /// Compatibility alias for resolveLanguageModel
    public static func resolveModel(name: String) -> any LanguageModel {
        return resolveLanguageModel(name: name)
    }

    /// Lists all models to advertise via GET /v1/models (including active custom aliases and OpenAI aliases if enabled).
    public static func listModels() -> [OpenAI.ModelListResponse.Model] {
        var models: [OpenAI.ModelListResponse.Model] = []
        
        // 1. Native Canonical Models
        for model in CanonicalModel.allCases {
            models.append(.init(id: model.rawValue, ownedBy: "apple"))
        }

        // 2. Custom Aliases
        let customAliases = AliasConfiguration.shared.customAliases
        for (alias, _) in customAliases {
            models.append(.init(id: alias, ownedBy: "user"))
        }

        // 3. OpenAI Standard Aliases (if enabled)
        if AliasConfiguration.shared.enableOpenAIAliases {
            let openAIAliases = [
                "gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo",
                "whisper-1", "tts-1", "tts-1-hd",
                "text-embedding-3-small", "text-embedding-ada-002",
                "text-moderation-latest",
                "dall-e-3", "dall-e-2"
            ]
            for alias in openAIAliases {
                models.append(.init(id: alias, ownedBy: "openai-alias"))
            }
        }

        return models
    }

    public static func displayName(for modelId: String) -> String {
        let canonical = resolveCanonicalId(modelId)
        if let model = CanonicalModel(rawValue: canonical) {
            return model.displayName
        }
        return modelId
    }
}
