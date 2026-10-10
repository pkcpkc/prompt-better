import Foundation

@MainActor
public protocol AppleOpenAIClientProtocol: Sendable {
    var chat: ChatClient { get }
    var prompts: PromptsClient { get }
    var index: IndexClient { get }
    var embeddings: EmbeddingsClient { get }
    var audio: AudioClient { get }
    var images: ImagesClient { get }
    var moderations: ModerationsClient { get }
}

/// In-Process Swift client offering OpenAI-compatible SDK access with zero HTTP overhead.
@MainActor
public final class AppleOpenAIClient: AppleOpenAIClientProtocol, Sendable {
    public static let shared = AppleOpenAIClient()
    
    public let chat: ChatClient
    public let prompts: PromptsClient
    public let index: IndexClient
    public let embeddings: EmbeddingsClient
    public let audio: AudioClient
    public let images: ImagesClient
    public let moderations: ModerationsClient
    
    public init() {
        self.chat = ChatClient()
        self.prompts = PromptsClient()
        self.index = IndexClient()
        self.embeddings = EmbeddingsClient()
        self.audio = AudioClient()
        self.images = ImagesClient()
        self.moderations = ModerationsClient()
    }
}
