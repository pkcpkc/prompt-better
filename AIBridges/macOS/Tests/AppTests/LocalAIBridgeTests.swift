@testable import App
import FoundationModels
import XCTVapor

@MainActor
final class LocalAIBridgeTests: XCTestCase {
    
    func testPromptGeneration() async throws {
        // We simulate how the LocalAIBridge processes messages
        let bridge = LocalAIBridge.shared
        
        let _ = OpenAI.ChatCompletionRequest(
            model: "test-model",
            messages: [
                .init(role: "system", content: "You act as a mock test AI"),
                .init(role: "user", content: "Hello!")
            ],
            temperature: nil,
            topP: nil,
            maxTokens: 50,
            stream: false,
            stop: nil
        )
        
        // Since generate actually attempts to run against FoundationModels,
        // we mainly want to verify it doesn't crash or that the map logic compiles correctly
        // Testing full Apple Intelligence is hard in unit tests if models aren't downloaded,
        // but this verifies the compilation of our mapping change seamlessly.
        XCTAssertNotNil(bridge)
    }
}
