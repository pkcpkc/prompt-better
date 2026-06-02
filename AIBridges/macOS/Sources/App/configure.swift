import Vapor

public func configure(_ app: Application) async throws {
    // Configure Port to 8080 as requested
    // Note: When testing, XCTVapor might use its own port.
    if app.environment != .testing {
        app.http.server.configuration.port = 8080
    }
    
    // Register routes
    try routes(app)
}
