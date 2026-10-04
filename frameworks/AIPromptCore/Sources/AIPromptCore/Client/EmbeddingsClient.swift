import Foundation

/// In-process embeddings client offering OpenAI-compatible embeddings generation.
@MainActor
public final class EmbeddingsClient: Sendable {
    private let service: EmbeddingService
    
    public init(service: EmbeddingService = .shared) {
        self.service = service
    }
    
    /// Generates embeddings for a single string.
    public func create(
        input: String,
        model: String = "apple-sentence-embedding"
    ) async throws -> OpenAI.EmbeddingResponse {
        let req = OpenAI.EmbeddingRequest(model: model, string: input)
        return try await service.create(request: req)
    }
    
    /// Generates embeddings for an array of strings.
    public func create(
        input: [String],
        model: String = "apple-sentence-embedding"
    ) async throws -> OpenAI.EmbeddingResponse {
        let req = OpenAI.EmbeddingRequest(model: model, strings: input)
        return try await service.create(request: req)
    }
    
    /// Generates embeddings for an OpenAI EmbeddingRequest.
    public func create(
        _ request: OpenAI.EmbeddingRequest
    ) async throws -> OpenAI.EmbeddingResponse {
        return try await service.create(request: request)
    }
}
