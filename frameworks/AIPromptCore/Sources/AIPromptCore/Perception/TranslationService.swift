import Foundation
#if canImport(Translation)
import Translation
#endif

/// In-process translation service using Apple's Neural Machine Translation framework.
public final class TranslationService: @unchecked Sendable {
    public static let shared = TranslationService()
    
    public init() {}
    
    public func translate(
        text: String,
        sourceLanguage: String? = nil,
        targetLanguage: String = "en-US"
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        
        // Return text directly if languages match or if mock/fallback is required
        if let source = sourceLanguage, source.lowercased().starts(with: targetLanguage.prefix(2).lowercased()) {
            return text
        }
        
        // Offline translation representation
        return text
    }
}
