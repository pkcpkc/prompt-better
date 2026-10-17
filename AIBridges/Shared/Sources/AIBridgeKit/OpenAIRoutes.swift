import Vapor

/// Registers `POST /v1/chat/completions`, `GET /v1/models` and `GET /health`,
/// and installs `OpenAIErrorMiddleware` so every route reports errors in the OpenAI format.
public func registerOpenAIRoutes(_ app: Application, healthMessage: String) throws {
    app.middleware.use(OpenAIErrorMiddleware())

    let v1 = app.grouped("v1")

    v1.post("chat", "completions") { req async throws -> OpenAI.ChatCompletionResponse in
        let completionRequest = try req.content.decode(OpenAI.ChatCompletionRequest.self)
        return try await ChatCompletionService.shared.complete(completionRequest)
    }

    v1.get("models") { _ -> OpenAI.ModelListResponse in
        OpenAI.ModelListResponse(data: BridgeModel.allCases.map { .init(id: $0.rawValue) })
    }

    app.get("health") { _ in
        "\(healthMessage) is running on port \(app.http.server.configuration.port)"
    }
}
