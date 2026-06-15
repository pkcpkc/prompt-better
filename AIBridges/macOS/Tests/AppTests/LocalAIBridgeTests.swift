@testable import App
import FoundationModels
import XCTVapor

@MainActor
final class LocalAIBridgeTests: XCTestCase {
    
    func testPromptGeneration() async throws {
        // We simulate how the LocalAIBridge processes messages
        let bridge = LocalAIBridge.shared
        XCTAssertNotNil(bridge)
    }

    func testRequestParsingExtensions() throws {
        // 1. Standard test: System + User
        let request1 = OpenAI.ChatCompletionRequest(
            model: "test-model",
            messages: [
                .init(role: "system", content: "System instructions go here."),
                .init(role: "user", content: "User query.")
            ],
            temperature: nil,
            topP: nil,
            maxTokens: nil,
            stream: nil,
            stop: nil
        )
        XCTAssertEqual(request1.systemInstructions, "System instructions go here.")
        XCTAssertEqual(request1.combinedPrompt, "User query.")

        // 2. Multi-system test: Multiple system instructions
        let request2 = OpenAI.ChatCompletionRequest(
            model: "test-model",
            messages: [
                .init(role: "system", content: "Instruction A"),
                .init(role: "system", content: "Instruction B"),
                .init(role: "user", content: "Query text")
            ],
            temperature: nil,
            topP: nil,
            maxTokens: nil,
            stream: nil,
            stop: nil
        )
        XCTAssertEqual(request2.systemInstructions, "Instruction A\n\nInstruction B")
        XCTAssertEqual(request2.combinedPrompt, "Query text")

        // 3. User-only test: No system instructions
        let request3 = OpenAI.ChatCompletionRequest(
            model: "test-model",
            messages: [
                .init(role: "user", content: "Hello!"),
                .init(role: "assistant", content: "Hi!"),
                .init(role: "user", content: "How are you?")
            ],
            temperature: nil,
            topP: nil,
            maxTokens: nil,
            stream: nil,
            stop: nil
        )
        XCTAssertEqual(request3.systemInstructions, "")
        XCTAssertEqual(request3.combinedPrompt, "Hello!\n\nHi!\n\nHow are you?")
        
        // 4. Empty messages test
        let request4 = OpenAI.ChatCompletionRequest(
            model: "test-model",
            messages: [],
            temperature: nil,
            topP: nil,
            maxTokens: nil,
            stream: nil,
            stop: nil
        )
        XCTAssertEqual(request4.systemInstructions, "")
        XCTAssertEqual(request4.combinedPrompt, "")
    }
}
