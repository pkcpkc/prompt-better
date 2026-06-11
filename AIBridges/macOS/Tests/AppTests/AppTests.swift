import Foundation
import XCTVapor

@testable import App

final class AppTests: XCTestCase {
  var app: Application!

  override func setUp() async throws {
    app = try await Application.make(.testing)
    try await configure(app)
  }

  override func tearDown() async throws {
    try await app.asyncShutdown()
    app = nil
  }

  func testHealthCheck() async throws {
    try await app.test(.GET, "health") { res async throws in
      XCTAssertEqual(res.status, .ok)
      XCTAssertEqual(res.body.string, "Bridge is running on port 8080")
    }
  }

  func testModelsListing() async throws {
    try await app.test(.GET, "v1/models") { res async throws in
      XCTAssertEqual(res.status, .ok)
      let models = try res.content.decode(OpenAI.ModelListResponse.self)
      XCTAssertFalse(models.data.isEmpty)
      XCTAssertTrue(models.data.contains { $0.id == "apple-intelligence" })
    }
  }
}
