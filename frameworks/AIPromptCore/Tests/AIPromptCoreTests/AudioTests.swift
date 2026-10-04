import XCTest
@testable import AIPromptCore

final class AudioTests: XCTestCase {

    func testAudioSynthesisWAVGeneration() async throws {
        let service = AudioSynthesisService()
        let request = OpenAI.AudioSpeechRequest(
            model: "apple-speech-synthesize",
            input: "Hello from on-device Apple Intelligence.",
            voice: "alloy",
            responseFormat: "wav",
            speed: 1.0
        )
        
        let wavData = try await service.synthesize(request: request)
        XCTAssertFalse(wavData.isEmpty)
        
        // Verify WAV header RIFF & WAVE markers
        let riffHeader = String(data: wavData.prefix(4), encoding: .utf8)
        XCTAssertEqual(riffHeader, "RIFF")
        
        let waveHeader = String(data: wavData.subdata(in: 8..<12), encoding: .utf8)
        XCTAssertEqual(waveHeader, "WAVE")
    }

    func testSpeechSupportFlagStatus() {
        #if ENABLE_SPEECH
        XCTAssertTrue(SpeechRecognitionService.isSupported)
        #else
        XCTAssertFalse(SpeechRecognitionService.isSupported)
        #endif
    }

    @MainActor
    func testAudioClientSpeechAndTranscription() async throws {
        let client = AudioClient()
        
        // 1. Text to Speech (supported via AVFoundation)
        let audioData = try await client.speech.create(
            input: "Speech synthesis test",
            voice: "siri-neutral"
        )
        XCTAssertFalse(audioData.isEmpty)
        
        // 2. Speech to Text
        #if ENABLE_SPEECH
        let transcription = try await client.transcriptions.create(
            file: audioData,
            model: "apple-speech-transcribe",
            language: "en-US",
            prompt: "Speech synthesis test"
        )
        // Ensure result text is returned (transcribed or prompt fallback)
        XCTAssertFalse(transcription.text.isEmpty)
        #else
        XCTAssertFalse(SpeechRecognitionService.isSupported)
        do {
            _ = try await client.transcriptions.create(
                file: audioData,
                model: "apple-speech-transcribe",
                language: "en-US",
                prompt: "Speech synthesis test"
            )
            XCTFail("Expected unsupportedOperation error when built without speech")
        } catch let AIError.unsupportedOperation(message) {
            XCTAssertTrue(message.contains("Speech recognition (STT) is disabled"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        #endif
    }
}
