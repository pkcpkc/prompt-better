import FoundationModels
import Vapor

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

// MARK: - Model Names & Registry

public enum ModelName: String, CaseIterable, Sendable {
    case defaultModel = "default"
    case privateCloudCompute = "apple-intelligence-private-cloud-compute"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .defaultModel:
            return "System Default: \(ModelRegistry.systemDefaultConcreteName)"
        case .privateCloudCompute:
            return "Apple Intelligence Private Cloud Compute (PCC)"
        }
    }
}

public enum ModelRegistry: Sendable {
    public typealias Model = ModelName

    public static let defaultModel: ModelName = .defaultModel
    public static let defaultModelId: String = ModelName.defaultModel.rawValue
    
    /// Concrete on-device model backing `SystemLanguageModel.default`, as reported by the system.
    /// On OS 27+ this is `SystemLanguageModel.variant` (`.core3` or `.coreAdvanced3`).
    public static var systemDefaultConcreteName: String {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            return SystemLanguageModel.default.variant.displayName
        }
        return "Apple On-Device Foundation Model (3B)"
    }

    /// One-line description of the active system model for startup logging.
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

    public static let privateCloudComputeModel: ModelName = .privateCloudCompute
    public static let privateCloudComputeModelId: String = ModelName.privateCloudCompute.rawValue
    
    public static var availableModels: [ModelName] {
        [
            defaultModel,
            privateCloudComputeModel
        ]
    }

    public static var availableModelIds: [String] {
        availableModels.map(\.rawValue)
    }

    public static func isSupported(modelId: String) -> Bool {
        let normalized = modelId.hasPrefix("openai/") ? String(modelId.dropFirst("openai/".count)) : modelId
        return availableModelIds.contains(normalized)
    }

    public static func resolveModel(name: String) -> any LanguageModel {
        let normalized = name.hasPrefix("openai/") ? String(name.dropFirst("openai/".count)) : name
        guard let model = ModelName(rawValue: normalized) else {
            return SystemLanguageModel.default
        }
        return resolveModel(model: model)
    }

    public static func resolveModel(model: ModelName) -> any LanguageModel {
        switch model {
        case .privateCloudCompute:
            return PrivateCloudComputeLanguageModel()
        case .defaultModel:
            return SystemLanguageModel.default
        }
    }

    public static func displayName(for modelId: String) -> String {
        let normalized = modelId.hasPrefix("openai/") ? String(modelId.dropFirst("openai/".count)) : modelId
        return ModelName(rawValue: normalized)?.displayName ?? modelId
    }
}

@MainActor
final class LocalAIBridge {
  static let shared = LocalAIBridge()

  private init() {}

  /// Generates a response using the local FoundationModels framework.
  func generate(request: OpenAI.ChatCompletionRequest, headers: HTTPHeaders) async throws -> String {
    let modelName = request.model
    
    // Check if the requested model is allowed on the current compiled system version
    guard ModelRegistry.isSupported(modelId: modelName) else {
      throw Abort(.notFound, reason: "Model '\(modelName)' not found.")
    }

    let systemInstructions = request.systemInstructions
    let combinedPrompt = request.combinedPrompt

    // Create the generation options from the request
    var options = GenerationOptions()
    if let temp = request.temperature { options.temperature = Double(temp) }

    if let topP = request.topP {
      options.sampling = .random(probabilityThreshold: Double(topP))
    }

    if let maxTokens = request.maxTokens {
      options.maximumResponseTokens = maxTokens
    }
    // stopSequences not supported in this version of Mac SDK

    // Resolve the appropriate model conforming to LanguageModel
    let resolvedModel = resolveModel(name: modelName)
    
    // Initialize session with the resolved model
    let session = systemInstructions.isEmpty ? 
      LanguageModelSession(model: resolvedModel) : 
      LanguageModelSession(model: resolvedModel, instructions: systemInstructions)
      
    do {
      let response = try await session.respond(
        to: combinedPrompt,
        options: options
      )
      return response.content
    } catch {
      throw mapNativeError(error)
    }
  }

  /// Lists all available models in the local framework.
  func listModels() async -> [OpenAI.ModelListResponse.Model] {
    return getAvailableModelIds().map { .init(id: $0) }
  }

  // MARK: - Internal Routing Helpers

  private func getAvailableModelIds() -> [String] {
    return ModelRegistry.availableModelIds
  }

  private func resolveModel(name: String) -> any LanguageModel {
    return ModelRegistry.resolveModel(name: name)
  }

  private func mapNativeError(_ error: Error) -> Abort {
    if let genError = error as? LanguageModelSession.GenerationError {
      switch genError {
      case .exceededContextWindowSize:
        return Abort(.badRequest, reason: "context_length_exceeded: This model's maximum context length is 4096 tokens.")
      case .rateLimited:
        return Abort(.tooManyRequests, reason: "rate_limit_exceeded: You exceeded your current quota for Private Cloud Compute.")
      case .concurrentRequests:
        return Abort(.serviceUnavailable, reason: "concurrent_requests_limit: The model is currently processing another request.")
      case .guardrailViolation:
        return Abort(.badRequest, reason: "content_policy_violation: The request was rejected by safety guardrails.")
      default:
        return Abort(.internalServerError, reason: "unknown_model_error: \(error.localizedDescription)")
      }
    }
    return Abort(.internalServerError, reason: "generation_failed: \(error.localizedDescription)")
  }
}
