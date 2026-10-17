import AIBridgeKit
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
      XCTAssertEqual(Set(models.data.map(\.id)), Set(BridgeModel.allCases.map(\.rawValue)))
    }
  }

  func testUnknownModelIsRejected() async throws {
    let request = OpenAI.ChatCompletionRequest(model: "unknown_model_identifier", messages: [.init(role: "user", content: "Say hello")])
    try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
      try req.content.encode(request)
    }) { res async throws in
      XCTAssertEqual(res.status, .notFound)
      let errorResponse = try res.content.decode(OpenAI.ErrorResponse.self)
      XCTAssertEqual(errorResponse.error.code, "model_not_found")
      XCTAssertEqual(errorResponse.error.type, "invalid_request_error")
    }
  }

  func testImagePartIsRejected() async throws {
    let request = OpenAI.ChatCompletionRequest(
      model: "default",
      messages: [.init(role: "user", content: .parts([.init(type: "image_url", text: nil)]))]
    )
    try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
      try req.content.encode(request)
    }) { res async throws in
      XCTAssertEqual(res.status, .badRequest)
      let errorResponse = try res.content.decode(OpenAI.ErrorResponse.self)
      XCTAssertEqual(errorResponse.error.code, "unsupported_operation")
    }
  }

  /// Needs Apple Intelligence on this Mac.
  func testChatCompletion() async throws {
    for model in BridgeModel.allCases {
      let request = OpenAI.ChatCompletionRequest(
        model: model.rawValue,
        messages: [
          .init(role: "system", content: "Answer in one word."),
          .init(role: "user", content: "Say hello"),
        ],
        temperature: 0,
        maxTokens: 10
      )
      try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
        try req.content.encode(request)
      }) { res async throws in
        XCTAssertEqual(res.status, .ok, res.body.string)
        let response = try res.content.decode(OpenAI.ChatCompletionResponse.self)
        XCTAssertEqual(response.model, model.rawValue)
        XCTAssertFalse(response.choices.isEmpty)
      }
    }
  }
}
