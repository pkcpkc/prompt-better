import Vapor
@_exported import AIPromptCore

// Conform AIPromptCore DTOs to Vapor Content for HTTP serialization
extension OpenAI.ChatCompletionRequest: @retroactive Content {}
extension OpenAI.ChatCompletionResponse: @retroactive Content {}
extension OpenAI.ModelListResponse: @retroactive Content {}
extension OpenAI.EmbeddingRequest: @retroactive Content {}
extension OpenAI.EmbeddingResponse: @retroactive Content {}
extension OpenAI.AudioTranscriptionRequest: @retroactive Content {}
extension OpenAI.AudioTranscriptionResponse: @retroactive Content {}
extension OpenAI.AudioTranslationRequest: @retroactive Content {}
extension OpenAI.AudioSpeechRequest: @retroactive Content {}
extension OpenAI.ModerationRequest: @retroactive Content {}
extension OpenAI.ModerationResponse: @retroactive Content {}
extension OpenAI.SearchRequest: @retroactive Content {}
extension OpenAI.SearchResponse: @retroactive Content {}
extension OpenAI.IndexDocumentRequest: @retroactive Content {}
extension OpenAI.IndexDocumentResponse: @retroactive Content {}
extension OpenAI.ImageGenerationRequest: @retroactive Content {}
extension OpenAI.ImageGenerationResponse: @retroactive Content {}
extension OpenAI.ErrorResponse: @retroactive Content {}
extension OpenAI.ErrorResponse.ErrorDetail: @retroactive Content {}
