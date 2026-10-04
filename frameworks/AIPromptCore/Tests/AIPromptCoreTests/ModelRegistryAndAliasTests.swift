import XCTest
@testable import AIPromptCore

final class ModelRegistryAndAliasTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        AliasConfiguration.shared.enableOpenAIAliases = false
        AliasConfiguration.shared.customAliases = [:]
    }
    
    func testRawAFMRecognition() {
        // Direct default AFM models
        XCTAssertTrue(ModelRegistry.isRawAFM(modelId: "apple-foundation-model-3-core-3b"))
        XCTAssertTrue(ModelRegistry.isRawAFM(modelId: "default"))
        XCTAssertTrue(ModelRegistry.isRawAFM(modelId: "apple-foundation-model"))
        XCTAssertTrue(ModelRegistry.isRawAFM(modelId: "apple-intelligence-private-cloud-compute"))
        
        // Non-raw AFM models
        XCTAssertFalse(ModelRegistry.isRawAFM(modelId: "apple-foundation-omni"))
        XCTAssertFalse(ModelRegistry.isRawAFM(modelId: "apple-vision-ocr"))
        XCTAssertFalse(ModelRegistry.isRawAFM(modelId: "apple-speech-transcribe"))
    }
    
    func testCustomAliasResolution() {
        AliasConfiguration.shared.setAlias(alias: "team-analyst", target: "apple-foundation-omni")
        AliasConfiguration.shared.setAlias(alias: "fast-whisper", target: "apple-speech-transcribe")
        
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("team-analyst"), "apple-foundation-omni")
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("fast-whisper"), "apple-speech-transcribe")
        XCTAssertTrue(ModelRegistry.isSupported(modelId: "team-analyst"))
        
        AliasConfiguration.shared.removeAlias(alias: "team-analyst")
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("team-analyst"), "team-analyst")
    }
    
    func testOpenAIAliasesFlag() {
        // When flag is disabled (default)
        AliasConfiguration.shared.enableOpenAIAliases = false
        XCTAssertFalse(ModelRegistry.isSupported(modelId: "whisper-1"))
        XCTAssertFalse(ModelRegistry.isSupported(modelId: "tts-1"))
        XCTAssertFalse(ModelRegistry.isSupported(modelId: "gpt-4o"))
        
        // When flag is enabled
        AliasConfiguration.shared.enableOpenAIAliases = true
        XCTAssertTrue(ModelRegistry.isSupported(modelId: "whisper-1"))
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("whisper-1"), "apple-speech-transcribe")
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("tts-1"), "apple-speech-synthesize")
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("gpt-4o"), "apple-foundation-omni")
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("text-embedding-3-small"), "apple-sentence-embedding")
    }
    
    func testOpenAIDTODecoding() throws {
        let json = """
        {
            "model": "apple-foundation-omni",
            "messages": [
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "Hello on-device AI!"}
            ],
            "temperature": 0.7,
            "max_tokens": 100
        }
        """.data(using: .utf8)!
        
        let request = try JSONDecoder().decode(OpenAI.ChatCompletionRequest.self, from: json)
        XCTAssertEqual(request.model, "apple-foundation-omni")
        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.systemInstructions, "You are a helpful assistant.")
        XCTAssertEqual(request.combinedPrompt, "Hello on-device AI!")
    }
    
    func testMultimodalMessageContentDecoding() throws {
        let json = """
        {
            "model": "apple-foundation-omni",
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "What is in this image?"},
                        {"type": "image_url", "image_url": {"url": "data:image/png;base64,abc123xyz"}}
                    ]
                }
            ]
        }
        """.data(using: .utf8)!
        
        let request = try JSONDecoder().decode(OpenAI.ChatCompletionRequest.self, from: json)
        XCTAssertEqual(request.messages.count, 1)
        XCTAssertEqual(request.combinedPrompt, "What is in this image?")
    }
}
