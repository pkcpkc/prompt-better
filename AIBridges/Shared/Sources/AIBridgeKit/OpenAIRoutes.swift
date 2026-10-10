import Vapor
import AIPromptCore

private let speechDisabledReason = "Speech recognition (STT) is disabled in this build. Rebuild with speech flag (e.g. ENABLE_SPEECH=1 or --with-speech) enabled."

private struct MultipartAudio: Content {
    var file: File
    var model: String?
    var language: String?
    var prompt: String?
}

/// Registers the OpenAI-compatible API (`/v1/...`) backed by `AppleOpenAIClient`
/// and installs `OpenAIErrorMiddleware` so every route reports errors in the OpenAI format.
public func registerOpenAIRoutes(_ app: Application) throws {
    app.middleware.use(OpenAIErrorMiddleware())

    let v1 = app.grouped("v1")

    v1.post("chat", "completions") { req async throws -> OpenAI.ChatCompletionResponse in
        let completionRequest = try req.content.decode(OpenAI.ChatCompletionRequest.self)
        try OpenAIAPIError.requireModel(completionRequest.model)
        return try await AppleOpenAIClient.shared.chat.completions.create(request: completionRequest)
    }

    v1.post("embeddings") { req async throws -> OpenAI.EmbeddingResponse in
        let embeddingRequest = try req.content.decode(OpenAI.EmbeddingRequest.self)
        try OpenAIAPIError.requireModel(embeddingRequest.model)
        return try await AppleOpenAIClient.shared.embeddings.create(embeddingRequest)
    }

    v1.post("index", "documents") { req async throws -> OpenAI.IndexDocumentResponse in
        let indexRequest = try req.content.decode(OpenAI.IndexDocumentRequest.self)
        await AppleOpenAIClient.shared.index.add(
            id: indexRequest.id,
            title: indexRequest.title,
            content: indexRequest.content,
            metadata: indexRequest.metadata
        )
        return OpenAI.IndexDocumentResponse(id: indexRequest.id, status: "indexed", chunkCount: 1)
    }

    v1.post("search") { req async throws -> OpenAI.SearchResponse in
        let searchRequest = try req.content.decode(OpenAI.SearchRequest.self)
        let mode: SearchMode
        switch searchRequest.mode {
        case "vector":
            mode = .vectorOnly
        case "spotlight":
            mode = .spotlightOnly
        default:
            if let f = searchRequest.fusion, f.type == "linear" {
                mode = .hybrid(strategy: LinearRankFusion(alpha: f.vectorWeight ?? 0.5))
            } else {
                mode = .hybrid(
                    k: searchRequest.fusion?.k ?? 60.0,
                    lexicalWeight: searchRequest.fusion?.lexicalWeight ?? 1.0,
                    vectorWeight: searchRequest.fusion?.vectorWeight ?? 1.0
                )
            }
        }
        let results = await AppleOpenAIClient.shared.index.search(
            query: searchRequest.query,
            limit: searchRequest.limit ?? 5,
            mode: mode,
            minScore: searchRequest.minScore
        )
        return OpenAI.SearchResponse(data: results, query: searchRequest.query, mode: searchRequest.mode ?? "hybrid")
    }

    v1.post("audio", "speech") { req async throws -> Response in
        let speechRequest = try req.content.decode(OpenAI.AudioSpeechRequest.self)
        let audioData = try await AppleOpenAIClient.shared.audio.speech.create(speechRequest)
        return Response(status: .ok, headers: ["Content-Type": "audio/wav"], body: .init(data: audioData))
    }

    v1.post("audio", "transcriptions") { req async throws -> OpenAI.AudioTranscriptionResponse in
        guard SpeechRecognitionService.isSupported else {
            throw Abort(.notImplemented, reason: speechDisabledReason)
        }
        if req.headers.contentType == .json {
            return try await AppleOpenAIClient.shared.audio.transcriptions.create(
                try req.content.decode(OpenAI.AudioTranscriptionRequest.self)
            )
        }
        let form = try req.content.decode(MultipartAudio.self)
        return try await AppleOpenAIClient.shared.audio.transcriptions.create(
            file: Data(buffer: form.file.data),
            filename: form.file.filename,
            model: form.model ?? "apple-speech-transcribe",
            language: form.language,
            prompt: form.prompt
        )
    }

    // Speech in `language` -> English text
    v1.post("audio", "translations") { req async throws -> OpenAI.AudioTranscriptionResponse in
        guard SpeechRecognitionService.isSupported else {
            throw Abort(.notImplemented, reason: speechDisabledReason)
        }
        if req.headers.contentType == .json {
            return try await AppleOpenAIClient.shared.audio.translations.create(
                try req.content.decode(OpenAI.AudioTranslationRequest.self)
            )
        }
        let form = try req.content.decode(MultipartAudio.self)
        return try await AppleOpenAIClient.shared.audio.translations.create(
            file: Data(buffer: form.file.data),
            filename: form.file.filename,
            model: form.model ?? "apple-speech-translate",
            language: form.language,
            prompt: form.prompt
        )
    }

    // Images only; text input is rejected with 400 (AIError.unsupportedOperation)
    v1.post("moderations") { req async throws -> OpenAI.ModerationResponse in
        let moderationRequest = try req.content.decode(OpenAI.ModerationRequest.self)
        try OpenAIAPIError.requireModel(moderationRequest.model ?? "apple-sensitive-content")
        return try await AppleOpenAIClient.shared.moderations.create(moderationRequest)
    }

    v1.post("images", "generations") { req async throws -> OpenAI.ImageGenerationResponse in
        let imageRequest = try req.content.decode(OpenAI.ImageGenerationRequest.self)
        try OpenAIAPIError.requireModel(imageRequest.model)
        return try await AppleOpenAIClient.shared.images.create(imageRequest)
    }

    v1.get("models") { _ async -> OpenAI.ModelListResponse in
        OpenAI.ModelListResponse(data: ModelRegistry.listModels())
    }
}
