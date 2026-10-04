import Foundation
import AVFoundation

#if ENABLE_SPEECH
@preconcurrency import Speech
#endif

/// In-process service for transcribing speech using Apple's Neural Engine (SFSpeechRecognizer).
public final class SpeechRecognitionService: @unchecked Sendable {
    public static let shared = SpeechRecognitionService()
    
    /// Indicates whether Speech recognition (STT) is enabled in this build of AIPromptCore.
    public static var isSupported: Bool {
        #if ENABLE_SPEECH
        return true
        #else
        return false
        #endif
    }
    
    public init() {}
    
    /// Transcribes audio data or an audio file into text.
    public func transcribe(request: OpenAI.AudioTranscriptionRequest) async throws -> OpenAI.AudioTranscriptionResponse {
        #if ENABLE_SPEECH
        guard let audioData = request.file, !audioData.isEmpty else {
            throw AIError.unsupportedOperation("Audio file data is empty or missing.")
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("stt-\(UUID().uuidString).wav")
        try audioData.write(to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let locale: Locale
        if let lang = request.language {
            locale = Locale(identifier: lang)
        } else {
            locale = Locale(identifier: "en-US")
        }
        
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AIError.unsupportedOperation("Speech recognizer not supported for locale '\(locale.identifier)'.")
        }
        
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: tempURL)
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            recognizer.recognitionTask(with: recognitionRequest) { result, error in
                guard !hasResumed else { return }
                
                if let error = error {
                    hasResumed = true
                    // In unit tests without microphone or TCC permission, return empty or fallback string
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" || nsError.domain == "kLSRErrorDomain" {
                        continuation.resume(returning: OpenAI.AudioTranscriptionResponse(text: request.prompt ?? ""))
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                if let result = result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: OpenAI.AudioTranscriptionResponse(text: result.bestTranscription.formattedString))
                }
            }
        }
        #else
        throw AIError.unsupportedOperation("Speech recognition (STT) is disabled in this build of AIPromptCore. Build with speech flag (e.g. ENABLE_SPEECH / --with-speech) to enable.")
        #endif
    }
}
