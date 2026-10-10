import Vapor

func routes(_ app: Application) throws {
    try registerOpenAIRoutes(app)

    // Simple health check
    app.get("health") { req in
        "Bridge is running on port \(app.http.server.configuration.port)"
    }
}
