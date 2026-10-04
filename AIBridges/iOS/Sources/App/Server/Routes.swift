import Vapor
import AIPromptCore
import FoundationModels

func routes(_ app: Application) throws {
    
    // MARK: - OpenAI Compatibility
    
    // Route: POST /v1/chat/completions
    app.post("v1", "chat", "completions") { req async throws in
        let completionRequest = try req.content.decode(OpenAI.ChatCompletionRequest.self)
        let modelName = completionRequest.model
        
        guard ModelRegistry.isSupported(modelId: modelName) else {
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: "Model '\(modelName)' not found.",
                type: "invalid_request_error",
                param: "model",
                code: "model_not_found"
            )
            let errorResponse = OpenAI.ErrorResponse(error: errorDetail)
            let data = try JSONEncoder().encode(errorResponse)
            return Response(status: .notFound, headers: ["Content-Type": "application/json"], body: .init(data: data))
        }
        
        do {
            let response = try await AppleOpenAIClient.shared.chat.completions.create(request: completionRequest)
            let data = try JSONEncoder().encode(response)
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
        } catch let aiError as AIError {
            let (status, message, code): (HTTPStatus, String, String)
            switch aiError {
            case .guardrailsTriggered:
                status = .badRequest
                message = "The request was rejected by safety guardrails."
                code = "content_policy_violation"
            case .modelNotFound(let name):
                status = .notFound
                message = "Model '\(name)' not found."
                code = "model_not_found"
            default:
                status = .internalServerError
                message = aiError.localizedDescription
                code = "internal_error"
            }
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: message,
                type: "api_error",
                param: nil,
                code: code
            )
            let errorResponse = OpenAI.ErrorResponse(error: errorDetail)
            let data = try JSONEncoder().encode(errorResponse)
            return Response(status: status, headers: ["Content-Type": "application/json"], body: .init(data: data))
        } catch let abortError as AbortError {
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: abortError.reason,
                type: "api_error",
                param: nil,
                code: "api_error"
            )
            let errorResponse = OpenAI.ErrorResponse(error: errorDetail)
            let data = try JSONEncoder().encode(errorResponse)
            return Response(status: abortError.status, headers: ["Content-Type": "application/json"], body: .init(data: data))
        } catch {
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: error.localizedDescription,
                type: "api_error",
                param: nil,
                code: "internal_error"
            )
            let errorResponse = OpenAI.ErrorResponse(error: errorDetail)
            let data = try JSONEncoder().encode(errorResponse)
            return Response(status: .internalServerError, headers: ["Content-Type": "application/json"], body: .init(data: data))
        }
    }
    
    // Route: POST /v1/embeddings
    app.post("v1", "embeddings") { req async throws -> OpenAI.EmbeddingResponse in
        let embeddingRequest = try req.content.decode(OpenAI.EmbeddingRequest.self)
        guard ModelRegistry.isSupported(modelId: embeddingRequest.model) else {
            throw Abort(.notFound, reason: "Model '\(embeddingRequest.model)' not found.")
        }
        return try await AppleOpenAIClient.shared.embeddings.create(embeddingRequest)
    }

    // Route: POST /v1/index/documents
    app.post("v1", "index", "documents") { req async throws -> OpenAI.IndexDocumentResponse in
        let indexRequest = try req.content.decode(OpenAI.IndexDocumentRequest.self)
        await AppleOpenAIClient.shared.index.add(
            id: indexRequest.id,
            title: indexRequest.title,
            content: indexRequest.content,
            metadata: indexRequest.metadata
        )
        return OpenAI.IndexDocumentResponse(id: indexRequest.id, status: "indexed", chunkCount: 1)
    }

    // Route: POST /v1/search
    app.post("v1", "search") { req async throws -> OpenAI.SearchResponse in
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
                let k = searchRequest.fusion?.k ?? 60.0
                let lw = searchRequest.fusion?.lexicalWeight ?? 1.0
                let vw = searchRequest.fusion?.vectorWeight ?? 1.0
                mode = .hybrid(k: k, lexicalWeight: lw, vectorWeight: vw)
            }
        }
        let results = await AppleOpenAIClient.shared.index.search(
            query: searchRequest.query,
            limit: searchRequest.limit ?? 5,
            mode: mode,
            minScore: searchRequest.minScore
        )
        return OpenAI.SearchResponse(
            data: results,
            query: searchRequest.query,
            mode: searchRequest.mode ?? "hybrid"
        )
    }
    
    // Route: POST /v1/audio/speech
    app.post("v1", "audio", "speech") { req async throws -> Response in
        let speechRequest = try req.content.decode(OpenAI.AudioSpeechRequest.self)
        let audioData = try await AppleOpenAIClient.shared.audio.speech.create(speechRequest)
        return Response(status: .ok, headers: ["Content-Type": "audio/wav"], body: .init(data: audioData))
    }

    // Route: POST /v1/audio/transcriptions
    app.post("v1", "audio", "transcriptions") { req async throws -> OpenAI.AudioTranscriptionResponse in
        guard SpeechRecognitionService.isSupported else {
            throw Abort(.notImplemented, reason: "Speech recognition (STT) is disabled in this build. Rebuild with speech flag (e.g. ENABLE_SPEECH=1 or --with-speech) enabled.")
        }
        if let jsonRequest = try? req.content.decode(OpenAI.AudioTranscriptionRequest.self) {
            return try await AppleOpenAIClient.shared.audio.transcriptions.create(jsonRequest)
        }
        
        struct MultipartTranscription: Content {
            var file: File
            var model: String?
            var language: String?
            var prompt: String?
        }
        
        let form = try req.content.decode(MultipartTranscription.self)
        let audioData = Data(buffer: form.file.data)
        return try await AppleOpenAIClient.shared.audio.transcriptions.create(
            file: audioData,
            filename: form.file.filename,
            model: form.model ?? "apple-speech-transcribe",
            language: form.language,
            prompt: form.prompt
        )
    }
    
    // Route: POST /v1/images/generations
    app.post("v1", "images", "generations") { req async throws -> OpenAI.ImageGenerationResponse in
        let imageRequest = try req.content.decode(OpenAI.ImageGenerationRequest.self)
        guard ModelRegistry.isSupported(modelId: imageRequest.model) else {
            throw Abort(.notFound, reason: "Model '\(imageRequest.model)' not found.")
        }
        return try await AppleOpenAIClient.shared.images.create(imageRequest)
    }
    
    // Route: GET /v1/models
    app.get("v1", "models") { req async in
        let models = ModelRegistry.listModels()
        return OpenAI.ModelListResponse(data: models)
    }
    
    // Simple health check
    app.get("health") { req in
        "iOS Bridge is running on port \(app.http.server.configuration.port)"
    }
}
