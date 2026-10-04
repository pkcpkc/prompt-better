import XCTest
import PDFKit
@testable import AIPromptCore

final class PerceptionTests: XCTestCase {

    func testPDFTextExtraction() throws {
        // Create an in-memory PDF document
        let pdfDoc = PDFDocument()
        let page = PDFPage()
        pdfDoc.insert(page, at: 0)
        
        guard let data = pdfDoc.dataRepresentation() else {
            XCTFail("Failed to create in-memory PDF data")
            return
        }
        
        let extracted = try VisionOCRService.shared.extractText(fromPDF: data)
        // Newly created blank page has no text, should not throw
        XCTAssertNotNil(extracted)
    }

    func testMultimodalPipelineRawAFMPassthrough() async throws {
        let rawMessage = OpenAI.ChatCompletionRequest.Message(
            role: "user",
            parts: [.text("Hello raw AFM")]
        )
        let request = OpenAI.ChatCompletionRequest(
            model: "apple-foundation-model-3-core-3b",
            messages: [rawMessage]
        )
        
        let processed = try await MultimodalPipeline.shared.process(request: request)
        // Must remain exactly identical for raw AFM
        XCTAssertEqual(processed.model, "apple-foundation-model-3-core-3b")
        if case .parts(let parts) = processed.messages[0].content {
            XCTAssertEqual(parts.count, 1)
        } else {
            XCTFail("Raw AFM message structure should not be modified")
        }
    }

    @MainActor
    func testStandaloneTranslationBypass() async throws {
        let client = ChatClient()
        let request = OpenAI.ChatCompletionRequest(
            model: "apple-translation",
            messages: [.init(role: "user", content: "Good morning")]
        )
        
        let response = try await client.completions.create(request: request)
        XCTAssertEqual(response.model, "apple-translation")
        XCTAssertFalse(response.choices.isEmpty)
        XCTAssertEqual(response.choices.first?.message.content, "Good morning")
    }

    @MainActor
    func testStandaloneOCRBypass() async throws {
        let client = ChatClient()
        let request = OpenAI.ChatCompletionRequest(
            model: "apple-vision-ocr",
            messages: [.init(role: "user", content: "Fallback text when no image")]
        )
        
        let response = try await client.completions.create(request: request)
        XCTAssertEqual(response.model, "apple-vision-ocr")
        XCTAssertFalse(response.choices.isEmpty)
    }
}
