import Foundation

/// In-process moderation client offering OpenAI-compatible `moderations.create` for images.
@MainActor
public final class ModerationsClient: Sendable {
    private let service: ModerationService
    
    public init(service: ModerationService = .shared) {
        self.service = service
    }
    
    /// Moderates one or more images, given as data URLs, http(s) URLs or file paths.
    public func create(
        images: [String],
        model: String = "apple-sensitive-content"
    ) async throws -> OpenAI.ModerationResponse {
        let parts = images.map(OpenAI.ModerationRequest.Input.Part.image(url:))
        return try await service.moderate(request: .init(input: .parts(parts), model: model))
    }
    
    public func create(_ request: OpenAI.ModerationRequest) async throws -> OpenAI.ModerationResponse {
        return try await service.moderate(request: request)
    }
}
