import Vapor
import AIPromptCore
import FoundationModels

/// A typed error that renders as an OpenAI-style error envelope.
public struct OpenAIAPIError: Error, Sendable {
    public var status: HTTPStatus
    public var type: String
    public var code: String
    public var message: String
    public var param: String?

    public init(status: HTTPStatus, type: String = "api_error", code: String, message: String, param: String? = nil) {
        self.status = status
        self.type = type
        self.code = code
        self.message = message
        self.param = param
    }

    public static func modelNotFound(_ id: String) -> OpenAIAPIError {
        OpenAIAPIError(
            status: .notFound,
            type: "invalid_request_error",
            code: "model_not_found",
            message: "Model '\(id)' not found.",
            param: "model"
        )
    }

    public static func unsupportedOperation(_ reason: String) -> OpenAIAPIError {
        OpenAIAPIError(status: .badRequest, type: "invalid_request_error", code: "unsupported_operation", message: reason)
    }

    /// Throws `model_not_found` unless the registry knows `id`.
    public static func requireModel(_ id: String) throws {
        guard ModelRegistry.isSupported(modelId: id) else { throw modelNotFound(id) }
    }
}

/// Maps every error thrown by a route to the OpenAI error response shape.
public struct OpenAIErrorMiddleware: AsyncMiddleware {
    public init() {}

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            let mapped = Self.map(error)
            let detail = OpenAI.ErrorResponse.ErrorDetail(
                message: mapped.message,
                type: mapped.type,
                param: mapped.param,
                code: mapped.code
            )
            let data = try JSONEncoder().encode(OpenAI.ErrorResponse(error: detail))
            return Response(status: mapped.status, headers: ["Content-Type": "application/json"], body: .init(data: data))
        }
    }

    static func map(_ error: Error) -> OpenAIAPIError {
        switch error {
        case let e as OpenAIAPIError:
            return e
        case let e as AIError:
            switch e {
            case .guardrailsTriggered:
                return OpenAIAPIError(status: .badRequest, type: "invalid_request_error", code: "content_policy_violation", message: "The request was rejected by safety guardrails.")
            case .modelNotFound(let name):
                return .modelNotFound(name)
            case .noActiveSession:
                return OpenAIAPIError(status: .internalServerError, code: "no_active_session", message: "Language model session could not be established.")
            case .promptNotFound(let name):
                return OpenAIAPIError(status: .notFound, type: "invalid_request_error", code: "prompt_not_found", message: "Prompt '\(name)' not found.")
            case .unsupportedOperation(let reason):
                return .unsupportedOperation(reason)
            }
        case let e as LanguageModelSession.GenerationError:
            switch e {
            case .exceededContextWindowSize:
                return OpenAIAPIError(status: .badRequest, type: "invalid_request_error", code: "context_length_exceeded", message: "This model's maximum context length is 4096 tokens.")
            case .rateLimited:
                return OpenAIAPIError(status: .tooManyRequests, type: "insufficient_quota", code: "rate_limit_exceeded", message: "You exceeded your current quota for Private Cloud Compute.")
            case .concurrentRequests:
                return OpenAIAPIError(status: .serviceUnavailable, type: "requests_limit_error", code: "concurrent_requests_limit", message: "The model is currently processing another request.")
            case .guardrailViolation:
                return OpenAIAPIError(status: .badRequest, type: "invalid_request_error", code: "content_policy_violation", message: "The request was rejected by safety guardrails.")
            default:
                return OpenAIAPIError(status: .internalServerError, code: "unknown_model_error", message: e.localizedDescription)
            }
        case let e as ImageGenerationError:
            return OpenAIAPIError(status: .serviceUnavailable, code: "image_generation_unavailable", message: e.localizedDescription)
        case let e as AbortError:
            return OpenAIAPIError(status: e.status, type: type(for: e.status), code: "api_error", message: e.reason)
        default:
            return OpenAIAPIError(status: .internalServerError, code: "internal_error", message: error.localizedDescription)
        }
    }

    private static func type(for status: HTTPStatus) -> String {
        switch status {
        case .badRequest, .notFound, .unprocessableEntity: return "invalid_request_error"
        case .tooManyRequests: return "insufficient_quota"
        case .serviceUnavailable: return "requests_limit_error"
        default: return "api_error"
        }
    }
}
