import XCTest
@testable import AIPromptCore

final class EmbeddingsTests: XCTestCase {

    func testSentenceEmbeddingGeneration() async throws {
        let service = EmbeddingService()
        let request = OpenAI.EmbeddingRequest(model: "apple-sentence-embedding", string: "Apple Intelligence running on macOS and iOS.")
        let response = try await service.create(request: request)
        
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.model, "apple-sentence-embedding")
        XCTAssertFalse(response.data[0].embedding.isEmpty)
        XCTAssertEqual(response.data[0].embedding.count, 512)
    }

    func testWordEmbeddingGeneration() async throws {
        let service = EmbeddingService()
        let request = OpenAI.EmbeddingRequest(model: "apple-word-embedding", string: "swift")
        let response = try await service.create(request: request)
        
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.model, "apple-word-embedding")
        XCTAssertFalse(response.data[0].embedding.isEmpty)
        XCTAssertEqual(response.data[0].embedding.count, 300)
    }

    func testVisionFeaturePrintGeneration() async throws {
        let service = EmbeddingService()
        let request = OpenAI.EmbeddingRequest(model: "apple-vision-featureprint", string: "raw-text-fallback")
        let response = try await service.create(request: request)
        
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.model, "apple-vision-featureprint")
        XCTAssertFalse(response.data[0].embedding.isEmpty)
        XCTAssertEqual(response.data[0].embedding.count, 768)
    }

    @MainActor
    func testEmbeddingsClientWithAliases() async throws {
        // Enable OpenAI aliases
        AliasConfiguration.shared.enableOpenAIAliases = true
        
        let client = EmbeddingsClient()
        let response = try await client.create(
            input: ["First document test.", "Second document test."],
            model: "text-embedding-3-small"
        )
        
        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.data[0].index, 0)
        XCTAssertEqual(response.data[1].index, 1)
        XCTAssertEqual(response.data[0].embedding.count, 512)
        XCTAssertEqual(response.data[1].embedding.count, 512)
    }
}
