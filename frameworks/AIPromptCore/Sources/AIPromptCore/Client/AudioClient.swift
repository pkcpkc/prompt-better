import Foundation

/// In-process Audio client providing OpenAI-compatible Speech-to-Text and Text-to-Speech.
@MainActor
public final class AudioClient: Sendable {
    public let transcriptions: TranscriptionsClient
    public let speech: SpeechClient
    
    public init() {
        self.transcriptions = TranscriptionsClient()
        self.speech = SpeechClient()
    }
    
    @MainActor
    public final class TranscriptionsClient: Sendable {
        private let service: SpeechRecognitionService
        
        public init(service: SpeechRecognitionService = .shared) {
            self.service = service
        }
        
        public func create(
            file: Data,
            filename: String = "audio.wav",
            model: String = "apple-speech-transcribe",
            language: String? = nil,
            prompt: String? = nil
        ) async throws -> OpenAI.AudioTranscriptionResponse {
            let req = OpenAI.AudioTranscriptionRequest(
                file: file,
                filename: filename,
                model: model,
                language: language,
                prompt: prompt
            )
            return try await service.transcribe(request: req)
        }
        
        public func create(_ request: OpenAI.AudioTranscriptionRequest) async throws -> OpenAI.AudioTranscriptionResponse {
            return try await service.transcribe(request: request)
        }
    }
    
    @MainActor
    public final class SpeechClient: Sendable {
        private let service: AudioSynthesisService
        
        public init(service: AudioSynthesisService = .shared) {
            self.service = service
        }
        
        public func create(
            input: String,
            voice: String = "siri-neutral",
            model: String = "apple-speech-synthesize",
            responseFormat: String = "wav",
            speed: Float? = nil
        ) async throws -> Data {
            let req = OpenAI.AudioSpeechRequest(
                model: model,
                input: input,
                voice: voice,
                responseFormat: responseFormat,
                speed: speed
            )
            return try await service.synthesize(request: req)
        }
        
        public func create(_ request: OpenAI.AudioSpeechRequest) async throws -> Data {
            return try await service.synthesize(request: request)
        }
    }
}
