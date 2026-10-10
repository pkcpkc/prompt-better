import Foundation
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

/// In-process translation service using Apple's on-device Translation framework.
///
/// Requires the source/target language packs to be installed (System Settings > General >
/// Language & Region > Translation Languages); no download UI is presented from here.
public final class TranslationService: @unchecked Sendable {
    public static let shared = TranslationService()
    
    public init() {}
    
    /// Detects the dominant language of `text`, or `nil` if it cannot be determined.
    public func detectLanguage(of text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }
    
    public func translate(
        text: String,
        sourceLanguage: String? = nil,
        targetLanguage: String = "en-US"
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        
        guard let sourceID = sourceLanguage ?? detectLanguage(of: text) else {
            throw AIError.unsupportedOperation("Could not detect the source language; pass a source language explicitly.")
        }
        
        let source = Locale.Language(identifier: sourceID)
        let target = Locale.Language(identifier: targetLanguage)
        
        // Same language (compare language codes, ignoring region): nothing to do.
        if source.languageCode == target.languageCode { return text }
        
        #if canImport(Translation)
        let status = await LanguageAvailability().status(from: source, to: target)
        guard status == .installed else {
            throw AIError.unsupportedOperation("Translation \(sourceID) -> \(targetLanguage) is unavailable (status: \(status)). Install the language packs in System Settings > General > Language & Region > Translation Languages.")
        }
        let session = TranslationSession(installedSource: source, target: target)
        return try await session.translate(text).targetText
        #else
        throw AIError.unsupportedOperation("The Translation framework is not available on this platform.")
        #endif
    }
}
