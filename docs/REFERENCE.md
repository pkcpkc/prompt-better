# CLI, Configuration & Presets Reference

> Part of the [prompt-better docs](../README.md).

## CLI Subcommands

| Command                 | Description                                                           | Key Arguments                                                                                                                                                |
| :---------------------- | :-------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `list-prompts`          | Scans for prompt specifications inside the target directory.          | `--prompts-dir`                                                                                                                                              |
| `preview-schema`        | Emits the parsed Pydantic schema structure derived from the spec.     | `--prompts-dir`, `--prompt`                                                                                                                                  |
| `evaluate-spec`         | Runs validator checks on prompt JSONs against `prompt-schema.json`.   | `--prompts-dir`                                                                                                                                              |
| `evaluate`              | Runs evaluation cases against the Student model.                      | `--prompts-dir`, `--prompt`, `--dataset`, `--student-temperature`, `--teacher-eval-temperature`                                                              |
| `optimize`              | Compiles and optimizes instructions via DSPy MIPROv2.                 | `--prompts-dir`, `--prompt`, `--dataset`, `--student-temperature`, `--teacher-temperature`, `--teacher-eval-temperature`, `--eval-cases-only`, `--optimizer` |
| `generate-golden-truth` | Generates placeholder schemas inside the target `golden-truth/` path. | `--prompts-dir`, `--dataset-dir`, `--prompt`, `--case-id`, `--teacher-temperature`                                                                           |
| `generate`              | Compiles Swift class structs conformant to `AIPromptCore`.            | `--source`, `--target`, `--language swift`                                                                                                                   |

## Environment Variables

- `PROMPT_BETTER_STUDENT_BASE_URL`: API root for student completions (e.g. Vapor server: `http://localhost:8080/v1`).
- `PROMPT_BETTER_STUDENT_MODEL`: Model ID identifier (e.g. `apple-foundation-model-3-core-3b` or `apple-intelligence-private-cloud-compute`).
- `PROMPT_BETTER_STUDENT_API_KEY`: Key used for authentication (optional/blank for localhost).
- `PROMPT_BETTER_STUDENT_TEMPERATURE`: Default temperature for student model completion calls (defaults to `0.2`).
- `PROMPT_BETTER_TEACHER_BASE_URL`: API root for the cloud teacher model (e.g. `https://api.openai.com/v1`).
- `PROMPT_BETTER_TEACHER_MODEL`: Teacher model ID (e.g. `gpt-4o`).
- `PROMPT_BETTER_TEACHER_API_KEY`: API token authorization key.
- `PROMPT_BETTER_TEACHER_TEMPERATURE`: General/MIPRO temperature for the teacher model when proposing prompt variations and creating samples (defaults to `0.2`).
- `PROMPT_BETTER_TEACHER_EVAL_TEMPERATURE`: Evaluation/eval temperature for the teacher model when grading/evaluating candidate outputs (defaults to `0.0` as recommended).
- `PROMPT_BETTER_OPTIMIZER`: Optimizer mode or custom class path: `"predict"` (best suited for iOS/schema-guided structured output), `"chain-of-thought"` / `"miprov2"` (default), `"gepa"` (DSPy v3 reflective optimization), or custom class/file path.

## Scenario-Specific CLI Presets

### On-Device & Local Silicon Testing

Run evaluations sequentially to avoid core contention, disable token budget validations, and disable Chain-of-Thought formatting constraints for schema-guided output targets:

```bash
python3 -m prompt_better.cli optimize \
  --prompts-dir ./prompts \
  --prompt MyPrompt \
  --num-threads 1 \
  --no-requires-permission-to-run \
  --optimizer predict
```

### Multi-threaded Cloud Pipelines

Speed up calls over remote APIs by increasing parallel compilation threads:

```bash
python3 -m prompt_better.cli optimize \
  --prompts-dir ./prompts \
  --prompt MyPrompt \
  --num-threads 8 \
  --auto medium
```

## Gradle Pipeline

For developers using Gradle (e.g., Android, iOS, or Kotlin Multiplatform projects), a generic, reusable Gradle script plugin helper is available in [contrib/gradle/](../contrib/gradle/):

- Refer to the [contrib/gradle/README.md](../contrib/gradle/README.md) for setup and integration instructions.
- Once integrated, tasks like `promptBetterList`, `promptBetterEvaluate`, `promptBetterOptimize`, and `promptBetterGenerateSwift` will be available in your project's Gradle build pipeline.

## Books & Literature

- **AI Engineering - Building Application with Foundation Models** by _Chip Huyen_ (O'Reilly)
  - Chapter 4. Evaluate AI Systems
  - Chapter 5. Prompt Engineering
  - Chapter 8. Dataset Engineering
