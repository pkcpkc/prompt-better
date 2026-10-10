import XCTest
@testable import AIPromptCore

final class ImageGenerationTests: XCTestCase {

    /// Image Playground needs Apple Intelligence, a foreground window and a person choosing an image, so under
    /// a test runner it must report "unavailable" rather than invent an image.
    func testImagePlaygroundIsUnavailableWithoutHostWindow() async throws {
        let request = OpenAI.ImageGenerationRequest(prompt: "Playful cartoon cat", model: "apple-image-playground")
        do {
            _ = try await ImageGenerationService().generate(request: request)
            throw XCTSkip("A window was available to host Image Playground.")
        } catch ImageGenerationError.unavailable {
            // expected
        }
    }

    func testPNGEncodingFromImageData() throws {
        // 1x1 transparent PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        let out = try ImageGenerationService.pngData(fromImageData: png)
        XCTAssertEqual(out.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @MainActor
    func testDallEAliasResolution() async throws {
        AliasConfiguration.shared.enableOpenAIAliases = true
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("dall-e-3"), "apple-image-playground")
        XCTAssertEqual(ModelRegistry.resolveCanonicalId("dall-e-2"), "apple-image-playground")
    }
}
