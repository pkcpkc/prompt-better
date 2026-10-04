import XCTest
@testable import AIPromptCore

final class ImageGenerationTests: XCTestCase {

    func testImageCreatorGeneration() async throws {
        let service = ImageGenerationService()
        let request = OpenAI.ImageGenerationRequest(
            prompt: "A futuristic Apple Silicon processor glowing in neon violet",
            model: "apple-image-creator",
            quality: "standard",
            responseFormat: "b64_json",
            size: "512x512",
            style: "illustration"
        )
        
        let response = try await service.generate(request: request)
        XCTAssertEqual(response.data.count, 1)
        
        guard let b64 = response.data[0].b64Json, let data = Data(base64Encoded: b64) else {
            XCTFail("Missing base64 image data")
            return
        }
        
        XCTAssertGreaterThan(data.count, 100)
        // Verify PNG magic bytes (0x89, 'P', 'N', 'G')
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testImagePlaygroundGeneration() async throws {
        let service = ImageGenerationService()
        let request = OpenAI.ImageGenerationRequest(
            prompt: "Playful cartoon cat drinking boba tea",
            model: "apple-image-playground",
            responseFormat: "b64_json",
            style: "animation"
        )
        
        let response = try await service.generate(request: request)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertNotNil(response.data[0].b64Json)
        XCTAssertTrue(response.data[0].revisedPrompt?.contains("ImagePlayground") == true)
    }

    func testImageURLResponseFormat() async throws {
        let service = ImageGenerationService()
        let request = OpenAI.ImageGenerationRequest(
            prompt: "Minimalist mountain landscape",
            model: "apple-image-creator",
            responseFormat: "url",
            size: "256x256"
        )
        
        let response = try await service.generate(request: request)
        XCTAssertEqual(response.data.count, 1)
        guard let urlString = response.data[0].url, let url = URL(string: urlString) else {
            XCTFail("Missing valid image file URL")
            return
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testImagesClientSDKMethods() async throws {
        let client = ImagesClient()
        
        // 1. Headless Creator SDK method
        let creatorResponse = try await client.generateCreator(
            prompt: "Sunset over San Francisco Bay",
            style: "illustration"
        )
        XCTAssertEqual(creatorResponse.data.count, 1)
        XCTAssertNotNil(creatorResponse.data[0].b64Json)
        
        // 2. Playground SDK method
        let playgroundResponse = try await client.generatePlayground(
            prompt: "Astronaut meditating in zero gravity",
            style: "animation"
        )
        XCTAssertEqual(playgroundResponse.data.count, 1)
        XCTAssertNotNil(playgroundResponse.data[0].b64Json)
    }

    @MainActor
    func testDallEAliasResolution() async throws {
        AliasConfiguration.shared.enableOpenAIAliases = true
        
        let resolved = ModelRegistry.resolveCanonicalId("dall-e-3")
        XCTAssertEqual(resolved, "apple-image-creator")
        
        let resolved2 = ModelRegistry.resolveCanonicalId("dall-e-2")
        XCTAssertEqual(resolved2, "apple-image-creator")
    }
}
