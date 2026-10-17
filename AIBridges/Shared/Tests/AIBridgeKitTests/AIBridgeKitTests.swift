import Foundation
import FoundationModels
import XCTest

@testable import AIBridgeKit

final class AIBridgeKitTests: XCTestCase {

    private func request(_ messages: [OpenAI.ChatCompletionRequest.Message]) -> OpenAI.ChatCompletionRequest {
        OpenAI.ChatCompletionRequest(model: "default", messages: messages)
    }

    func testSystemMessagesBecomeInstructions() {
        let req = request([
            .init(role: "system", content: "Instruction A"),
            .init(role: "system", content: "Instruction B"),
            .init(role: "user", content: "Query text")
        ])
        XCTAssertEqual(req.systemInstructions, "Instruction A\n\nInstruction B")
        XCTAssertEqual(req.combinedPrompt, "Query text")
    }

    func testConversationIsJoinedIntoOnePrompt() {
        let req = request([
            .init(role: "user", content: "Hello!"),
            .init(role: "assistant", content: "Hi!"),
            .init(role: "user", content: "How are you?")
        ])
        XCTAssertEqual(req.systemInstructions, "")
        XCTAssertEqual(req.combinedPrompt, "Hello!\n\nHi!\n\nHow are you?")
    }

    func testDecodesStringPartsAndNullContent() throws {
        let json = """
        {"model": "openai/default", "temperature": 0, "top_p": 0.9, "max_tokens": 64,
         "messages": [
           {"role": "system", "content": [{"type": "text", "text": "Be brief."}]},
           {"role": "assistant", "content": null},
           {"role": "user", "content": "Hi"}
         ]}
        """
        let req = try JSONDecoder().decode(OpenAI.ChatCompletionRequest.self, from: Data(json.utf8))
        XCTAssertEqual(req.systemInstructions, "Be brief.")
        XCTAssertEqual(req.combinedPrompt, "\n\nHi")
        XCTAssertEqual(req.maxTokens, 64)
        XCTAssertEqual(BridgeModel.resolve(req.model), .defaultAFM)
    }

    func testModelResolution() {
        XCTAssertEqual(BridgeModel.resolve("apple-foundation-model-3-core-3b"), .foundationModel3B)
        XCTAssertEqual(BridgeModel.resolve("openai/apple-intelligence-private-cloud-compute"), .privateCloudCompute)
        XCTAssertNil(BridgeModel.resolve("omni"))
    }

    func testRejectsNonTextParts() {
        let req = request([
            .init(role: "user", content: .parts([.init(type: "image_url", text: nil)]))
        ])
        XCTAssertThrowsError(try ChatCompletionService.requireTextOnly(req.messages)) { error in
            XCTAssertEqual((error as? OpenAIAPIError)?.code, "unsupported_operation")
        }
    }

    func testGenerationOptionsMapping() {
        var req = request([.init(role: "user", content: "x")])
        req.maxTokens = 32
        XCTAssertEqual(ChatCompletionService.generationOptions(for: req).maximumResponseTokens, 32)

        req.temperature = 0
        XCTAssertEqual(ChatCompletionService.generationOptions(for: req).samplingMode, .greedy)

        req.temperature = 0.7
        req.topP = 0.5
        XCTAssertEqual(ChatCompletionService.generationOptions(for: req).samplingMode, .random(probabilityThreshold: 0.5))
    }
}
