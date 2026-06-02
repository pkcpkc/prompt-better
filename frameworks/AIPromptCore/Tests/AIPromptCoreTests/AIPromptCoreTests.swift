import XCTest
import FoundationModels
@testable import AIPromptCore

final class AIPromptCoreTests: XCTestCase {

    public struct MockPromptNoContext: GenerableWithPrompt {
        public static var systemPrompt: String { "My template is {{input}}." }
        public static var options: GenerationOptions? { nil }

        public static var generationSchema: GenerationSchema { fatalError() }
        public init(_ content: GeneratedContent) throws { }
        public var generatedContent: GeneratedContent { fatalError() }
    }

    public struct MockPromptWithContext: GenerableWithPrompt {
        public static var systemPrompt: String { "My template is {{input}} and {{weather}}." }
        public static var options: GenerationOptions? { nil }

        public static var generationSchema: GenerationSchema { fatalError() }
        public init(_ content: GeneratedContent) throws { }
        public var generatedContent: GeneratedContent { fatalError() }
    }

    func testBuildSystemPrompt_NoContext() {
        let result = MockPromptNoContext.buildSystemPrompt(for: "sunny days", context: [:])
        XCTAssertEqual(result, "My template is sunny days.", "Should linearly replace input")
    }

    func testBuildSystemPrompt_WithContext() {
        let result = MockPromptWithContext.buildSystemPrompt(for: "sunny days", context: ["weather": "cold weather"])
        XCTAssertEqual(result, "My template is sunny days and cold weather.", "Should replace all passed keys")
    }
}

@available(macOS 26.0, iOS 26.0, *)
final class AIPromptConfigTests: XCTestCase {
    func testToGenerationOptionsGreedy() {
        let config = AIPrompt.Config(
            modelId: "test-model",
            temperature: 0.0,
            topP: 1.0,
            topK: 40,
            maxTokens: 100,
            stopSequences: []
        )
        
        let options = config.toGenerationOptions()
        XCTAssertEqual(options.maximumResponseTokens, 100, "Max tokens should map correctly")
        // Note: We cannot easily assert inside SamplingMode as it is an opaque struct.
    }

    func testToGenerationOptionsRandom() {
        let config = AIPrompt.Config(
            modelId: "test-model",
            temperature: 0.8,
            topP: 0.9,
            topK: 40,
            maxTokens: 500,
            stopSequences: []
        )
        
        let options = config.toGenerationOptions()
        XCTAssertEqual(options.maximumResponseTokens, 500, "Max tokens should map correctly")
        // Note: We cannot easily assert inside SamplingMode as it is an opaque struct.
    }
}
