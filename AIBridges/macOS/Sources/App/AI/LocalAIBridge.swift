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
    case afm3Core3B = "apple-foundation-model-3-core-3b"
    case afm3CoreAdvanced20BSparse = "apple-foundation-model-3-core-advanced-20b-sparse"
    case privateCloudCompute = "apple-intelligence-private-cloud-compute"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .afm3Core3B:
            return "AFM 3 Core (3B)"
        case .afm3CoreAdvanced20BSparse:
            return "AFM 3 Core Advanced (20B Sparse)"
        case .privateCloudCompute:
            return "Private Cloud Compute (PCC)"
        }
    }
}

public enum ModelRegistry: Sendable {
    public typealias Model = ModelName

    public static var onDeviceModel: ModelName {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Double(ramBytes) / (1024.0 * 1024.0 * 1024.0)
        
        // iOS 27+ / macOS 27+ with >= 12 GB RAM
        if osVersion.majorVersion >= 27 && ramGB >= 12.0 {
            return .afm3CoreAdvanced20BSparse
        } else {
            return .afm3Core3B
        }
    }
    
    public static var onDeviceModelId: String {
        onDeviceModel.rawValue
    }
    
    public static let privateCloudComputeModel: ModelName = .privateCloudCompute
    public static let privateCloudComputeModelId: String = ModelName.privateCloudCompute.rawValue
    
    public static var availableModels: [ModelName] {
        [
            onDeviceModel,
            privateCloudComputeModel
        ]
    }

    public static var availableModelIds: [String] {
        availableModels.map(\.rawValue)
    }

    public static func resolveModel(name: String) -> any LanguageModel {
        guard let model = ModelName(rawValue: name) else {
            return SystemLanguageModel.default
        }
        return resolveModel(model: model)
    }

    public static func resolveModel(model: ModelName) -> any LanguageModel {
        switch model {
        case .privateCloudCompute:
            return PrivateCloudComputeLanguageModel()
        case .afm3Core3B, .afm3CoreAdvanced20BSparse:
            return SystemLanguageModel.default
        }
    }

    public static func displayName(for modelId: String) -> String {
        ModelName(rawValue: modelId)?.displayName ?? modelId
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
