import Foundation
import FoundationModels

// MARK: - Protocol

public protocol GenerableWithPrompt: Generable {
  /// Template string with `{{placeholder}}` tokens.
  /// `{{input}}` is always replaced with the primary input.
  /// Additional keys are passed via the `context` dictionary.
  static var systemPrompt: String { get }

  /// Generation configuration for the AI model.
  static var options: GenerationOptions? { get }
}

extension GenerableWithPrompt {
  /// Builds the final prompt by replacing `{{input}}` and any context placeholders.
  public static func buildSystemPrompt(for input: String = "", context: [String: String] = [:])
    -> String
  {
    var result = systemPrompt.replacingOccurrences(of: "{{input}}", with: input)
    for (key, value) in context {
      result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    #if DEBUG
      // Catch unfilled placeholders during development
      if let range = result.range(of: #"\{\{[a-zA-Z]+\}\}"#, options: .regularExpression) {
        assertionFailure("Unfilled placeholder in prompt: \(result[range])")
      }
    #endif
    return result
  }
}
