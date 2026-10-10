import Foundation
import CoreGraphics
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
            try Self.requireChatCapable(canonicalId)
            try Self.requireSupportedMedia(request.messages, model: canonicalId)
            
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
                throw AIError.unsupportedOperation("Model 'apple-vision-ocr' requires an image_url content part.")

            case "apple-pdf-extractor":
                for message in request.messages {
                    if case .parts(let parts) = message.content {
                        for part in parts {
                            if case .document(let doc) = part {
                                guard doc.format.lowercased() == "pdf" else {
                                    throw AIError.unsupportedOperation("Model 'apple-pdf-extractor' only accepts PDF documents, got '\(doc.format)'.")
                                }
                                guard let data = Data(base64Encoded: doc.data) else {
                                    throw AIError.unsupportedOperation("PDF document is not valid base64 data.")
                                }
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
                throw AIError.unsupportedOperation("Model 'apple-pdf-extractor' requires a document content part with format 'pdf'.")

            case "apple-nl-tagger":
                let analysis = try NLTaggerService.shared.analyzeJSON(text: request.combinedPrompt)
                return OpenAI.ChatCompletionResponse(
                    id: "nl-\(UUID().uuidString)",
                    created: Int(Date().timeIntervalSince1970),
                    model: canonicalId,
                    choices: [.init(index: 0, message: .init(content: analysis), finishReason: "stop")]
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
            // Images are seen natively by image-capable models (vlm) and OCR'd otherwise.
            let perception = try await MultimodalPipeline.shared.process(
                request: request,
                nativeImages: MultimodalPipeline.supportsNativeImages
            )
            let effectiveRequest = perception.request
            
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
            
            // Image-capable language models (vlm) receive images natively: raw models take them straight from
            // the request (the media check above rejects everything else), omni gets them from the perception pass.
            let images = ModelRegistry.isRawAFM(modelId: canonicalId)
                ? try Self.images(in: request.messages)
                : perception.images
            if !images.isEmpty {
                let text = try await AISessionController.shared.respond(
                    to: prompt,
                    images: images,
                    options: options,
                    model: resolvedModel,
                    instructions: systemInstructions.isEmpty ? nil : systemInstructions
                )
                return OpenAI.ChatCompletionResponse(
                    id: "chatcmpl-\(UUID().uuidString)",
                    created: Int(Date().timeIntervalSince1970),
                    model: canonicalId,
                    choices: [.init(index: 0, message: .init(content: text), finishReason: "stop")],
                    usage: .init(promptTokens: 0, completionTokens: 0, totalTokens: 0)
                )
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
        
        /// Raw language models skip the perception pipeline, so media they cannot take natively would be
        /// silently dropped. Fail loudly instead, naming what the model does accept.
        private static func requireSupportedMedia(_ messages: [OpenAI.ChatCompletionRequest.Message], model canonicalId: String) throws {
            guard ModelRegistry.isRawAFM(modelId: canonicalId) else { return }
            let model = CanonicalModel(rawValue: canonicalId)
            let allowed = model?.inputModalities ?? [.text]
            for message in messages {
                guard case .parts(let parts) = message.content else { continue }
                for part in parts {
                    let modality: InputModality
                    switch part {
                    case .text: continue
                    case .imageUrl: modality = .image
                    case .inputAudio: modality = .audio
                    case .document: modality = .document
                    }
                    guard !allowed.contains(modality) else { continue }
                    let kind = model?.type.rawValue ?? "llm"
                    throw AIError.unsupportedOperation(
                        "Model '\(canonicalId)' (\(kind)) cannot process \(modality.rawValue) input. Use 'omni' (extracts audio, documents and image text first) or a direct model such as 'apple-vision-ocr'."
                    )
                }
            }
        }
        
        /// Image references attached to the messages, loaded for models that take images natively.
        private static func images(in messages: [OpenAI.ChatCompletionRequest.Message]) throws -> [CGImage] {
            try messages.flatMap { message -> [CGImage] in
                guard case .parts(let parts) = message.content else { return [] }
                return try parts.compactMap { part in
                    guard case .imageUrl(let image) = part else { return nil }
                    return try ImageLoading.cgImage(fromReference: image.url)
                }
            }
        }
        
        /// Rejects canonical models that do not serve chat (embeddings, audio, images, search) instead of silently routing them to the language model.
        private static func requireChatCapable(_ canonicalId: String) throws {
            guard let model = CanonicalModel(rawValue: canonicalId) else { return }
            guard model.isChatCapable else {
                throw AIError.unsupportedOperation("Model '\(canonicalId)' does not support chat completions; use its dedicated endpoint.")
            }
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
        public func create<T: Generable & Sendable>(
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
            
            try Self.requireChatCapable(canonicalId)
            try Self.requireSupportedMedia(messages, model: canonicalId)
            if try !Self.images(in: messages).isEmpty {
                throw AIError.unsupportedOperation("Image input is not supported with typed (@Generable) generation.")
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
