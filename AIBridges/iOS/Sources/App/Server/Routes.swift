import AIBridgeKit
import Vapor

func routes(_ app: Application) throws {
  try registerOpenAIRoutes(app, healthMessage: "iOS Bridge")
}
