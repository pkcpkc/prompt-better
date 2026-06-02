import Vapor
import AIPromptCore
import FoundationModels

func routes(_ app: Application) throws {
    
    // MARK: - OpenAI Compatibility
    
    // Route: POST /v1/chat/completions
    app.post("v1", "chat", "completions") { req async throws in
        let completionRequest = try req.content.decode(OpenAI.ChatCompletionRequest.self)
        
        // Prepare the prompt by combining message contents (Raw text for parity)
        let combinedPrompt = completionRequest.messages.map { $0.content }.joined(separator: "\n\n")
        
        // Prepare options
        var options = GenerationOptions()
        if let temp = completionRequest.temperature {
            options.sampling = .random(probabilityThreshold: Double(completionRequest.topP ?? 1.0))
            // Note: Vapor temperature is Float, FoundationModels expects Double or sampling mode
            if temp == 0 {
                options.sampling = .greedy
            }
        } else {
            options.sampling = .greedy
        }
        
        if let maxTokens = completionRequest.maxTokens {
            options.maximumResponseTokens = maxTokens
        }

        // Call native LanguageModelSession directly to ensure statelessness
        let session = LanguageModelSession()
        let response = try await session.respond(to: combinedPrompt, options: options)
        let responseText = response.content
        
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
                promptTokens: 0,
                completionTokens: 0,
                totalTokens: 0
            )
        )
    }
    
    // Route: GET /v1/models
    app.get("v1", "models") { req async in
        let models = [
            OpenAI.ModelListResponse.Model(id: "apple-intelligence")
        ]
        return OpenAI.ModelListResponse(data: models)
    }
    
    // Simple health check
    app.get("health") { req in
        "iOS Bridge is running on port \(app.http.server.configuration.port)"
    }
}
