import Vapor
import AIPromptCore
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

func routes(_ app: Application) throws {
    
    // MARK: - OpenAI Compatibility
    
    // Route: POST /v1/chat/completions
    app.post("v1", "chat", "completions") { req async throws in
        let completionRequest = try req.content.decode(OpenAI.ChatCompletionRequest.self)
        
        let modelName = completionRequest.model
        guard ModelRegistry.isSupported(modelId: modelName) else {
            // Formulate standard OpenAI not found error
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: "Model '\(modelName)' not found.",
                type: "invalid_request_error",
                param: "model",
                code: "model_not_found"
            )
            let errorResponse = OpenAI.ErrorResponse(error: errorDetail)
            let data = try JSONEncoder().encode(errorResponse)
            return Response(status: .notFound, headers: ["Content-Type": "application/json"], body: .init(data: data))
        }
        
        let systemInstructions = completionRequest.systemInstructions
        let combinedPrompt = completionRequest.combinedPrompt
        
        // Prepare options
        var options = GenerationOptions()
        if let temp = completionRequest.temperature {
            options.sampling = .random(probabilityThreshold: Double(completionRequest.topP ?? 1.0))
            if temp == 0 {
                options.sampling = .greedy
            }
        } else {
            options.sampling = .greedy
        }
        
        if let maxTokens = completionRequest.maxTokens {
            options.maximumResponseTokens = maxTokens
        }

        // Resolve model and session dynamically
        let resolvedModel = resolveModel(name: modelName)
        let session = systemInstructions.isEmpty ? 
            LanguageModelSession(model: resolvedModel) : 
            LanguageModelSession(model: resolvedModel, instructions: systemInstructions)
            
        do {
            let response = try await session.respond(to: combinedPrompt, options: options)
            let responseText = response.content
            
            let chatResponse = OpenAI.ChatCompletionResponse(
                id: "chatcmpl-\(UUID().uuidString)",
                created: Int(Date().timeIntervalSince1970),
                model: completionRequest.model,
                choices: [
                    .init(
                        index: 0,
                        message: .init(content: responseText),
                        finishReason: "stop"
                    )
                ],
                usage: .init(
                    promptTokens: 0,
                    completionTokens: 0,
                    totalTokens: 0
                )
            )
            let data = try JSONEncoder().encode(chatResponse)
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
        } catch let abortError as AbortError {
            let reason = abortError.reason
            let code: String?
            let message: String
            
            if reason.contains(":") {
                let parts = reason.split(separator: ":", maxSplits: 1).map(String.init)
                code = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                message = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                code = "api_error"
                message = reason
            }
            
            let type: String
            switch abortError.status {
            case .badRequest:
                type = "invalid_request_error"
            case .tooManyRequests:
                type = "insufficient_quota"
            case .serviceUnavailable:
                type = "requests_limit_error"
            default:
                type = "api_error"
            }
            
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: message,
                type: type,
                param: nil,
                code: code
            )
            let errorResponse = OpenAI.ErrorResponse(error: errorDetail)
            let data = try JSONEncoder().encode(errorResponse)
            return Response(status: abortError.status, headers: ["Content-Type": "application/json"], body: .init(data: data))
        } catch {
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: error.localizedDescription,
                type: "api_error",
                param: nil,
                code: "internal_error"
            )
            let errorResponse = OpenAI.ErrorResponse(error: errorDetail)
            let data = try JSONEncoder().encode(errorResponse)
            return Response(status: .internalServerError, headers: ["Content-Type": "application/json"], body: .init(data: data))
        }
    }
    
    // Route: GET /v1/models
    app.get("v1", "models") { req async in
        let models = getAvailableModelIds().map { OpenAI.ModelListResponse.Model(id: $0) }
        return OpenAI.ModelListResponse(data: models)
    }
    
    // Simple health check
    app.get("health") { req in
        "iOS Bridge is running on port \(app.http.server.configuration.port)"
    }
}

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

public enum ModelRegistry {
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

// MARK: - Routing Helpers

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
