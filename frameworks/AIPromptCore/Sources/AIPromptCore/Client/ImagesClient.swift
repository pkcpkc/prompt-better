import Foundation

/// In-process Images client providing OpenAI-compatible image generation
/// via Apple Image Playground (the system sheet, which the user completes).
@MainActor
public final class ImagesClient: Sendable {
    private let service: ImageGenerationService
    
    public init(service: ImageGenerationService = .shared) {
        self.service = service
    }
    
    /// Generates images matching the OpenAI SDK `client.images.generate(...)` signature.
    public func generate(
        prompt: String,
        model: String = "apple-image-playground",
        n: Int? = 1,
        quality: String? = "standard",
        responseFormat: String? = "b64_json",
        size: String? = "1024x1024",
        style: String? = nil,
        user: String? = nil
    ) async throws -> OpenAI.ImageGenerationResponse {
        let req = OpenAI.ImageGenerationRequest(
            prompt: prompt,
            model: model,
            n: n,
            quality: quality,
            responseFormat: responseFormat,
            size: size,
            style: style,
            user: user
        )
        return try await service.generate(request: req)
    }
    
    /// Generates images with an explicit ImageGenerationRequest object.
    public func create(_ request: OpenAI.ImageGenerationRequest) async throws -> OpenAI.ImageGenerationResponse {
        return try await service.generate(request: request)
    }
    
    /// Generates an image using the Apple Image Playground (launches Playground UI workflow).
    public func generatePlayground(
        prompt: String,
        style: String = "animation",
        size: String = "1024x1024",
        responseFormat: String = "b64_json"
    ) async throws -> OpenAI.ImageGenerationResponse {
        return try await generate(
            prompt: prompt,
            model: "apple-image-playground",
            responseFormat: responseFormat,
            size: size,
            style: style
        )
    }
}
