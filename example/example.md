# Prompt Better Usage Example: macOS & iOS On-Device Optimization

This example demonstrates how to use the `prompt-better` framework to evaluate, optimize, and export prompts for Apple's local **LanguageModelSession** API (iOS 26+ and macOS 26+). 

The framework bridges Python-based prompt optimization (built on DSPy) with Apple's Swift runtimes via Vapor-based HTTP bridges, allowing you to optimize prompts directly on target Apple hardware (both Mac and physical iOS devices).

---

## 1. Quick Start: The Automated Script

The most convenient way to run the entire flow is using the pre-configured automation script `example/example.sh`. This script will:
1. Verify if the local macOS Vapor bridge is running (and automatically build and launch it in the background if it is not).
2. Load credentials securely from the macOS Keychain.
3. Run Step 1: Baseline validation (`validate` command).
4. Run Step 2: DSPy optimization (`optimize` command).
5. Run Step 3: Export the optimized prompt to Swift (`generate` command).
6. Automatically stop the macOS bridge after completing execution.

To run it:
```bash
# Make sure you are at the repository root
chmod +x example/example.sh
./example/example.sh
```

---

## 2. Prerequisites & Environment Setup

### Prerequisites
1. An Apple Silicon Mac running **macOS 26+**.
2. **Xcode 26+** installed.
3. **Mise** installed (see [mise.jdx.dev](https://mise.jdx.dev)) to manage python runtimes and environments.

### Setup Python
Install `prompt-better` locally in editable mode:
```bash
mise trust
mise install
mise exec -- uv pip install -e .
```

---

## 3. Starting the AI Bridge Server

To communicate with local Apple foundation models (Apple Intelligence), you must run one of the provided Vapor bridges. The bridge acts as a local `/v1/chat/completions` server wrapping the Swift-only `LanguageModelSession` API.

### Option A: macOS Bridge (Headless Command-Line Service)
Best for running optimization loops entirely on your Mac.
```bash
cd AIBridges/macOS
swift build -c release
swift run App serve --hostname 127.0.0.1 --port 8080
```
*Keep this terminal running. The server starts at `http://127.0.0.1:8080`.*

### Option B: iOS Bridge (SwiftUI Dashboard App)
Best for validating prompts directly on a physical iOS device or simulator to ensure compatibility with iOS hardware.

1. **Generate the Xcode Project** (using `xcodegen`):
   ```bash
   cd AIBridges/iOS
   xcodegen generate
   ```
2. **Deploy to Simulator or Physical Device**:
   - Open `iosAIBridge.xcodeproj` in Xcode.
   - Run the scheme `iosAIBridge` on a connected physical iOS 26+ device or Simulator.
3. **Run the Server**:
   - Launch the app and tap **Start** on the SwiftUI dashboard.
   - Note the **Local Address** displayed (e.g. `http://192.168.1.45:8080/v1`).
   - Ensure your Mac and iOS device are connected to the same Wi-Fi network.

---

## 4. Configuration & API Credentials

Settings are defined in [example/prompt-better.json](prompt-better.json). It targets our local student model while referencing a cloud-based teacher model (e.g., GPT-4o) for proposing instructions and grading results:

```json
{
  "student": {
    "base_url": "http://localhost:8080/v1",
    "model": "apple-intelligence"
  },
  "teacher": {
    "base_url": "https://api.openai.com/v1",
    "model": "gpt-4o"
  },
  "auto_mode": "medium",
  "num_threads": 4,
  "train_ratio": 0.8,
  "optimizer": "predict"
}
```

> [!NOTE]
> For physical iOS testing, update `student.base_url` to the IP address displayed on your iOS device screen (e.g., `http://192.168.1.45:8080/v1`).

### Securing API Keys via macOS Keychain
To prevent credentials from leaking, API keys **cannot** be stored in `prompt-better.json`.

You can set them using environment variables:
```bash
export PROMPT_BETTER_TEACHER_API_KEY="sk-proj-..."
```

Alternatively, the `example/example.sh` script supports loading credentials from the macOS Keychain. Store your API keys in the Keychain with:
- Service Name: `prompt-better`
- Account: `API Key`
The script will query the keychain securely at runtime using macOS `security` tools.

---

## 5. Execution & Optimization Workflow

### Run Baseline Validation
Measure the performance of your baseline instructions before optimization:
```bash
python3 -m prompt_better.cli validate \
  --prompts-dir example/prompts \
  --prompt TopicClassifierPrompt
```
This runs the test cases located in `example/prompts/TopicClassifier/dataset/` and evaluates the student responses against the golden truth references in `golden-truth/`.

### Run Prompt Optimization
Optimize the prompt instructions using DSPy's `MIPROv2` compiler:
```bash
python3 -m prompt_better.cli optimize \
  --prompts-dir example/prompts \
  --prompt TopicClassifierPrompt \
  --no-requires-permission-to-run \
  --apply
```
- During compilation, the Teacher model proposes instruction changes, the Student executes them, and the framework records the best performing prompts.
- The `--apply` flag automatically overwrites `example/prompts/TopicClassifier/prompt.json` with the winning instructions.

---

## 6. On-Device & iOS Specific Recommendations

Apple's local `LanguageModelSession` utilizes native schema-guided structured outputs, returning strict JSON objects. When developing and compiling prompts for this environment, keep the following in mind:

> [!IMPORTANT]
> **Optimizing with `--optimizer predict` (Option 1 - Recommended)**
> By default, `prompt-better` uses DSPy `ChainOfThought` compilation (`"optimizer": "chain-of-thought"`). Because CoT generates formatting instructions requesting intermediate reasoning text prefixes (e.g. `Reasoning:` and `Output:`), it conflicts with Apple's native structured JSON schema constraints, leading to parsing or validation errors on-device. 
> 
> Set your optimizer configuration to `predict` in `prompt-better.json` (or use `--optimizer predict` CLI flag) to compile prompts cleanly using `dspy.Predict`.

> [!TIP]
> **Schema-Guided Chain of Thought (Option 2)**
> If the target on-device model requires step-by-step reasoning to get the correct answer, explicitly add a `reasoning` field inside the `outputs` array of your `prompt.json`:
> ```json
> "outputs": [
>   {
>     "name": "reasoning",
>     "type": "string",
>     "desc": "Step-by-step logic explaining the category classification."
>   },
>   {
>     "name": "topic",
>     "type": "string",
>     "desc": "The final classified topic category."
>   }
> ]
> ```
> This allows the model to output reasoning steps directly within the schema-guided output, satisfying Apple's JSON parsing constraints.

---

## 7. Generating Swift & Integrating with iOS/macOS Apps

### Step 1: Export Swift Struct
Generate a type-safe Swift struct conforming to Apple's native schema format:
```bash
python3 -m prompt_better.cli generate \
  --source example/prompts/TopicClassifier/results/optimized-prompt.json \
  --target example/prompts/TopicClassifier/results/TopicClassifierPrompt.swift \
  --language swift
```
This produces `TopicClassifierPrompt.swift` containing your optimized instructions and target fields. It conforms to `GenerableWithPrompt` (built on top of Apple's `@Generable` macro):
```swift
import Foundation
import FoundationModels
import AIPromptCore

@Generable
struct TopicClassifierPrompt: GenerableWithPrompt {
    static let promptName = "TopicClassifierPrompt"

    @Guide(description: "The main topic of the text.")
    var topic: String

    static let systemPrompt = "..." // Your optimized instructions
}
```

### Step 2: Integrate `AIPromptCore`
Using the `AIPromptCore` framework is recommended to execute the prompts using exactly the same parameters and session wrappers used during optimization.

1. **Build the Binary Framework**:
   ```bash
   cd frameworks/AIPromptCore
   ./build_xcframework.sh
   ```
2. **Add Dependency**:
   Link the resulting binary or include the local package in your project's `Package.swift`:
   ```swift
   .package(path: "path/to/prompt-better/frameworks/AIPromptCore")
   ```
3. **Execute On-Device Prompt**:
   Use `AISessionController` to trigger prompt execution within your SwiftUI/Swift code:
   ```swift
   import AIPromptCore
   
   let input = "Mars rover successfully collects rock sample."
   
   do {
       let result = try await AISessionController.shared.respond(
           to: input,
           generating: TopicClassifierPrompt.self,
           createNewSession: true
       )
       print("Optimized Category: \(result.topic)")
   } catch {
       print("Failed to run on-device prompt: \(error)")
   }
   ```
