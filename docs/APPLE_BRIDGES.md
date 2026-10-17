# Apple Bridges

> Part of the [prompt-better docs](../README.md).

The Vapor bridges in [`AIBridges/`](../AIBridges) serve Apple's on-device language model as an OpenAI-compatible endpoint, so the Python optimizer can use it as the student. They implement only what optimization needs: `POST /v1/chat/completions` (text), `GET /v1/models` and `GET /health`.

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

For the iOS app, run `xcodegen generate` in `AIBridges/iOS`, open `iosAIBridge.xcodeproj` and run it on an iOS 26+ target. The server starts on launch. Use the address shown on the dashboard as `base_url` when the Mac and device share a network.

## Model IDs

| Model ID | What it runs |
| :--- | :--- |
| `default` | `SystemLanguageModel.default`, the system's current on-device model |
| `apple-foundation-model-3-core-3b` | Alias for `default` |
| `apple-foundation-model` | Alias for `default` |
| `apple-intelligence-private-cloud-compute` | Private Cloud Compute ID; currently served by the on-device model |

An `openai/` prefix (as sent by LiteLLM) is accepted.

## How requests are run

- A fresh `LanguageModelSession` per request, one request at a time.
- `system` messages become the session instructions (joined with blank lines); all other messages are joined with blank lines into the prompt.
- `temperature: 0` selects greedy decoding; otherwise `top_p` selects nucleus sampling. `max_tokens` sets `maximumResponseTokens`.
- Non-text content parts are rejected with `400 unsupported_operation`. Errors use the OpenAI error envelope (`model_not_found`, `context_length_exceeded`, `content_policy_violation`, ...).

## Using the optimized prompt in Swift

Generate `@Generable` Swift structs from an optimized prompt:

```bash
python3 -m prompt_better.cli generate \
  --source example/prompts/TopicClassifier/results/optimized-prompt.json \
  --target example/prompts/TopicClassifier/results/TopicClassifierPrompt.swift \
  --language swift
```

The generated type conforms to `GenerableWithPrompt` from [`AIPromptCore`](../frameworks/AIPromptCore), a small framework (`GenerableWithPrompt`, `AISessionController`, `AIPrompt`) that runs generated prompts on the on-device model. Add it as a package or build the XCFramework:

```swift
.package(path: "path/to/prompt-better/frameworks/AIPromptCore")
```

```bash
cd frameworks/AIPromptCore && ./build_xcframework.sh
```

Using `AIPromptCore` is not required; you can take the optimized instruction text from the results JSON and run it in any LLM setup.
