import Foundation

/// What a model is, using standard industry terms rather than product names.
public enum ModelType: String, Sendable, CaseIterable {
    /// Text-only large language model.
    case llm
    /// Vision-language model: a language model that accepts images together with text.
    case vlm
    /// Language model fronted by a perception pipeline that accepts images, audio and documents, with optional local RAG.
    case multimodal
    /// Optical character recognition (image to text).
    case ocr
    /// Document text extraction (PDF to text).
    case document
    /// Machine translation.
    case translation
    /// Natural language processing: tagging and entity recognition.
    case nlp
    /// Speech to text, including speech translation.
    case stt
    /// Text to speech.
    case tts
    /// Vector embeddings.
    case embedding
    /// Content moderation.
    case moderation
    /// Retrieval over the local index.
    case search
    /// Image generation.
    case imageGeneration = "image-generation"
}

/// A kind of input a model consumes.
public enum InputModality: String, Sendable, CaseIterable {
    case text
    /// Images; chat UIs also accept videos for these models and sample frames from them.
    case image
    case audio
    case document
}
