import AIBridgeKit
import Vapor

public func configure(_ app: Application) async throws {
    // Note: When testing, XCTVapor might use its own port.
    if app.environment != .testing {
        app.http.server.configuration.port = 8080
    }

    app.logger.info("\(BridgeModel.diagnostics)")

    try routes(app)
}
