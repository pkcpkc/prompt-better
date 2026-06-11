# Gradle Integration for prompt-better

This folder provides a generic Gradle script plugin helper to easily integrate `prompt-better` tasks (list, validate, optimize, and Swift generation) directly into your Kotlin, Android, or iOS Gradle build pipelines.

## Setup

1. **Copy the script**: Place `prompt-better.gradle.kts` in your project's Gradle configuration directory (e.g., `<your-project-root>/gradle/prompt-better.gradle.kts`).
2. **Apply the plugin**: Apply it in your target module's `build.gradle.kts` file:

```kotlin
apply(from = "gradle/prompt-better.gradle.kts")
```

3. **Configure the Extension**: Customize paths and properties inside the `promptBetter` block:

```kotlin
configure<PromptBetterExtension> {
    // Command setup (if using mise or virtual environment)
    commandPrefix.set(listOf("mise", "exec", "--"))
    pythonCommand.set("python3")
    
    // Directory paths
    promptsDir.set("prompts")
    datasetDir.set("data")
    
    // Default prompt target
    promptName.set("ALL")
    
    // Swift code generation output path
    swiftOutputDir.set("src/main/swift/Generated")
}
```

## Available Tasks

Once applied, the script registers the following tasks under the `prompt-better` group:

*   **`promptBetterList`**: Lists all prompts defined in your prompt directory.
*   **`promptBetterPreviewSchema`**: Prints the JSON schema format for the selected prompt.
*   **`promptBetterValidate`**: Runs baseline prompt validation against the configured Student endpoint.
*   **`promptBetterOptimize`**: Compiles and optimizes instructions using your Student and Teacher LLM setup.
*   **`promptBetterGenerateSwift`**: Scans the prompts directory for `prompt.json` files and generates Swift `@Generable` structs.

## CLI Properties Override

You can override configuration values dynamically on the command-line using `-P` flags. These CLI arguments take precedence over extension configurations:

```bash
# Validate a specific prompt
./gradlew promptBetterValidate -PpromptBetterPrompt=TopicClassifierPrompt

# Run optimization on a specific prompt and apply the optimized instructions
./gradlew promptBetterOptimize -PpromptBetterPrompt=TopicClassifierPrompt -PpromptBetterApply=true

# Override endpoint API keys in a CI/CD runner
./gradlew promptBetterOptimize \
  -PpromptBetterTeacherApiKey="sk-proj-..." \
  -PpromptBetterStudentBaseUrl="http://127.0.0.1:8080/v1"
```

### Supported CLI Properties:

*   `promptBetterPython` (e.g., `python3`)
*   `promptBetterPromptsDir` (e.g., `prompts/`)
*   `promptBetterDataset` (e.g., `data/`)
*   `promptBetterPrompt` (e.g., `TopicClassifierPrompt`)
*   `promptBetterAutoMode` (`light`, `medium`, `heavy`)
*   `promptBetterNumThreads` (number of threads)
*   `promptBetterTrainRatio` (e.g., `0.8`)
*   `promptBetterApply` (`true`/`false`)
*   `promptBetterStudentBaseUrl`
*   `promptBetterStudentModel`
*   `promptBetterStudentApiKey`
*   `promptBetterTeacherBaseUrl`
*   `promptBetterTeacherModel`
*   `promptBetterTeacherApiKey`
