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

@MainActor
final class LocalAIBridge {
  static let shared = LocalAIBridge()

  private init() {}

  /// Generates a response using the local FoundationModels framework.
  func generate(request: OpenAI.ChatCompletionRequest, headers: HTTPHeaders) async throws -> String {
    let modelName = request.model
    
    // Check if the requested model is allowed on the current compiled system version
    guard getAvailableModelIds().contains(modelName) else {
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
    #if canImport(ClaudeForFoundationModels)
    // Full OS 27+ Model Capabilities (Edge & PCC only)
    return [
      "apple_intelligence_on_device",
      "apple_intelligence_private_cloud"
    ]
    #else
    // OS 26 supports on-device only explicitly (no user confusion)
    return ["apple_intelligence_on_device"]
    #endif
  }

  private func resolveModel(name: String) -> any LanguageModel {
    #if canImport(ClaudeForFoundationModels)
    if name == "apple_intelligence_private_cloud" {
      return PrivateCloudComputeLanguageModel()
    }
    return SystemLanguageModel.default
    #else
    // Under OS 26 fallback, everything routes to local SystemLanguageModel
    return SystemLanguageModel.default
    #endif
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
