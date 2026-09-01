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
      XCTAssertTrue(models.data.contains { $0.id == ModelRegistry.onDeviceModelId })
      XCTAssertTrue(models.data.contains { $0.id == ModelName.privateCloudCompute.rawValue })
      
      // Ensure on-device is either 3B or 20B advanced sparse
      XCTAssertTrue(
        ModelRegistry.onDeviceModelId == ModelName.afm3Core3B.rawValue ||
        ModelRegistry.onDeviceModelId == ModelName.afm3CoreAdvanced20BSparse.rawValue
      )
    }
  }

  func testChatCompletionWithSpecificModels() async throws {
    // 1. Verify on-device detected model completion succeeds
    let onDeviceRequest = OpenAI.ChatCompletionRequest(
      model: ModelRegistry.onDeviceModelId,
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
      try req.content.encode(onDeviceRequest)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.ChatCompletionResponse.self)
      XCTAssertEqual(response.model, ModelRegistry.onDeviceModelId)
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

    // 3. Verify that unlisted/invalid models are rejected
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
