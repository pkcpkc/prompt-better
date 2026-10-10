import XCTest
import CoreGraphics
import ImageIO
@testable import AIPromptCore

@MainActor
final class ModelHandlerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AliasConfiguration.shared.enableOpenAIAliases = false
        AliasConfiguration.shared.customAliases = [:]
    }

    func testAllRegisteredModelsAreAdvertised() {
        let ids = ModelRegistry.listModels().map(\.id)
        XCTAssertTrue(ids.contains("apple-sensitive-content"))
        XCTAssertTrue(ids.contains("apple-speech-translate"))
        XCTAssertTrue(ids.contains("apple-nl-tagger"))
    }

    func testNonChatModelsAreRejectedByChat() async {
        for model in ["apple-sentence-embedding", "apple-speech-synthesize", "apple-image-playground", "apple-sensitive-content"] {
            do {
                _ = try await AppleOpenAIClient.shared.chat.completions.create(
                    model: model,
                    messages: [.init(role: "user", content: "hi")]
                )
                XCTFail("\(model) should not be served by chat completions")
            } catch AIError.unsupportedOperation {
                // expected
            } catch {
                XCTFail("Unexpected error for \(model): \(error)")
            }
        }
    }

    func testModerationRejectsTextInput() async {
        let inputs: [OpenAI.ModerationRequest.Input] = [
            .text("some text"),
            .texts(["a", "b"]),
            .parts([.text("some text")])
        ]
        for input in inputs {
            do {
                _ = try await AppleOpenAIClient.shared.moderations.create(.init(input: input))
                XCTFail("Text moderation should be rejected")
            } catch AIError.unsupportedOperation {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testModerationRejectsUndecodableImage() async {
        do {
            _ = try await AppleOpenAIClient.shared.moderations.create(images: ["data:image/png;base64,AAAA"])
            XCTFail("Expected unsupportedOperation")
        } catch AIError.unsupportedOperation {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testModerationInputDecodesOpenAIShapes() throws {
        let decoder = JSONDecoder()
        let s = try decoder.decode(OpenAI.ModerationRequest.self, from: Data(#"{"input": "hi"}"#.utf8))
        guard case .text = s.input else { return XCTFail("string") }
        let a = try decoder.decode(OpenAI.ModerationRequest.self, from: Data(#"{"input": ["a","b"]}"#.utf8))
        guard case .texts = a.input else { return XCTFail("array") }
        let p = try decoder.decode(OpenAI.ModerationRequest.self, from: Data(#"{"input": [{"type":"image_url","image_url":{"url":"data:image/png;base64,AA"}}]}"#.utf8))
        guard case .parts(let parts) = p.input, parts.first?.imageUrl?.url == "data:image/png;base64,AA" else { return XCTFail("parts") }
    }

    func testRawModelsRejectMediaTheyCannotProcess() async {
        let image = OpenAI.ChatCompletionRequest.ContentPart.imageUrl(.init(url: "data:image/png;base64,AAAA"))
        let audio = OpenAI.ChatCompletionRequest.ContentPart.inputAudio(.init(data: "AAAA", format: "wav"))
        let doc = OpenAI.ChatCompletionRequest.ContentPart.document(.init(data: "aGk=", format: "txt"))
        let tierTakesImages = AFMTier.detect().tier.acceptsImages
        let systemFamily = ["default", "apple-foundation-model-3-core-3b", "apple-foundation-model"]
        let cases: [(model: String, part: OpenAI.ChatCompletionRequest.ContentPart, rejected: Bool)] =
            systemFamily.flatMap { [($0, audio, true), ($0, doc, true), ($0, image, !tierTakesImages)] }
            + [("apple-intelligence-private-cloud-compute", image, true), ("apple-intelligence-private-cloud-compute", doc, true)]
        for (model, part, rejected) in cases where rejected {
            do {
                _ = try await AppleOpenAIClient.shared.chat.completions.create(
                    model: model,
                    messages: [.init(role: "user", parts: [.text("describe"), part])]
                )
                XCTFail("\(model) should reject \(part)")
            } catch AIError.unsupportedOperation(let reason) {
                XCTAssertTrue(reason.contains("omni"), reason)
            } catch {
                XCTFail("Unexpected error for \(model): \(error)")
            }
        }
    }

    /// A 400x300 PNG data URL: a red circle on a blue background.
    private func redCircleDataURL() throws -> String {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 120, y: 70, width: 160, height: 160))
        let image = try XCTUnwrap(ctx.makeImage())
        let png = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return "data:image/png;base64,\((png as Data).base64EncodedString())"
    }

    func testVLMTierDescribesImages() async throws {
        guard AFMTier.detect().tier.acceptsImages else { throw XCTSkip("The active model tier does not accept images") }
        let response = try await AppleOpenAIClient.shared.chat.completions.create(
            model: "default",
            messages: [.init(role: "user", parts: [
                .text("What color is the circle? Answer with one word."),
                .imageUrl(.init(url: try redCircleDataURL()))
            ])]
        )
        let answer = (response.choices.first?.message.content ?? "").lowercased()
        XCTAssertTrue(answer.contains("red"), "Unexpected answer: \(answer)")
    }

    func testOmniSeesImagesNativelyOnVLMTier() async throws {
        guard AFMTier.detect().tier.acceptsImages else { throw XCTSkip("The active model tier does not accept images") }
        // The circle contains no text, so OCR alone could never answer this.
        let response = try await AppleOpenAIClient.shared.chat.completions.create(
            model: "omni",
            messages: [.init(role: "user", parts: [
                .text("What color is the circle? Answer with one word."),
                .imageUrl(.init(url: try redCircleDataURL()))
            ])]
        )
        let answer = (response.choices.first?.message.content ?? "").lowercased()
        XCTAssertTrue(answer.contains("red"), "Unexpected answer: \(answer)")
    }

    func testPipelineReturnsImagesInsteadOfOCRWhenNative() async throws {
        let url = try redCircleDataURL()
        let request = OpenAI.ChatCompletionRequest(
            model: "omni",
            messages: [.init(role: "user", parts: [.text("hi"), .imageUrl(.init(url: url))])]
        )
        let native = try await MultimodalPipeline.shared.process(request: request, nativeImages: true)
        XCTAssertEqual(native.images.count, 1)
        XCTAssertEqual(native.request.messages.first?.content.rawText, "hi")

        let ocr = try await MultimodalPipeline.shared.process(request: request, nativeImages: false)
        XCTAssertTrue(ocr.images.isEmpty)
        XCTAssertTrue(ocr.request.messages.first?.content.rawText.contains("[Attached Image") == true)
    }

    private func omni(_ part: OpenAI.ChatCompletionRequest.ContentPart) async throws -> String {
        let response = try await AppleOpenAIClient.shared.chat.completions.create(
            request: .init(model: "omni", messages: [.init(role: "user", parts: [part])])
        )
        return response.choices.first?.message.content ?? ""
    }

    func testPerceptionRejectsUnprocessableMediaInsteadOfDroppingIt() async {
        let bad: [OpenAI.ChatCompletionRequest.ContentPart] = [
            .imageUrl(.init(url: "data:image/png;base64,!!!not-base64!!!")),
            .imageUrl(.init(url: "data:image/png;base64,AAAA")),
            .document(.init(data: "!!!", format: "txt")),
            .document(.init(data: "/wA=", format: "bin")),   // bytes 0xFF 0x00: not UTF-8
            .document(.init(data: "AAAA", format: "pdf")),   // not a PDF
        ]
        for part in bad {
            do {
                _ = try await omni(part)
                XCTFail("Expected an error for \(part)")
            } catch AIError.unsupportedOperation {
            } catch {
                XCTFail("Unexpected error for \(part): \(error)")
            }
        }
    }

    func testDirectModelsRequireTheirMedia() async {
        for model in ["apple-vision-ocr", "apple-pdf-extractor"] {
            do {
                _ = try await AppleOpenAIClient.shared.chat.completions.create(
                    model: model, messages: [.init(role: "user", content: "just text")]
                )
                XCTFail("\(model) should require media")
            } catch AIError.unsupportedOperation {
            } catch {
                XCTFail("Unexpected error for \(model): \(error)")
            }
        }
    }

    func testMalformedContentIsNotSwallowedByDecoding() throws {
        let decoder = JSONDecoder()
        let unknown = #"{"model":"m","messages":[{"role":"user","content":[{"type":"video_url","video_url":{"url":"x"}}]}]}"#
        XCTAssertThrowsError(try decoder.decode(OpenAI.ChatCompletionRequest.self, from: Data(unknown.utf8)))
        let garbage = #"{"model":"m","messages":[{"role":"user","content":42}]}"#
        XCTAssertThrowsError(try decoder.decode(OpenAI.ChatCompletionRequest.self, from: Data(garbage.utf8)))
        let null = #"{"model":"m","messages":[{"role":"assistant","content":null}]}"#
        XCTAssertNoThrow(try decoder.decode(OpenAI.ChatCompletionRequest.self, from: Data(null.utf8)))
    }

    func testNLTaggerExtractsEntities() async throws {
        let response = try await AppleOpenAIClient.shared.chat.completions.create(
            model: "apple-nl-tagger",
            messages: [.init(role: "user", content: "Tim Cook presented the new iPhone in Cupertino.")]
        )
        let json = try XCTUnwrap(response.choices.first?.message.content)
        let analysis = try JSONDecoder().decode(NLTaggerService.Analysis.self, from: Data(json.utf8))
        XCTAssertEqual(analysis.language, "en")
        XCTAssertTrue(analysis.entities.contains { $0.text.contains("Cupertino") })
        XCTAssertFalse(analysis.tokens.isEmpty)
    }

    func testTranslationSameLanguageIsPassthrough() async throws {
        let out = try await TranslationService.shared.translate(text: "Hello", sourceLanguage: "en", targetLanguage: "en-US")
        XCTAssertEqual(out, "Hello")
    }

    func testSpeechTranslateDisabledWithoutSpeechFlag() async {
        #if !ENABLE_SPEECH
        do {
            _ = try await AppleOpenAIClient.shared.audio.translations.create(file: Data([0]), language: "de-DE")
            XCTFail("Expected unsupportedOperation")
        } catch AIError.unsupportedOperation {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        #endif
    }

    func testEveryModelHasATypeAndInputs() {
        for model in CanonicalModel.allCases {
            XCTAssertFalse(model.inputModalities.isEmpty, "\(model.rawValue) has no input modality")
            if model.inputModalities.contains(.document) {
                XCTAssertFalse(model.documentFormats.isEmpty, "\(model.rawValue) accepts documents but lists no formats")
            }
        }
        // The system-default family follows the active tier; Private Cloud Compute stays text-only.
        let takesImages = AFMTier.detect().tier.acceptsImages
        for model in [CanonicalModel.defaultAFM, .foundationModel3B, .foundationModelGeneric] {
            XCTAssertEqual(model.type, takesImages ? .vlm : .llm)
            XCTAssertEqual(model.inputModalities, takesImages ? [.text, .image] : [.text])
        }
        XCTAssertEqual(CanonicalModel.privateCloudCompute.type, .llm)
        XCTAssertEqual(CanonicalModel.privateCloudCompute.inputModalities, [.text])
        XCTAssertEqual(CanonicalModel.omni.type, .multimodal)
        XCTAssertEqual(CanonicalModel.visionOCR.inputModalities, [.image])
        XCTAssertEqual(CanonicalModel.pdfExtractor.documentFormats, ["pdf"])
    }

    func testModelListExposesTypeAndInputModalities() throws {
        let models = ModelRegistry.listModels()
        let omni = try XCTUnwrap(models.first { $0.id == "omni" })
        XCTAssertEqual(omni.type, "multimodal")
        XCTAssertEqual(omni.inputModalities, ["audio", "document", "image", "text"])
        let json = try JSONEncoder().encode(omni)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "multimodal")
        XCTAssertNotNil(object["input_modalities"])
    }
}
