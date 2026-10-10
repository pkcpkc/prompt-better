import Foundation

public extension OpenAI {
    
    // MARK: - Speech to Text (STT)
    
    struct AudioTranscriptionRequest: Codable, Sendable {
        public var file: Data?
        public var filename: String?
        public var model: String
        public var language: String?
        public var prompt: String?
        public var responseFormat: String? // "json", "text", "verbose_json"
        public var temperature: Float?
        
        public init(
            file: Data? = nil,
            filename: String? = nil,
            model: String = "apple-speech-transcribe",
            language: String? = nil,
            prompt: String? = nil,
            responseFormat: String? = "json",
            temperature: Float? = nil
        ) {
            self.file = file
            self.filename = filename
            self.model = model
            self.language = language
            self.prompt = prompt
            self.responseFormat = responseFormat
            self.temperature = temperature
        }
        
        public enum CodingKeys: String, CodingKey {
            case file, filename, model, language, prompt, temperature
            case responseFormat = "response_format"
        }
    }
    
    struct AudioTranscriptionResponse: Codable, Sendable {
        public let text: String
        
        public init(text: String) {
            self.text = text
        }
    }
    
    // MARK: - Speech Translation (audio -> English text)
    
    struct AudioTranslationRequest: Codable, Sendable {
        public var file: Data?
        public var filename: String?
        public var model: String
        /// Spoken language of the audio (e.g. "de-DE"). Required for recognition; the output is always English.
        public var language: String?
        public var prompt: String?
        public var responseFormat: String?
        public var temperature: Float?
        
        public init(
            file: Data? = nil,
            filename: String? = nil,
            model: String = "apple-speech-translate",
            language: String? = nil,
            prompt: String? = nil,
            responseFormat: String? = "json",
            temperature: Float? = nil
        ) {
            self.file = file
            self.filename = filename
            self.model = model
            self.language = language
            self.prompt = prompt
            self.responseFormat = responseFormat
            self.temperature = temperature
        }
        
        public enum CodingKeys: String, CodingKey {
            case file, filename, model, language, prompt, temperature
            case responseFormat = "response_format"
        }
    }
    
    // MARK: - Text to Speech (TTS)
    
    struct AudioSpeechRequest: Codable, Sendable {
        public var model: String
        public var input: String
        public var voice: String
        public var responseFormat: String? // "wav", "aac", "mp3"
        public var speed: Float?
        
        public init(
            model: String = "apple-speech-synthesize",
            input: String,
            voice: String = "siri-neutral",
            responseFormat: String? = "wav",
            speed: Float? = nil
        ) {
            self.model = model
            self.input = input
            self.voice = voice
            self.responseFormat = responseFormat
            self.speed = speed
        }
        
        public enum CodingKeys: String, CodingKey {
            case model, input, voice, speed
            case responseFormat = "response_format"
        }
    }
}
