# Apple Bridges & AIPromptCore Setup

> Part of the [prompt-better docs](../README.md). Model catalog: [APPLE_MODELS.md](APPLE_MODELS.md).

`prompt-better` reaches Apple's on-device models in two ways:

- **Vapor bridges** (`AIBridges/`) expose them as an OpenAI-compatible REST API. This is how the Python optimizer talks to the student model.
- **`AIPromptCore`** (`frameworks/AIPromptCore`) is the Swift framework the bridges are built on. Use it directly in your own app for in-process access and typed `@Generable` prompts.

## Bridges

| Bridge | Platform | Mode | Best for |
| :--- | :--- | :--- | :--- |
| [macOS Bridge](../AIBridges/macOS) | macOS 26.0+ | Headless CLI service | Scripts, CI, Apple Silicon Macs |
| [iOS Bridge](../AIBridges/iOS) | iOS 26.0+ | SwiftUI dashboard app | Physical devices and simulators |

```bash
# macOS
cd AIBridges/macOS
swift build && swift run App serve --hostname 127.0.0.1 --port 8080
```

For the iOS app, run `xcodegen generate` in `AIBridges/iOS`, open `iosAIBridge.xcodeproj`, run it on an iOS 26+ target, and tap **Start**. Use the IP shown on the dashboard as `base_url` when the Mac and device share a network.

### Chat window attachments

The bridge app's chat window (iOS app and `macAIBridge`) shows only the inputs the selected model accepts (its `input_modalities`, see [model types](APPLE_MODELS.md#model-types)): text-only `llm` models show just the text field, `vlm` models (the default model on the advanced tier) add photo/video and image-file attachments, `omni` shows text, photos and files, `apple-vision-ocr` shows only the photo/file buttons for images, and `apple-pdf-extractor` accepts only PDFs. The model picker prefixes each entry with its type, for example `[llm]`. Attachments:

- **Photos & videos**: the picture button opens the system photo picker (up to 5 items).
- **Files**: the paperclip button opens a file dialog. PDFs, images, audio, movies, and any UTF-8 text file (txt, md, json, source code) are accepted.

Chat goes through `AppleOpenAIClient`, the same path as `POST /v1/chat/completions`, so attachments behave exactly as they do over HTTP:

- **Raw language models** (`default`, the `apple-foundation-model*` aliases, Private Cloud Compute): `vlm` models take images natively (a video contributes 4 sampled frames); everything else they cannot process returns an error naming `omni`, instead of being silently dropped.
- **`omni`** runs the perception pipeline first: images go to the language model as images on the advanced tier (OCR otherwise), PDFs are text-extracted, audio is transcribed (speech build only). Extracted document and audio text is kept in the conversation, so later turns reuse it instead of re-processing; images are named in the history but only seen on the turn they are attached. A video contributes 4 frames sampled evenly across it (seen as images or OCR'd, as above); its audio track is not transcribed.
- **Direct models** such as `apple-vision-ocr` or `apple-pdf-extractor` receive the raw attachment.

Endpoint payloads, setup steps and device-testing notes are in the [AIBridges README](../AIBridges/README.md).

## AIPromptCore

> [!NOTE]
> Using `AIPromptCore` guarantees the same call structure and parsing to the Apple model as used during optimization. It is not required; you can take the optimized instruction text from the results JSON and run it in any LLM setup.

1. Add the package, or build the XCFramework (speech is excluded by default; add `--with-speech` for STT):
   ```swift
   .package(path: "path/to/prompt-better/frameworks/AIPromptCore")
   ```
   ```bash
   cd frameworks/AIPromptCore && ./build_xcframework.sh
   ```
2. Generate `@Generable` Swift structs from an optimized prompt:
   ```bash
   python3 -m prompt_better.cli generate \
     --source example/prompts/TopicClassifier/results/optimized-prompt.json \
     --target example/prompts/TopicClassifier/results/TopicClassifierPrompt.swift \
     --language swift
   ```
3. Call models in-process with `AppleOpenAIClient.shared` (see [APPLE_MODELS.md](APPLE_MODELS.md#2-using-the-swift-sdk)).

Further guides:

- [API reference](../frameworks/AIPromptCore/docs/API_REFERENCE.md)
- [Framework integration](../frameworks/AIPromptCore/docs/FRAMEWORK_INTEGRATION.md)
- [Generable prompts](../frameworks/AIPromptCore/docs/GENERABLE_PROMPTS_GUIDE.md)
- [Local RAG](../frameworks/AIPromptCore/docs/LOCAL_RAG_GUIDE.md)
