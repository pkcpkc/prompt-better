import Foundation
import CoreGraphics
import FoundationModels

public actor AISessionController {
  public static let shared = AISessionController()
  private var session: LanguageModelSession?
  private var isBusy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  private func acquireLock() async {
    if !isBusy {
      isBusy = true
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func releaseLock() {
    if !waiters.isEmpty {
      let next = waiters.removeFirst()
      next.resume()
    } else {
      isBusy = false
    }
  }

  private func runSerialized<T>(_ operation: () async throws -> T) async throws -> T {
    await acquireLock()
    defer { releaseLock() }
    return try await operation()
  }

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
    try await runSerialized {
      if createNewSession || self.session == nil || self.session?.isResponding == true {
        let newSession = LanguageModelSession()
        self.session = newSession
      }
      guard let session = self.session else { throw AIError.noActiveSession }
      let userPrompt = T.buildSystemPrompt(for: input, context: context)
      do {
        let options =
          T.options
          ?? {
            var o = GenerationOptions()
            o.samplingMode = .greedy
            return o
          }()
        let response = try await session.respond(to: userPrompt, generating: type, options: options)
        return response.content
      } catch LanguageModelSession.GenerationError.guardrailViolation {
        throw AIError.guardrailsTriggered
      } catch let error where error.localizedDescription.localizedCaseInsensitiveContains("Safety guardrails")
        || error.localizedDescription.localizedCaseInsensitiveContains("unsafe")
        || error.localizedDescription.localizedCaseInsensitiveContains("guardrail")
        || error.localizedDescription.localizedCaseInsensitiveContains("safety") {
        throw AIError.guardrailsTriggered
      }
    }
  }

  /// Sends a raw string prompt to the language model and returns the response content.
  public func respond(
    to prompt: String,
    options: GenerationOptions? = nil,
    model: (any LanguageModel)? = nil,
    instructions: String? = nil,
    createNewSession: Bool = false
  ) async throws -> String {
    try await runSerialized {
      let session = try await self.ensureSession(model: model, instructions: instructions, forceNew: createNewSession)
      let generationOptions = options ?? {
        var o = GenerationOptions()
        o.sampling = .greedy
        return o
      }()
      
      do {
        let response = try await session.respond(to: prompt, options: generationOptions)
        return response.content
      } catch LanguageModelSession.GenerationError.guardrailViolation {
        throw AIError.guardrailsTriggered
      } catch let error where error.localizedDescription.localizedCaseInsensitiveContains("Safety guardrails")
        || error.localizedDescription.localizedCaseInsensitiveContains("unsafe")
        || error.localizedDescription.localizedCaseInsensitiveContains("guardrail")
        || error.localizedDescription.localizedCaseInsensitiveContains("safety") {
        throw AIError.guardrailsTriggered
      }
    }
  }

  /// Sends a text prompt together with images. Requires an image-capable model (OS 27+, advanced tier).
  public func respond(
    to prompt: String,
    images: [CGImage],
    options: GenerationOptions? = nil,
    model: (any LanguageModel)? = nil,
    instructions: String? = nil
  ) async throws -> String {
    guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else {
      throw AIError.unsupportedOperation("Image input requires OS 27 or later.")
    }
    return try await runSerialized {
      // Image prompts always get a fresh session so attachments do not accumulate in the transcript.
      let session = try await self.ensureSession(model: model, instructions: instructions, forceNew: true)
      let generationOptions = options ?? {
        var o = GenerationOptions()
        o.samplingMode = .greedy
        return o
      }()
      let fullPrompt = Prompt {
        prompt
        for image in images {
          Attachment(image)
        }
      }
      do {
        return try await session.respond(to: fullPrompt, options: generationOptions).content
      } catch LanguageModelSession.GenerationError.guardrailViolation {
        throw AIError.guardrailsTriggered
      }
    }
  }

  /// Sends a prompt and decodes the response into a schema-conforming Generable type.
  public func respond<T: Generable & Sendable>(
    to prompt: String,
    generating type: T.Type,
    options: GenerationOptions? = nil,
    model: (any LanguageModel)? = nil,
    instructions: String? = nil,
    createNewSession: Bool = false
  ) async throws -> T {
    try await runSerialized {
      let session = try await self.ensureSession(model: model, instructions: instructions, forceNew: createNewSession)
      let generationOptions = options ?? {
        var o = GenerationOptions()
        o.sampling = .greedy
        return o
      }()

      do {
        let response = try await session.respond(to: prompt, generating: type, options: generationOptions)
        return response.content
      } catch LanguageModelSession.GenerationError.guardrailViolation {
        throw AIError.guardrailsTriggered
      } catch let error where error.localizedDescription.localizedCaseInsensitiveContains("Safety guardrails")
        || error.localizedDescription.localizedCaseInsensitiveContains("unsafe")
        || error.localizedDescription.localizedCaseInsensitiveContains("guardrail")
        || error.localizedDescription.localizedCaseInsensitiveContains("safety") {
        throw AIError.guardrailsTriggered
      }
    }
  }

  private func ensureSession(
    model: (any LanguageModel)? = nil,
    instructions: String? = nil,
    forceNew: Bool = false
  ) async throws -> LanguageModelSession {
    if !forceNew, let session = self.session, model == nil && instructions == nil, !session.isResponding {
      return session
    }
    let resolved = model ?? SystemLanguageModel.default
    let newSession = LanguageModelSession(model: resolved, instructions: instructions)
    self.session = newSession
    return newSession
  }
}

// MARK: - Errors

public enum AIError: Error, LocalizedError, Sendable {
  case noActiveSession
  case guardrailsTriggered
  case modelNotFound(String)
  case promptNotFound(String)
  case unsupportedOperation(String)
  
  public var errorDescription: String? {
    switch self {
    case .noActiveSession: return "No active language model session"
    case .guardrailsTriggered: return "Content policy violation: generation rejected by safety guardrails"
    case .modelNotFound(let name): return "Model '\(name)' not found"
    case .promptNotFound(let name): return "Prompt definition '\(name).json' not found"
    case .unsupportedOperation(let op): return "Operation '\(op)' is unsupported"
    }
  }
}

