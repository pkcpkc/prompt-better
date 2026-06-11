# Prompt Better Usage Example

This example demonstrates how to use the `prompt-better` framework to evaluate and optimize prompts using a local **macOS Vapor bridge**. This setup is fully offline, targeting the macOS `LanguageModelSession` (Apple Silicon Foundation Models) for both prompt execution (Student) and instruction suggestions/grading (Teacher).

---

## Prerequisites

1. A Mac with Apple Silicon running **macOS 26+**.
2. **Xcode 26+** installed.
3. **Mise** installed (see [mise.jdx.dev](https://mise.jdx.dev)).

---

## 1. Setup the Python Environment

Set up Python tools and install the `prompt-better` package in editable mode:

```bash
# From the root of the prompt-better repository
mise trust
mise install
mise exec -- uv pip install -e .
```

---

## 2. Start the macOS Bridge Vapor Server

The macOS bridge acts as an OpenAI-compatible endpoint that wraps Apple's on-device Foundation Models.

Run the Vapor bridge:

```bash
cd AIBridges/macOS
swift build
swift run App serve --hostname 127.0.0.1 --port 8080
```

Keep this terminal running. The server will start listening at `http://127.0.0.1:8080`.

---

## 3. Configuration & Prompt Layout

For this example, the settings are defined in [example/prompt-better.json](file:///Users/pkc/Projects/prompt-better/example/prompt-better.json). It maps both the `student` and `teacher` models to our local bridge:

```json
{
  "student": {
    "base_url": "http://localhost:8080/v1",
    "model": "apple-intelligence"
  },
  "teacher": {
    "base_url": "http://localhost:8080/v1",
    "model": "apple-intelligence"
  },
  "auto_mode": "light",
  "num_threads": 4,
  "train_ratio": 0.4
}
```

The prompt definition is located in [prompt.json](example/prompts/TopicClassifier). It defines `TopicClassifierPrompt` to classify short texts into Politics, Sports, Technology, Science, or Entertainment.

### Securing API Keys via macOS Keychain / Passwords App

For security reasons, API keys **cannot** be stored in the `prompt-better.json` configuration file (doing so will trigger a validation error). 

To make running the example workflow convenient without exposing credentials or requiring manual environment exports, the `example/example.sh` script integrates with the macOS Keychain/Passwords system:

1. Add your API keys to your macOS Keychain (or via the macOS Passwords App).
2. Set the service name and account name in `example/example.sh`:
   ```bash
   STUDENT_KEYCHAIN_SERVICE="your-service-name"
   STUDENT_KEYCHAIN_ACCOUNT="your-account-name"
   ```
3. The script will automatically query the keychain securely at runtime using macOS `security` tools. If not found, it falls back to environment variables or dummy key values.

---

## 4. Run Baseline Validation

To see how the unoptimized prompt behaves against the on-device model, run the `validate` command. Note that the `--dataset` argument is completely **optional**; if omitted, the CLI automatically infers it as `<prompts-dir>/<PromptName>`:

From the repository root (running commands with `mise exec -- ` prefix, or with `mise` activated in your shell):

```bash
python3 -m prompt_better.cli validate \
  --prompts-dir example/prompts \
  --prompt TopicClassifierPrompt
```

This will run the baseline prompt for each test case, compare its output against the reference answers (golden truths) in `example/prompts/TopicClassifier/golden-truth/`, and output evaluation scores (structural matching and text similarity).

---

## 5. Optimize the Prompt (MIPROv2)

To compile the prompt and find a better-performing instruction candidate, run the `optimize` command.

You can bypass the estimated cost warning and confirmation prompt by passing `--no-requires-permission-to-run` (matching DSPy's parameter):

```bash
python3 -m prompt_better.cli optimize \
  --prompts-dir example/prompts \
  --prompt TopicClassifierPrompt \
  --no-requires-permission-to-run
```

During optimization:

1. The **Teacher model** (via our local bridge) proposes prompt rewrites.
2. The **Student model** executes the candidates on the training examples.
3. The evaluation metric scores the responses.
4. The best-performing instruction is written to `example/prompts/TopicClassifier/results/optimize-report.json`.

To automatically write the winning prompt back to `prompt.json`, run with the `--apply` flag:

```bash
python3 -m prompt_better.cli optimize \
  --prompts-dir example/prompts \
  --prompt TopicClassifierPrompt \
  --no-requires-permission-to-run \
  --apply
```
