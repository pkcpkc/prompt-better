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
  /// Builds the final prompt by formatting and appending dynamic inputs as structured sections.
  public static func buildSystemPrompt(for input: String = "", context: [String: String] = [:])
    -> String
  {
    var result = systemPrompt
    if !input.isEmpty {
      result += "\n\nInput:\n\(input)"
    }
    for (key, value) in context.sorted(by: { $0.key < $1.key }) {
      let titleKey = formatKeyToTitleCase(key)
      result += "\n\n\(titleKey):\n\(value)"
    }
    return result
  }

  private static func formatKeyToTitleCase(_ key: String) -> String {
    let pattern = "[A-Z]?[a-z]+|[A-Z]+(?=[A-Z][a-z]|\\b)|[0-9]+"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return key.capitalized
    }

    let range = NSRange(key.startIndex..<key.endIndex, in: key)
    let matches = regex.matches(in: key, options: [], range: range)

    let words = matches.map { match -> String in
      let matchRange = Range(match.range, in: key)!
      let word = String(key[matchRange])
      return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }

    if words.isEmpty {
      return key.capitalized
    }
    return words.joined(separator: " ")
  }
}
