import Foundation

/// Runs one chat turn through `AppleOpenAIClient`, the same path the HTTP bridge uses, so attachments
/// are handled (or rejected) exactly as they are for `POST /v1/chat/completions`.
///
/// Raw language models (`default`, the AFM aliases, Private Cloud Compute) cannot process media and
/// throw an error; `omni` and the direct models (OCR, PDF, ...) accept attachments.
@MainActor
enum ChatTurnRunner {
    struct Outcome {
        let reply: String
        /// For omni: the user prompt with attachment content extracted to text. Later turns reuse it
        /// as history so attachments are not re-processed.
        let extractedPrompt: String?
        /// Attachment id -> the text that replaced that attachment's media in the prompt.
        let extractedText: [UUID: String]
    }

    /// Generates one image with an image model and returns its PNG data.
    static func generateImage(model: String, prompt: String) async throws -> Data {
        let response = try await AppleOpenAIClient.shared.images.generate(prompt: prompt, model: model, n: 1, responseFormat: "b64_json")
        guard let b64 = response.data.first?.b64Json, let data = Data(base64Encoded: b64) else {
            throw ChatAttachmentError.unreadable("generated image")
        }
        return data
    }

    static func run(
        model: String,
        history: [ChatMessage],
        text: String,
        attachments: [ChatAttachment]
    ) async throws -> Outcome {
        let client = AppleOpenAIClient.shared
        let canonical = CanonicalModel(rawValue: ModelRegistry.resolveCanonicalId(model))
        let mediaParts = attachments.flatMap(\.parts)

        // Direct models (OCR, PDF, translation, tagger) work on the current message only.
        if let canonical, !canonical.isLanguageModel {
            var parts: [ContentPart] = text.isEmpty ? [] : [.text(text)]
            parts += mediaParts
            let response = try await client.chat.completions.create(
                model: model,
                messages: [.init(role: "user", parts: parts)]
            )
            return Outcome(reply: response.choices.first?.message.content ?? "", extractedPrompt: nil, extractedText: [:])
        }

        // Omni: documents and audio (and images when the model cannot see them) are extracted to text once
        // and kept in the history. Extraction runs per attachment so each one can show what replaced it.
        let nativeImages = MultimodalPipeline.supportsNativeImages
        var userPrompt = text
        var extracted: String?
        var extractedText: [UUID: String] = [:]
        var imageParts: [ContentPart] = []
        if canonical == .omni, !attachments.isEmpty {
            var native: [ChatAttachment] = []
            for attachment in attachments {
                if attachment.kind.isVisual, nativeImages {
                    native.append(attachment)
                    imageParts += attachment.parts
                    continue
                }
                let probe = OpenAI.ChatCompletionRequest(model: model, messages: [.init(role: "user", parts: attachment.parts)])
                let processed = try await MultimodalPipeline.shared.process(request: probe)
                extractedText[attachment.id] = processed.messages.first?.content.rawText ?? ""
            }
            let texts = attachments.compactMap { extractedText[$0.id] }.filter { !$0.isEmpty }
            userPrompt = ([text] + texts).filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !native.isEmpty {
                userPrompt += (userPrompt.isEmpty ? "" : "\n") + "[attached images: \(native.map(\.name).joined(separator: ", "))]"
            }
            extracted = userPrompt
        }

        let prior = history.map { ($0.isUser ? "User: " : "Model: ") + ($0.promptText ?? $0.text) }
        let prompt = (prior + ["User: " + userPrompt]).joined(separator: "\n\n")

        // Raw models receive the attachments unprocessed (images natively on vlm, errors otherwise).
        let message: OpenAI.ChatCompletionRequest.Message
        if canonical == .omni {
            message = imageParts.isEmpty ? .init(role: "user", content: prompt) : .init(role: "user", parts: [.text(prompt)] + imageParts)
        } else if attachments.isEmpty {
            message = .init(role: "user", content: prompt)
        } else {
            message = .init(role: "user", parts: [.text(prompt)] + mediaParts)
        }
        let response = try await client.chat.completions.create(model: model, messages: [message])
        return Outcome(reply: response.choices.first?.message.content ?? "", extractedPrompt: extracted, extractedText: extractedText)
    }
}
