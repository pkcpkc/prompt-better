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
      
      XCTAssertGreaterThanOrEqual(models.data.count, 2)
      XCTAssertTrue(models.data.contains { $0.id == ModelName.defaultModel.rawValue })
      XCTAssertTrue(models.data.contains { $0.id == ModelName.privateCloudCompute.rawValue })
      XCTAssertTrue(models.data.contains { $0.id == "apple-foundation-model-3-core-3b" })
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

    // 3. Verify that raw AFM model (apple-foundation-model-3-core-3b) succeeds
    let afmRequest = OpenAI.ChatCompletionRequest(
      model: "apple-foundation-model-3-core-3b",
      messages: [
        .init(role: "user", content: "Say hello via AFM")
      ],
      temperature: nil,
      topP: nil,
      maxTokens: 10,
      stream: nil,
      stop: nil
    )
    
    try await app.test(.POST, "v1/chat/completions", beforeRequest: { req in
      try req.content.encode(afmRequest)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.ChatCompletionResponse.self)
      XCTAssertEqual(response.model, "apple-foundation-model-3-core-3b")
      XCTAssertFalse(response.choices.isEmpty)
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

  func testEmbeddingsEndpoint() async throws {
    let embeddingRequest = OpenAI.EmbeddingRequest(
      model: "apple-sentence-embedding",
      string: "Testing vector representation via macOS bridge HTTP."
    )
    
    try await app.test(.POST, "v1/embeddings", beforeRequest: { req in
      try req.content.encode(embeddingRequest)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.EmbeddingResponse.self)
      XCTAssertEqual(response.model, "apple-sentence-embedding")
      XCTAssertEqual(response.data.count, 1)
      XCTAssertEqual(response.data[0].embedding.count, 512)
    }
  }

  func testIndexAndSearchEndpoints() async throws {
    let indexReq = OpenAI.IndexDocumentRequest(
      id: "doc-macos-test",
      title: "Swift on macOS",
      content: "Swift delivers exceptional performance with native memory safety."
    )
    
    try await app.test(.POST, "v1/index/documents", beforeRequest: { req in
      try req.content.encode(indexReq)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.IndexDocumentResponse.self)
      XCTAssertEqual(response.id, "doc-macos-test")
      XCTAssertEqual(response.status, "indexed")
    }

    let searchReq = OpenAI.SearchRequest(
      query: "native memory safety performance",
      limit: 1,
      mode: "hybrid"
    )

    try await app.test(.POST, "v1/search", beforeRequest: { req in
      try req.content.encode(searchReq)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.SearchResponse.self)
      XCTAssertFalse(response.data.isEmpty)
      XCTAssertEqual(response.data.first?.id, "doc-macos-test")
    }
  }

  func testAudioSpeechEndpoint() async throws {
    let speechReq = OpenAI.AudioSpeechRequest(
      model: "apple-speech-synthesize",
      input: "HTTP audio speech synthesis test",
      voice: "alloy"
    )

    try await app.test(.POST, "v1/audio/speech", beforeRequest: { req in
      try req.content.encode(speechReq)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      XCTAssertEqual(res.headers.contentType?.description, "audio/wav")
      XCTAssertGreaterThan(res.body.readableBytes, 44) // WAV header is at least 44 bytes
    }
  }

  func testAudioTranscriptionEndpoint() async throws {
    // Generate dummy audio bytes
    let dummyWav = AudioSynthesisService.shared
    let speechReq = OpenAI.AudioSpeechRequest(
      input: "Speech transcription HTTP test",
      voice: "alloy"
    )
    let audioData = try await dummyWav.synthesize(request: speechReq)

    let transcriptionReq = OpenAI.AudioTranscriptionRequest(
      file: audioData,
      filename: "test.wav",
      model: "apple-speech-transcribe",
      prompt: "Speech transcription HTTP test"
    )

    try await app.test(.POST, "v1/audio/transcriptions", beforeRequest: { req in
      try req.content.encode(transcriptionReq)
    }) { res async throws in
      #if ENABLE_SPEECH
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.AudioTranscriptionResponse.self)
      XCTAssertFalse(response.text.isEmpty)
      #else
      XCTAssertEqual(res.status, .notImplemented)
      #endif
    }
  }

  func testImageGenerationEndpoint() async throws {
    let imageReq = OpenAI.ImageGenerationRequest(
      prompt: "A futuristic cybernetic falcon in flight",
      model: "apple-image-creator",
      responseFormat: "b64_json",
      size: "256x256"
    )

    try await app.test(.POST, "v1/images/generations", beforeRequest: { req in
      try req.content.encode(imageReq)
    }) { res async throws in
      XCTAssertEqual(res.status, .ok)
      let response = try res.content.decode(OpenAI.ImageGenerationResponse.self)
      XCTAssertEqual(response.data.count, 1)
      XCTAssertNotNil(response.data.first?.b64Json)
    }
  }
}
