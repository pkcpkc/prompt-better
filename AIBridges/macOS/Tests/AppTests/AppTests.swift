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
      
      XCTAssertEqual(models.data.count, 2)
      XCTAssertTrue(models.data.contains { $0.id == ModelName.defaultModel.rawValue })
      XCTAssertTrue(models.data.contains { $0.id == ModelName.privateCloudCompute.rawValue })
    }
  }

  func testChatCompletionWithSpecificModels() async throws {
    // 1. Verify default model completion succeeds
    let defaultRequest = OpenAI.ChatCompletionRequest(
      model: ModelName.defaultModel.rawValue,
      messages: [
        .init(role: "user", content: "Say hello via default")
      ],
      temperature: nil,
      topP: nil,
      maxTokens: 10,
      stream: nil,
      stop: nil
    )
    
    try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
      try req.content.encode(defaultRequest)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.ChatCompletionResponse.self)
      XCTAssertEqual(response.model, ModelName.defaultModel.rawValue)
      XCTAssertFalse(response.choices.isEmpty)
    }

    // 2. Verify Private Cloud Compute model completion succeeds
    let pccRequest = OpenAI.ChatCompletionRequest(
      model: ModelName.privateCloudCompute.rawValue,
      messages: [
        .init(role: "user", content: "Say hello via PCC")
      ],
      temperature: nil,
      topP: nil,
      maxTokens: 10,
      stream: nil,
      stop: nil
    )
    
    try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
      try req.content.encode(pccRequest)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.ChatCompletionResponse.self)
      XCTAssertEqual(response.model, ModelName.privateCloudCompute.rawValue)
      XCTAssertFalse(response.choices.isEmpty)
    }

    // 3. Verify that unlisted/legacy models are rejected
    let legacyRequest = OpenAI.ChatCompletionRequest(
      model: "apple-foundation-model-3-core-3b",
      messages: [
        .init(role: "user", content: "Say hello")
      ],
      temperature: nil,
      topP: nil,
      maxTokens: 10,
      stream: nil,
      stop: nil
    )
    
    try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
      try req.content.encode(legacyRequest)
    }) { res async throws in
      XCTAssertEqual(res.status, .notFound)
      let errorResponse = try res.content.decode(OpenAI.ErrorResponse.self)
      XCTAssertEqual(errorResponse.error.code, "api_error")
      XCTAssertEqual(errorResponse.error.type, "api_error")
      XCTAssertTrue(errorResponse.error.message.contains("not found"))
    }

    // 4. Verify that unknown models are rejected
    let invalidRequest = OpenAI.ChatCompletionRequest(
      model: "unknown_model_identifier",
      messages: [
        .init(role: "user", content: "Say hello")
      ],
      temperature: nil,
      topP: nil,
      maxTokens: 10,
      stream: nil,
      stop: nil
    )
    
    try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
      try req.content.encode(invalidRequest)
    }) { res async throws in
      XCTAssertEqual(res.status, .notFound)
      let errorResponse = try res.content.decode(OpenAI.ErrorResponse.self)
      XCTAssertEqual(errorResponse.error.code, "api_error")
      XCTAssertEqual(errorResponse.error.type, "api_error")
      XCTAssertTrue(errorResponse.error.message.contains("not found"))
    }
  }
}
