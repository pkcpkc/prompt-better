import Foundation
import ImageIO
#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif

/// In-process image moderation backed by Apple's SensitiveContentAnalysis framework.
///
/// The framework analyzes images (and video) only. Text input is rejected with
/// `AIError.unsupportedOperation`. Apple reports a single boolean (nudity), reported here as the
/// OpenAI `sexual` category with a score of `1.0` or `0.0`.
///
/// Requires the `com.apple.developer.sensitivecontentanalysis.client` entitlement and the system
/// "Sensitive Content Warning" (or Communication Safety) setting to be enabled.
public final class ModerationService: @unchecked Sendable {
    public static let shared = ModerationService()
    
    public init() {}
    
    public func moderate(request: OpenAI.ModerationRequest) async throws -> OpenAI.ModerationResponse {
        let imageURLs = try Self.imageURLs(from: request.input)
        var results: [OpenAI.ModerationResponse.ModerationResult] = []
        for url in imageURLs {
            results.append(try await analyzeImage(urlString: url))
        }
        return OpenAI.ModerationResponse(model: "apple-sensitive-content", results: results)
    }
    
    /// Extracts image references, rejecting any text input.
    static func imageURLs(from input: OpenAI.ModerationRequest.Input) throws -> [String] {
        let unsupported = AIError.unsupportedOperation(
            "apple-sensitive-content only moderates images; text input is not supported. Pass an image as {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/...\"}}."
        )
        switch input {
        case .text, .texts:
            throw unsupported
        case .parts(let parts):
            guard !parts.isEmpty else { throw unsupported }
            return try parts.map { part in
                guard part.type == "image_url", let url = part.imageUrl?.url else { throw unsupported }
                return url
            }
        }
    }
    
    private func analyzeImage(urlString: String) async throws -> OpenAI.ModerationResponse.ModerationResult {
        #if canImport(SensitiveContentAnalysis)
        let image = try ImageLoading.cgImage(fromReference: urlString)
        
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled else {
            throw AIError.unsupportedOperation("Sensitive content analysis is disabled on this device. Enable Sensitive Content Warning in System Settings > Privacy & Security.")
        }
        
        let analysis = try await analyzer.analyzeImage(image)
        let flagged = analysis.isSensitive
        return .init(
            flagged: flagged,
            categories: ["sexual": flagged],
            categoryScores: ["sexual": flagged ? 1.0 : 0.0]
        )
        #else
        throw AIError.unsupportedOperation("SensitiveContentAnalysis is not available on this platform.")
        #endif
    }
}
