import Foundation
import FoundationModels
import Vapor
import AIPromptCore

// MARK: - Backward Compatibility ModelName Alias for existing tests

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

@MainActor
final class LocalAIBridge {
    static let shared = LocalAIBridge()

    private init() {}

    /// Generates a response using the local FoundationModels framework via AppleOpenAIClient.
    func generate(request: OpenAI.ChatCompletionRequest, headers: HTTPHeaders) async throws -> String {
        let modelName = request.model
        
        // Validate if the model is supported
        guard ModelRegistry.isSupported(modelId: modelName) else {
            throw Abort(.notFound, reason: "Model '\(modelName)' not found.")
        }

        do {
            let response = try await AppleOpenAIClient.shared.chat.completions.create(request: request)
            return response.choices.first?.message.content ?? ""
        } catch let aiError as AIError {
            switch aiError {
            case .guardrailsTriggered:
                throw Abort(.badRequest, reason: "content_policy_violation: The request was rejected by safety guardrails.")
            case .modelNotFound(let name):
                throw Abort(.notFound, reason: "Model '\(name)' not found.")
            case .noActiveSession:
                throw Abort(.internalServerError, reason: "no_active_session: Language model session could not be established.")
            case .promptNotFound(let name):
                throw Abort(.notFound, reason: "Prompt '\(name)' not found.")
            case .unsupportedOperation(let op):
                throw Abort(.badRequest, reason: "unsupported_operation: \(op)")
            }
        } catch let abortError as AbortError {
            throw abortError
        } catch {
            throw mapNativeError(error)
        }
    }

    /// Lists all available models in the local framework.
    func listModels() async -> [OpenAI.ModelListResponse.Model] {
        return ModelRegistry.listModels()
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
