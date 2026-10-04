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
    
    /// Processes a ChatCompletionRequest, converting attached images, audio, and documents into text blocks.
    public func process(request: OpenAI.ChatCompletionRequest) async throws -> OpenAI.ChatCompletionRequest {
        // Raw AFM models bypass perception transformations entirely
        if ModelRegistry.isRawAFM(modelId: request.model) {
            return request
        }
        
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
                        
                    case .imageUrl(let img):
                        let ocr = try await ocrService.recognizeText(fromURL: img.url)
                        if !ocr.isEmpty {
                            textComponents.append("[Attached Image OCR Extracted Text]:\n\(ocr)")
                        }
                        
                    case .inputAudio(let audio):
                        guard SpeechRecognitionService.isSupported else { break }
                        if let audioData = Data(base64Encoded: audio.data) {
                            let transcription = try? await speechService.transcribe(
                                request: OpenAI.AudioTranscriptionRequest(file: audioData)
                            )
                            if let text = transcription?.text, !text.isEmpty {
                                textComponents.append("[Attached Audio Transcription]:\n\(text)")
                            }
                        }
                        
                    case .document(let doc):
                        if let docData = Data(base64Encoded: doc.data) {
                            let docName = doc.filename ?? "document.\(doc.format)"
                            if doc.format.lowercased() == "pdf" {
                                if let extracted = try? ocrService.extractText(fromPDF: docData), !extracted.isEmpty {
                                    textComponents.append("[Attached Document '\(docName)' Content]:\n\(extracted)")
                                }
                            } else if let plainText = String(data: docData, encoding: .utf8) {
                                textComponents.append("[Attached Document '\(docName)' Content]:\n\(plainText)")
                            }
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
        return newRequest
    }
}
