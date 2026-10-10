# AIPromptCore & Apple AI Bridge API Reference

`AIPromptCore` is a zero-dependency, pure Swift framework providing an in-process, OpenAI-compatible client (`AppleOpenAIClient`) and backend engine that powers the macOS and iOS local Apple Intelligence Bridges.

---

## 1. In-Process Swift Client (`AppleOpenAIClient`)

The in-process client provides zero-HTTP-overhead access to on-device Apple Foundation Models and perception services.

```swift
import AIPromptCore

let client = AppleOpenAIClient.shared
```

### Chat Completions (`client.chat.completions`)

```swift
// Standard inference
let response = try await client.chat.completions.create(
    model: "omni", // or "default", "gpt-4o"
    messages: [
        .init(role: "user", content: "Summarize today's release notes.")
    ],
    temperature: 0.2,
    maxTokens: 500
)
print(response.choices.first?.message.content ?? "")
```

#### Raw AFM Direct Inference (Bypass Perception & RAG)
```swift
let rawResponse = try await client.chat.completions.create(
    model: "apple-foundation-model-3-core-3b", // Direct 3B AFM
    messages: [.init(role: "user", content: "Write a haiku about Swift.")]
)
```

#### Multimodal Chat (Audio, Image OCR, PDF)
```swift
let imageBase64 = imageData.base64EncodedString()
let multimodalMessage = OpenAI.ChatCompletionRequest.Message(
    role: "user",
    parts: [
        .text("Extract the total amount and line items from this receipt:"),
        .imageUrl(.init(url: "data:image/jpeg;base64,\(imageBase64)"))
    ]
)
let response = try await client.chat.completions.create(
    model: "omni",
    messages: [multimodalMessage]
)
```

#### Auto-RAG Retrieval
```swift
let ragResponse = try await client.chat.completions.create(
    model: "omni",
    messages: [.init(role: "user", content: "What were our Q3 earnings?")],
    rag: .init(enabled: true, mode: "hybrid", limit: 3)
)
```

---

### Local Indexing & Search (`client.index`)

Index content into Apple on-device vector and CoreSpotlight stores for offline retrieval.

```swift
// Index document
await client.index.add(
    id: "doc-101",
    title: "Quarterly Financials",
    content: "Q3 revenue was up 18% driven by software services.",
    metadata: ["quarter": "Q3", "year": "2025"]
)

// Search (Vector, Spotlight, or Hybrid)
let results = await client.index.search(
    query: "software revenue growth",
    limit: 5,
    mode: .hybrid(k: 60.0) // default Reciprocal Rank Fusion
)

for item in results {
    print("Found: \(item.title) (Score: \(item.score))")
}
```

---

### In-Process Embeddings (`client.embeddings`)

Generate dense float vectors using Apple's `NaturalLanguage` and `Vision` frameworks.

```swift
// Sentence Embedding (512 dimensions)
let sentenceVec = try await client.embeddings.create(
    input: "Apple Intelligence running fully private on-device.",
    model: "apple-sentence-embedding" // or alias "text-embedding-3-small"
)
let vector: [Float] = sentenceVec.data[0].embedding

// Word Embedding (300 dimensions)
let wordVec = try await client.embeddings.create(
    input: "concurrency",
    model: "apple-word-embedding"
)

// Vision FeaturePrint (Visual Embedding)
let visualVec = try await client.embeddings.create(
    input: "data:image/png;base64,...",
    model: "apple-vision-featureprint"
)
```

---

### In-Process Audio (`client.audio`)

#### Text-to-Speech (TTS)
```swift
let wavData = try await client.audio.speech.create(
    input: "Your order is ready for pickup.",
    voice: "alloy", // or "echo", "nova", "siri-neutral"
    model: "apple-speech-synthesize" // or alias "tts-1"
)
// wavData contains 16-bit Linear PCM RIFF/WAVE audio
```

#### Speech-to-Text (STT)
```swift
let transcription = try await client.audio.transcriptions.create(
    file: wavData,
    model: "apple-speech-transcribe", // or alias "whisper-1"
    language: "en-US"
)
print("Recognized: \(transcription.text)")
```

---

### In-Process Image Generation (`client.images`)

Generate images on-device with Apple Image Playground.

#### Apple Image Playground (`apple-image-playground`)
Presents the system Image Playground sheet (`ImagePlaygroundViewController`) over the frontmost window, pre-filled with the prompt, and returns the image the user picks. It needs a foreground window and a person to choose; with no window, or if the user cancels, it throws `ImageGenerationError` (the HTTP routes answer `503`).

```swift
let response = try await client.images.generate(
    prompt: "Playful cartoon red panda wearing headphones",
    model: "apple-image-playground",
    style: "animation",
    responseFormat: "b64_json"
)
```

Convenience SDK shorthand:
```swift
let response = try await client.images.generatePlayground(
    prompt: "Astronaut floating near Saturn rings",
    style: "animation"
)
```

---

## 2. HTTP Compatibility Endpoints

The macOS bridge (`AIBridges/macOS`) and iOS bridge (`AIBridges/iOS`) expose standard OpenAI HTTP routes:

| HTTP Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/v1/chat/completions` | Standard chat completion with streaming, multi-turn, multimodal, and Auto-RAG |
| `POST` | `/v1/embeddings` | Dense vector embedding extraction (`apple-sentence-embedding`, `apple-vision-featureprint`) |
| `POST` | `/v1/audio/transcriptions` | Speech-to-text recognition from WAV audio (`multipart/form-data` or JSON) |
| `POST` | `/v1/audio/speech` | Text-to-speech synthesis returning WAV audio stream |
| `POST` | `/v1/images/generations` | Image generation using `apple-image-playground` (system sheet; the user picks the image) |
| `POST` | `/v1/index/documents` | Add document to local CoreSpotlight and Vector stores |
| `POST` | `/v1/search` | Query local stores with `.vector`, `.spotlight`, or `.hybrid` fusion |
| `GET` | `/v1/models` | List all available canonical models and active custom/OpenAI aliases |
| `GET` | `/health` | Server heartbeat and port check |
