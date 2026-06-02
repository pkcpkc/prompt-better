import Vapor

func routes(_ app: Application) throws {
    
    // MARK: - OpenAI Compatibility
    
    // Route: POST /v1/chat/completions
    app.post("v1", "chat", "completions") { req async throws in
        let completionRequest = try req.content.decode(OpenAI.ChatCompletionRequest.self)
        
        // Automatic hop to MainActor since LocalAIBridge is @MainActor
        let responseText = try await LocalAIBridge.shared.generate(request: completionRequest)
        
        return OpenAI.ChatCompletionResponse(
            id: "chatcmpl-\(UUID().uuidString)",
            created: Int(Date().timeIntervalSince1970),
            model: completionRequest.model,
            choices: [
                .init(
                    index: 0,
                    message: .init(content: responseText),
                    finishReason: "stop"
                )
            ],
            usage: .init(
                promptTokens: 0, // Not provided by local AI easily
                completionTokens: 0,
                totalTokens: 0
            )
        )
    }
    
    // Route: GET /v1/models
    app.get("v1", "models") { req async in
        let models = await LocalAIBridge.shared.listModels()
        return OpenAI.ModelListResponse(data: models)
    }
    
    // Simple health check
    app.get("health") { req in
        "Bridge is running on port 8080"
    }

}
