import Foundation
import FoundationModels

/// Runs chat completions on FoundationModels, one at a time.
///
/// Each request gets a fresh session: system messages become the instructions and the remaining messages
/// are joined into one prompt.
public actor ChatCompletionService {
    public static let shared = ChatCompletionService()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public func complete(_ request: OpenAI.ChatCompletionRequest) async throws -> OpenAI.ChatCompletionResponse {
        guard let model = BridgeModel.resolve(request.model) else {
            throw OpenAIAPIError.modelNotFound(request.model)
        }
        try Self.requireTextOnly(request.messages)

        let instructions = request.systemInstructions
        let prompt = request.combinedPrompt
        let options = Self.generationOptions(for: request)

        let text = try await runSerialized {
            let session = LanguageModelSession(model: model.languageModel, instructions: instructions.isEmpty ? nil : instructions)
            do {
                return try await session.respond(to: prompt, options: options).content
            } catch LanguageModelSession.GenerationError.guardrailViolation {
                throw OpenAIAPIError.contentPolicyViolation
            } catch let error where Self.isGuardrailMessage(error.localizedDescription) {
                throw OpenAIAPIError.contentPolicyViolation
            }
        }

        return OpenAI.ChatCompletionResponse(
            id: "chatcmpl-\(UUID().uuidString)",
            created: Int(Date().timeIntervalSince1970),
            model: model.rawValue,
            choices: [.init(index: 0, message: .init(content: text), finishReason: "stop")],
            usage: .init()
        )
    }

    /// `temperature == 0` selects greedy decoding; otherwise `top_p` selects nucleus sampling.
    static func generationOptions(for request: OpenAI.ChatCompletionRequest) -> GenerationOptions {
        var options = GenerationOptions()
        if let temperature = request.temperature {
            if temperature == 0 {
                options.samplingMode = .greedy
            } else if let topP = request.topP {
                options.samplingMode = .random(probabilityThreshold: Double(topP))
            }
        }
        if let maxTokens = request.maxTokens {
            options.maximumResponseTokens = maxTokens
        }
        return options
    }

    /// Non-text parts would otherwise be silently dropped from the prompt.
    static func requireTextOnly(_ messages: [OpenAI.ChatCompletionRequest.Message]) throws {
        for message in messages {
            guard case .parts(let parts) = message.content else { continue }
            if let part = parts.first(where: { $0.type != "text" }) {
                throw OpenAIAPIError.unsupportedOperation(
                    "Content part type '\(part.type)' is not supported by this bridge; send text only."
                )
            }
        }
    }

    private static func isGuardrailMessage(_ message: String) -> Bool {
        ["Safety guardrails", "unsafe", "guardrail", "safety"].contains { message.localizedCaseInsensitiveContains($0) }
    }

    private func runSerialized<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        defer {
            if waiters.isEmpty {
                isBusy = false
            } else {
                waiters.removeFirst().resume()
            }
        }
        return try await operation()
    }
}
