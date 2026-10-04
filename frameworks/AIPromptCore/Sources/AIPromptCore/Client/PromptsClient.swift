import Foundation
import FoundationModels

@MainActor
public final class PromptsClient: Sendable {
    public init() {}
    
    /// Generates a type conforming to GenerableWithPrompt using its built-in template.
    public func generate<T: GenerableWithPrompt>(
        _ type: T.Type,
        input: String = "",
        context: [String: String] = [:]
    ) async throws -> T {
        return try await AISessionController.shared.respond(to: input, context: context, generating: type)
    }
    
    /// Executes a precompiled AIPrompt JSON definition with runtime input and parameters.
    public func execute(
        _ prompt: AIPrompt,
        input: String = "",
        context: [String: String] = [:]
    ) async throws -> String {
        var rendered = prompt.instructions
        for (key, val) in context {
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: val)
        }
        if !input.isEmpty {
            rendered += "\n\nInput:\n\(input)"
        }
        
        let options = prompt.config.toGenerationOptions()
        return try await AISessionController.shared.respond(to: rendered, options: options)
    }
}
