import Vapor

func routes(_ app: Application) throws {
    
    // MARK: - OpenAI Compatibility
    
    // Route: POST /v1/chat/completions
    app.post("v1", "chat", "completions") { req async throws in
        let completionRequest = try req.content.decode(OpenAI.ChatCompletionRequest.self)
        
        do {
            // Automatic hop to MainActor since LocalAIBridge is @MainActor
            let responseText = try await LocalAIBridge.shared.generate(request: completionRequest, headers: req.headers)
            
            let chatResponse = OpenAI.ChatCompletionResponse(
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
            let data = try JSONEncoder().encode(chatResponse)
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
        } catch let abortError as AbortError {
            let reason = abortError.reason
            let code: String?
            let message: String
            
            if reason.contains(":") {
                let parts = reason.split(separator: ":", maxSplits: 1).map(String.init)
                code = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                message = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                code = "api_error"
                message = reason
            }
            
            let type: String
            switch abortError.status {
            case .badRequest:
                type = "invalid_request_error"
            case .tooManyRequests:
                type = "insufficient_quota"
            case .serviceUnavailable:
                type = "requests_limit_error"
            default:
                type = "api_error"
            }
            
            let errorDetail = OpenAI.ErrorResponse.ErrorDetail(
                message: message,
                type: type,
                param: nil,
                code: code
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
