import FoundationModels
import Vapor

@MainActor
final class LocalAIBridge {
    static let shared = LocalAIBridge()
    private var session: LanguageModelSession?

    private init() {}

    /// Generates a response using the local FoundationModels framework.
    func generate(request: OpenAI.ChatCompletionRequest) async throws -> String {
        let session = try getSession()
        
        // Prepare the prompt by combining messages seamlessly
        let combinedPrompt = request.messages.map { $0.content }.joined(separator: "\n\n")
        
        // Create the generation options from the request
        var options = GenerationOptions()
        if let temp = request.temperature { options.temperature = Double(temp) }
        
        if let topP = request.topP {
            options.sampling = .random(probabilityThreshold: Double(topP))
        }
        
        if let maxTokens = request.maxTokens {
            options.maximumResponseTokens = maxTokens
        }
        // stopSequences not supported in this version of Mac SDK

        // Use the direct String-based respond method for maximum simplicity
        let response = try await session.respond(
            to: combinedPrompt,
            options: options
        )
        
        return response.content
    }

    private func getSession() throws -> LanguageModelSession {
        if let session = session {
            return session
        }
        // Use default initialization
        let newSession = LanguageModelSession()
        self.session = newSession
        return newSession
    }
    
    /// Lists all available models in the local framework.
    func listModels() async -> [OpenAI.ModelListResponse.Model] {
        return [
            .init(id: "apple-intelligence-base"),
            .init(id: "apple-intelligence-chat")
        ]
    }
}
