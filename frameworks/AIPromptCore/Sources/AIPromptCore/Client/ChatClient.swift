import Foundation
import FoundationModels

@MainActor
public final class ChatClient: Sendable {
    public var completions: CompletionsClient {
        CompletionsClient(chatClient: self)
    }
    
    public init() {}
    
    @MainActor
    public final class CompletionsClient: Sendable {
        private weak var chatClient: ChatClient?
        
        public init(chatClient: ChatClient? = nil) {
            self.chatClient = chatClient
        }
        
        /// Standard string completion matching OpenAI SDK conventions.
        public func create(
            request: OpenAI.ChatCompletionRequest
        ) async throws -> OpenAI.ChatCompletionResponse {
            let modelId = request.model
            let canonicalId = ModelRegistry.resolveCanonicalId(modelId)
            
            guard ModelRegistry.isSupported(modelId: modelId) else {
                throw AIError.modelNotFound(modelId)
            }
            
            // Standalone Direct Models (Bypass LLM completely)
            switch canonicalId {
            case "apple-vision-ocr":
                for message in request.messages {
                    if case .parts(let parts) = message.content {
                        for part in parts {
                            if case .imageUrl(let img) = part {
                                let ocr = try await VisionOCRService.shared.recognizeText(fromURL: img.url)
                                return OpenAI.ChatCompletionResponse(
                                    id: "ocr-\(UUID().uuidString)",
                                    created: Int(Date().timeIntervalSince1970),
                                    model: canonicalId,
                                    choices: [.init(index: 0, message: .init(content: ocr), finishReason: "stop")]
                                )
                            }
                        }
                    }
                }
                return OpenAI.ChatCompletionResponse(
                    id: "ocr-\(UUID().uuidString)",
                    created: Int(Date().timeIntervalSince1970),
                    model: canonicalId,
                    choices: [.init(index: 0, message: .init(content: request.combinedPrompt), finishReason: "stop")]
                )

            case "apple-pdf-extractor":
                for message in request.messages {
                    if case .parts(let parts) = message.content {
                        for part in parts {
                            if case .document(let doc) = part, doc.format.lowercased() == "pdf", let data = Data(base64Encoded: doc.data) {
                                let text = try VisionOCRService.shared.extractText(fromPDF: data)
                                return OpenAI.ChatCompletionResponse(
                                    id: "pdf-\(UUID().uuidString)",
                                    created: Int(Date().timeIntervalSince1970),
                                    model: canonicalId,
                                    choices: [.init(index: 0, message: .init(content: text), finishReason: "stop")]
                                )
                            }
                        }
                    }
                }
                return OpenAI.ChatCompletionResponse(
                    id: "pdf-\(UUID().uuidString)",
                    created: Int(Date().timeIntervalSince1970),
                    model: canonicalId,
                    choices: [.init(index: 0, message: .init(content: request.combinedPrompt), finishReason: "stop")]
                )

            case "apple-translation":
                let translated = try await TranslationService.shared.translate(text: request.combinedPrompt)
                return OpenAI.ChatCompletionResponse(
                    id: "tr-\(UUID().uuidString)",
                    created: Int(Date().timeIntervalSince1970),
                    model: canonicalId,
                    choices: [.init(index: 0, message: .init(content: translated), finishReason: "stop")]
                )

            default:
                break
            }

            // Multimodal perception extraction (Audio transcription, Image OCR, PDF extraction)
            let effectiveRequest = try await MultimodalPipeline.shared.process(request: request)
            
            let resolvedModel = ModelRegistry.resolveLanguageModel(name: canonicalId)
            let systemInstructions = effectiveRequest.systemInstructions
            var prompt = effectiveRequest.combinedPrompt
            
            // Auto-RAG Context Injection if requested
            if let rag = effectiveRequest.rag, rag.enabled != false {
                let ragMode: SearchMode
                switch rag.mode?.lowercased() {
                case "vector": ragMode = .vectorOnly
                case "spotlight": ragMode = .spotlightOnly
                default: ragMode = .hybrid()
                }
                let retrieved = await HybridRAGFusion.search(
                    query: prompt,
                    limit: rag.limit ?? 3,
                    mode: ragMode,
                    minScore: rag.minScore
                )
                let context = HybridRAGFusion.formatContext(results: retrieved)
                if !context.isEmpty {
                    prompt = "\(context)\n\n[USER QUERY]:\n\(prompt)"
                }
            }
            
            var options = GenerationOptions()
            if let temp = request.temperature {
                if temp == 0 {
                    options.samplingMode = .greedy
                } else if let topP = request.topP {
                    options.samplingMode = .random(probabilityThreshold: Double(topP))
                }
            }
            if let maxTokens = request.maxTokens {
                options.maximumResponseTokens = maxTokens
            }
            
            let responseText = try await AISessionController.shared.respond(
                to: prompt,
                options: options,
                model: resolvedModel,
                instructions: systemInstructions.isEmpty ? nil : systemInstructions
            )
            
            return OpenAI.ChatCompletionResponse(
                id: "chatcmpl-\(UUID().uuidString)",
                created: Int(Date().timeIntervalSince1970),
                model: canonicalId,
                choices: [
                    .init(
                        index: 0,
                        message: .init(content: responseText),
                        finishReason: "stop"
                    )
                ],
                usage: .init(promptTokens: 0, completionTokens: 0, totalTokens: 0)
            )
        }
        
        /// Convenience overload with explicit parameters.
        public func create(
            model: String = ModelRegistry.defaultModelId,
            messages: [OpenAI.ChatCompletionRequest.Message],
            temperature: Float? = nil,
            topP: Float? = nil,
            maxTokens: Int? = nil,
            rag: OpenAI.ChatCompletionRequest.RAGConfiguration? = nil
        ) async throws -> OpenAI.ChatCompletionResponse {
            let request = OpenAI.ChatCompletionRequest(
                model: model,
                messages: messages,
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens,
                rag: rag
            )
            return try await create(request: request)
        }
        
        /// Type-safe structured output generation decoding directly into a @Generable conforming Swift type.
        public func create<T: Generable>(
            model: String = ModelRegistry.defaultModelId,
            messages: [OpenAI.ChatCompletionRequest.Message],
            generating type: T.Type,
            temperature: Float? = nil,
            topP: Float? = nil,
            maxTokens: Int? = nil
        ) async throws -> T {
            let canonicalId = ModelRegistry.resolveCanonicalId(model)
            guard ModelRegistry.isSupported(modelId: model) else {
                throw AIError.modelNotFound(model)
            }
            
            let resolvedModel = ModelRegistry.resolveLanguageModel(name: canonicalId)
            let request = OpenAI.ChatCompletionRequest(
                model: model,
                messages: messages,
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens
            )
            
            let systemInstructions = request.systemInstructions
            let prompt = request.combinedPrompt
            
            var options = GenerationOptions()
            if let temp = temperature {
                if temp == 0 {
                    options.samplingMode = .greedy
                } else if let p = topP {
                    options.samplingMode = .random(probabilityThreshold: Double(p))
                }
            }
            if let maxTokens = maxTokens {
                options.maximumResponseTokens = maxTokens
            }
            
            return try await AISessionController.shared.respond(
                to: prompt,
                generating: type,
                options: options,
                model: resolvedModel,
                instructions: systemInstructions.isEmpty ? nil : systemInstructions
            )
        }
    }
}
