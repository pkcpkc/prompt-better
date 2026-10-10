import CoreGraphics
import Foundation

/// Pipeline that transforms multimodal inputs (Audio, Images/OCR, PDF Documents) into LLM-consumable prompts.
public final class MultimodalPipeline: Sendable {
    public static let shared = MultimodalPipeline()
    
    private let ocrService: VisionOCRService
    private let speechService: SpeechRecognitionService
    
    public init(
        ocrService: VisionOCRService = .shared,
        speechService: SpeechRecognitionService = .shared
    ) {
        self.ocrService = ocrService
        self.speechService = speechService
    }
    
    /// Result of the perception pass: a text-only request, plus images to hand to the model as images.
    public struct Output: Sendable {
        public var request: OpenAI.ChatCompletionRequest
        /// Images the language model should see directly. Empty unless `nativeImages` was requested.
        public var images: [CGImage]
    }
    
    /// Whether the active language model accepts images natively (`vlm`), so they need not be OCR'd.
    public static var supportsNativeImages: Bool {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        return AFMTier.detect().tier.acceptsImages
    }
    
    /// Processes a ChatCompletionRequest, converting attached images (OCR), audio, and documents into text blocks.
    public func process(request: OpenAI.ChatCompletionRequest) async throws -> OpenAI.ChatCompletionRequest {
        try await process(request: request, nativeImages: false).request
    }
    
    /// Like ``process(request:)``, but with `nativeImages` the images are returned for the model to see
    /// directly instead of being OCR'd into text.
    public func process(request: OpenAI.ChatCompletionRequest, nativeImages: Bool) async throws -> Output {
        // Raw AFM models bypass perception transformations entirely
        if ModelRegistry.isRawAFM(modelId: request.model) {
            return Output(request: request, images: [])
        }
        
        var images: [CGImage] = []
        var processedMessages: [OpenAI.ChatCompletionRequest.Message] = []
        
        for message in request.messages {
            switch message.content {
            case .text:
                processedMessages.append(message)
                
            case .parts(let parts):
                var textComponents: [String] = []
                
                for part in parts {
                    switch part {
                    case .text(let t):
                        textComponents.append(t)
                        
                    case .imageUrl(let img) where nativeImages:
                        images.append(try ImageLoading.cgImage(fromReference: img.url))
                        
                    case .imageUrl(let img):
                        // Throws if the image cannot be loaded; an image without any text gets an explicit note.
                        let ocr = try await ocrService.recognizeText(fromURL: img.url)
                        textComponents.append(ocr.isEmpty
                            ? "[Attached Image: no text was detected by OCR; its visual content cannot be described]"
                            : "[Attached Image OCR Extracted Text]:\n\(ocr)")
                        
                    case .inputAudio(let audio):
                        guard SpeechRecognitionService.isSupported else {
                            throw AIError.unsupportedOperation("Audio input requires speech recognition, which is disabled in this build. Rebuild with ENABLE_SPEECH=1 or --with-speech.")
                        }
                        guard let audioData = Data(base64Encoded: audio.data) else {
                            throw AIError.unsupportedOperation("Audio attachment is not valid base64 data.")
                        }
                        let transcription = try await speechService.transcribe(
                            request: OpenAI.AudioTranscriptionRequest(file: audioData)
                        )
                        textComponents.append(transcription.text.isEmpty
                            ? "[Attached Audio: no speech was recognized]"
                            : "[Attached Audio Transcription]:\n\(transcription.text)")
                        
                    case .document(let doc):
                        let docName = doc.filename ?? "document.\(doc.format)"
                        guard let docData = Data(base64Encoded: doc.data) else {
                            throw AIError.unsupportedOperation("Document '\(docName)' is not valid base64 data.")
                        }
                        if doc.format.lowercased() == "pdf" {
                            let extracted = try ocrService.extractText(fromPDF: docData)
                            textComponents.append(extracted.isEmpty
                                ? "[Attached Document '\(docName)': the PDF contains no extractable text (it may be a scan)]"
                                : "[Attached Document '\(docName)' Content]:\n\(extracted)")
                        } else if let plainText = String(data: docData, encoding: .utf8) {
                            textComponents.append("[Attached Document '\(docName)' Content]:\n\(plainText)")
                        } else {
                            throw AIError.unsupportedOperation("Document '\(docName)' has unsupported format '\(doc.format)'; only PDF and UTF-8 text are supported.")
                        }
                    }
                }
                
                let combinedText = textComponents.joined(separator: "\n\n")
                var newMessage = message
                newMessage.content = .text(combinedText)
                processedMessages.append(newMessage)
            }
        }
        
        var newRequest = request
        newRequest.messages = processedMessages
        return Output(request: newRequest, images: images)
    }
}
