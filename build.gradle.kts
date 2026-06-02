import java.io.File
import javax.inject.Inject
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations

plugins {
    base
}

fun resolveRepoPath(pathStr: String): File {
    val f = project.file(pathStr)
    if (f.exists()) return f
    val parentFile = project.file("../$pathStr")
    if (parentFile.exists()) return parentFile
    return f
}

// Prompt optimization workspace properties
val promptOptimizationPython = providers.gradleProperty("promptOptimizationPython")
    .getOrElse("python3")
val promptOptimizationPrompt = providers.gradleProperty("promptOptimizationPrompt")
    .getOrElse("ALL")
val promptOptimizationDataset = providers.gradleProperty("promptOptimizationDataset")
    .getOrElse("data")
val promptOptimizationPromptsDir = providers.gradleProperty("promptOptimizationPromptsDir")
    .getOrElse("../prompts/ios/prompts")
val promptOptimizationAutoMode = providers.gradleProperty("promptOptimizationAutoMode")
    .getOrElse("light")
val promptOptimizationNumThreads = providers.gradleProperty("promptOptimizationNumThreads")
    .getOrElse("6")
val promptOptimizationTrainRatio = providers.gradleProperty("promptOptimizationTrainRatio")
    .getOrElse("0.8")
val promptOptimizationSwiftOutputDir = providers.gradleProperty("promptOptimizationSwiftOutputDir")
    .getOrElse("../iosApp/iosApp/AI/Generated")
val promptOptimizationLanguage = providers.gradleProperty("promptOptimizationLanguage")
    .getOrElse("swift")
val promptOptimizationTemplate = providers.gradleProperty("promptOptimizationTemplate")
    .getOrElse("")
val promptOptimizationApply = providers.gradleProperty("promptOptimizationApply")
    .getOrElse("false")

// Runtime endpoints (pass via -P or environment)
val promptOptimizationStudentBaseUrl = providers.gradleProperty("promptOptimizationStudentBaseUrl").getOrElse("")
val promptOptimizationStudentModel = providers.gradleProperty("promptOptimizationStudentModel").getOrElse("")
val promptOptimizationStudentApiKey = providers.gradleProperty("promptOptimizationStudentApiKey").getOrElse("")
val promptOptimizationTeacherBaseUrl = providers.gradleProperty("promptOptimizationTeacherBaseUrl").getOrElse("")
val promptOptimizationTeacherModel = providers.gradleProperty("promptOptimizationTeacherModel").getOrElse("")
val promptOptimizationTeacherApiKey = providers.gradleProperty("promptOptimizationTeacherApiKey").getOrElse("")

fun Exec.configurePromptOptimizationRuntime(
    command: String,
    includeRuntimeEndpoints: Boolean,
) {
    group = "ai"
    workingDir = projectDir

    doFirst {
        val argsList = mutableListOf(
            promptOptimizationPython,
            "-m", "prompt_better.cli",
            command,
            "--prompts-dir", resolveRepoPath(promptOptimizationPromptsDir).absolutePath,
            "--dataset", resolveRepoPath(promptOptimizationDataset).absolutePath,
            "--prompt", promptOptimizationPrompt,
            "--auto", promptOptimizationAutoMode,
            "--num-threads", promptOptimizationNumThreads,
            "--train-ratio", promptOptimizationTrainRatio
        )
        if (promptOptimizationApply.toBoolean()) {
            argsList.add("--apply")
        }
        commandLine(argsList)

        if (includeRuntimeEndpoints) {
            environment("PROMPT_BETTER_STUDENT_BASE_URL", promptOptimizationStudentBaseUrl)
            environment("PROMPT_BETTER_STUDENT_MODEL", promptOptimizationStudentModel)
            environment("PROMPT_BETTER_STUDENT_API_KEY", promptOptimizationStudentApiKey)
            environment("PROMPT_BETTER_TEACHER_BASE_URL", promptOptimizationTeacherBaseUrl)
            environment("PROMPT_BETTER_TEACHER_MODEL", promptOptimizationTeacherModel)
            environment("PROMPT_BETTER_TEACHER_API_KEY", promptOptimizationTeacherApiKey)
        }
    }
}

tasks.register<Exec>("install") {
    group = "ai"
    description = "Installs the promptOptimization Python package and its dependencies in editable mode."
    workingDir = projectDir
    commandLine(promptOptimizationPython, "-m", "pip", "install", "-e", ".")
}

tasks.register<Exec>("list") {
    group = "ai"
    description = "Lists prompts defined in JSON files."
    workingDir = projectDir
    doFirst {
        commandLine(
            promptOptimizationPython,
            "-m", "prompt_better.cli",
            "list-prompts",
            "--prompts-dir", resolveRepoPath(promptOptimizationPromptsDir).absolutePath
        )
    }
}

tasks.register<Exec>("previewSchema") {
    group = "ai"
    description = "Prints the JSON schema for the selected prompt."
    workingDir = projectDir
    doFirst {
        commandLine(
            promptOptimizationPython,
            "-m", "prompt_better.cli",
            "preview-schema",
            "--prompts-dir", resolveRepoPath(promptOptimizationPromptsDir).absolutePath,
            "--prompt", promptOptimizationPrompt
        )
    }
}

tasks.register<Exec>("test") {
    group = "verification"
    description = "Runs dependency-light promptOptimization unit tests."
    workingDir = projectDir
    commandLine(promptOptimizationPython, "-m", "unittest", "discover", "tests")
}

tasks.register<Exec>("validate") {
    description = "Runs baseline prompt validation against the configured student endpoint using JSON schema."
    configurePromptOptimizationRuntime(command = "validate", includeRuntimeEndpoints = true)
}

tasks.register<Exec>("optimize") {
    description = "Runs DSPy optimization for the selected prompt(s) and writes reports to results."
    configurePromptOptimizationRuntime(command = "optimize", includeRuntimeEndpoints = true)
}

abstract class GenerateSwiftPromptsTask @Inject constructor(
    private val execOperations: ExecOperations
) : DefaultTask() {
    @get:Input
    abstract val promptsDir: Property<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Input
    abstract val pythonCommand: Property<String>

    @get:Input
    abstract val language: Property<String>

    @get:Input
    abstract val templateFile: Property<String>

    @TaskAction
    fun generate() {
        val rawPromptsDir = promptsDir.get()
        val dir = if (project.file(rawPromptsDir).exists()) {
            project.file(rawPromptsDir)
        } else {
            project.file("../$rawPromptsDir")
        }
        val outDir = outputDir.get().asFile
        val pythonCmd = pythonCommand.get()
        val templateArg = templateFile.get()
        
        if (outDir.exists()) {
            outDir.deleteRecursively()
        }
        outDir.mkdirs()
        
        dir.walk().filter { it.name == "prompt.json" }.forEach { file ->
            val json = groovy.json.JsonSlurper().parseText(file.readText()) as Map<*, *>
            val name = json["name"] as String
            val outputFile = outDir.resolve("$name.swift")

            execOperations.exec {
                workingDir = project.projectDir
                val args = mutableListOf(
                    pythonCmd,
                    "-m", "prompt_better.cli",
                    "generate",
                    "--source", file.absolutePath,
                    "--target", outputFile.absolutePath
                )
                if (templateArg.isNotBlank()) {
                    args.addAll(listOf("-template", project.file(templateArg).absolutePath))
                } else {
                    args.addAll(listOf("-language", language.get()))
                }
                commandLine(args)
            }
        }
    }
}

tasks.register<GenerateSwiftPromptsTask>("generateSwiftPrompts") {
    group = "ai"
    description = "Generates Swift GenerableWithPrompt structs from JSON definitions."
    promptsDir.set(promptOptimizationPromptsDir)
    outputDir.set(project.layout.projectDirectory.dir(promptOptimizationSwiftOutputDir))
    pythonCommand.set(promptOptimizationPython)
    language.set(promptOptimizationLanguage)
    templateFile.set(promptOptimizationTemplate)
}
