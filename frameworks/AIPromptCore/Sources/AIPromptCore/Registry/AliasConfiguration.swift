import Foundation

/// Manages built-in standard aliases (e.g., whisper-1 -> apple-speech-transcribe)
/// and user-defined custom aliases (e.g., my-model -> apple-foundation-omni).
public final class AliasConfiguration: @unchecked Sendable {
    public static let shared = AliasConfiguration()
    
    private let lock = NSLock()
    private var _enableOpenAIAliases: Bool = false
    private var _customAliases: [String: String] = [:]
    
    private let userDefaultsKey = "com.apple.aibridge.custom_aliases"
    private let openAIAliasesFlagKey = "com.apple.aibridge.enable_openai_aliases"
    
    public init() {
        // 1. Check environment variable for OpenAI aliases flag
        if let envFlag = ProcessInfo.processInfo.environment["ENABLE_OPENAI_ALIASES"] {
            _enableOpenAIAliases = (envFlag == "1" || envFlag.lowercased() == "true")
        } else {
            _enableOpenAIAliases = UserDefaults.standard.bool(forKey: openAIAliasesFlagKey)
        }
        
        // 2. Load custom aliases from UserDefaults if present
        if let savedDict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] {
            _customAliases = savedDict
        }
        
        // 3. Check environment variable MODEL_ALIASES (JSON string format: {"alias": "target"})
        if let envAliases = ProcessInfo.processInfo.environment["MODEL_ALIASES"],
           let data = envAliases.data(using: .utf8),
           let json = try? JSONDecoder().decode([String: String].self, from: data) {
            _customAliases.merge(json) { _, new in new }
        }
    }
    
    /// Whether standard OpenAI aliases (e.g., whisper-1, tts-1, text-embedding-3-small, gpt-4o) are recognized.
    public var enableOpenAIAliases: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _enableOpenAIAliases
        }
        set {
            lock.lock()
            _enableOpenAIAliases = newValue
            UserDefaults.standard.set(newValue, forKey: openAIAliasesFlagKey)
            lock.unlock()
        }
    }
    
    /// User-defined custom model alias mappings (alias -> target model ID).
    public var customAliases: [String: String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _customAliases
        }
        set {
            lock.lock()
            _customAliases = newValue
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            lock.unlock()
        }
    }
    
    /// Adds or updates a single custom alias.
    public func setAlias(alias: String, target: String) {
        lock.lock()
        _customAliases[alias] = target
        UserDefaults.standard.set(_customAliases, forKey: userDefaultsKey)
        lock.unlock()
    }
    
    /// Removes a custom alias.
    public func removeAlias(alias: String) {
        lock.lock()
        _customAliases.removeValue(forKey: alias)
        UserDefaults.standard.set(_customAliases, forKey: userDefaultsKey)
        lock.unlock()
    }
    
    /// Resolves an incoming model name to its target canonical Apple model ID.
    public func resolve(modelName: String) -> String {
        let normalized = modelName.hasPrefix("openai/") ? String(modelName.dropFirst("openai/".count)) : modelName
        
        lock.lock()
        defer { lock.unlock() }
        
        // 1. Check custom aliases first
        if let customTarget = _customAliases[normalized] {
            return customTarget
        }
        
        // 2. If OpenAI aliases enabled, check standard mapping
        if _enableOpenAIAliases {
            switch normalized.lowercased() {
            // Chat
            case "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo":
                return "apple-foundation-omni"
            // Audio STT
            case "whisper-1", "whisper":
                return "apple-speech-transcribe"
            // Audio TTS
            case "tts-1", "tts-1-hd":
                return "apple-speech-synthesize"
            // Embeddings
            case "text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002":
                return "apple-sentence-embedding"
            // Moderations
            case "text-moderation-latest", "text-moderation-stable", "omni-moderation-latest":
                return "apple-sensitive-content"
            // Image Generation
            case "dall-e-3", "dall-e-2", "dall-e":
                return "apple-image-creator"
            default:
                break
            }
        }
        
        return normalized
    }
}
