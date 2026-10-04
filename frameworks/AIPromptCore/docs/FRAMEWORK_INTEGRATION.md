# Framework Integration Guide for iOS & macOS Apps

This guide explains how to integrate `AIPromptCore` into your own iOS and macOS applications, either via Swift Package Manager or as a standalone universal `XCFramework`.

---

## 1. Integration Methods

### Option A: Swift Package Manager (Recommended)
Add `AIPromptCore` to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../prompt-better/frameworks/AIPromptCore")
]
```

Or in Xcode:
1. Select **File > Add Package Dependencies...**
2. Add the repository URL or local package path.
3. Link `AIPromptCore` to your application target.

---

### Option B: Universal XCFramework (`AIPromptCore.xcframework`)
To build the distributable, closed-source or binary framework for iOS Device, iOS Simulator, and macOS:

```bash
cd frameworks/AIPromptCore
./build_xcframework.sh
```

The resulting `build/AIPromptCore.xcframework` contains:
- `ios-arm64` (iOS physical devices)
- `ios-arm64_x86_64-simulator` (iOS Simulators)
- `macos-arm64` (macOS Apple Silicon)

Drag `AIPromptCore.xcframework` into your Xcode project's **Frameworks, Libraries, and Embedded Content** and set to **Embed & Sign**.

---

## 2. Privacy & Entitlements (`Info.plist`)

If your app uses speech recognition or microphone features via `client.audio`:

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>This app uses on-device speech recognition to transcribe your voice notes privately.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to record audio for transcription.</string>
```

---

## 3. Embedding the Settings View

Embed the shared multiplatform `SettingsView` in your app to let users manage aliases and local RAG indexes:

### In SwiftUI for iOS
```swift
import SwiftUI
import AIPromptCore

struct AppRootView: View {
    @State private var showSettings = false

    var body: some View {
        Button("Settings") {
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
    }
}
```

### In SwiftUI for macOS (Preferences Menu)
```swift
import SwiftUI
import AIPromptCore

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .frame(minWidth: 500, minHeight: 450)
        }
        #endif
    }
}
```

---

## 4. Custom Model Aliases & Flag Configuration

You can configure model aliases programmatically or via environment variables:

```swift
// Enable standard OpenAI aliases (e.g. whisper-1, gpt-4o, text-embedding-3-small)
AliasConfiguration.shared.enableOpenAIAliases = true

// Add custom alias for an internal tool or agent
AliasConfiguration.shared.setAlias(alias: "summarizer-agent", target: "apple-foundation-omni")
```

Or via environment variables:
```bash
export ENABLE_OPENAI_ALIASES=true
export MODEL_ALIASES='{"research-bot": "apple-foundation-omni"}'
```
