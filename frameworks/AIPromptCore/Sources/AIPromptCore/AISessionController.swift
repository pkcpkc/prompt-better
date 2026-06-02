import Foundation
import FoundationModels

@MainActor
public final class AISessionController {
  public static let shared = AISessionController()
  private var session: LanguageModelSession?

  private init() {}

  /// Sends a prompt built from the type's template to the language model.
  /// - Parameters:
  ///   - input: Primary input text (replaces `{input}` in the template)
  ///   - context: Additional named values (replace `{key}` placeholders)
  ///   - type: The `GenerableWithPrompt` type to generate
  ///   - createNewSession: If true, creates a new session; otherwise uses the existing one
  public func respond<T: GenerableWithPrompt>(
    to input: String = "",
    context: [String: String] = [:],
    generating type: T.Type,
    createNewSession: Bool = false
  ) async throws -> T {
    if createNewSession {
      let newSession = LanguageModelSession()
      self.session = newSession
    }
    guard let session = self.session else { throw AIError.noActiveSession }
    let prompt = T.buildSystemPrompt(for: input, context: context)
    do {
      let options =
        T.options
        ?? {
          var o = GenerationOptions()
          o.sampling = .greedy
          return o
        }()
      let response = try await session.respond(to: prompt, generating: type, options: options)
      return response.content
    } catch let error where error.localizedDescription.contains("Safety guardrails") {
      throw AIError.guardrailsTriggered
    }
  }

  /// Sends a raw string prompt to the language model and returns the response content.
  public func respond(to prompt: String, options: GenerationOptions? = nil) async throws -> String {
    let session = try await ensureSession()
    let generationOptions = options ?? {
      var o = GenerationOptions()
      o.sampling = .greedy
      return o
    }()
    
    let response = try await session.respond(to: prompt, options: generationOptions)
    return response.content
  }

  private func ensureSession() async throws -> LanguageModelSession {
    if let session = self.session {
      return session
    }
    let newSession = LanguageModelSession()
    self.session = newSession
    return newSession
  }
}

// MARK: - Errors

public enum AIError: Error {
  case noActiveSession
  case guardrailsTriggered
}
