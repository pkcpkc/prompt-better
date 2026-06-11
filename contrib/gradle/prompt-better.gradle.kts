import java.io.File
import javax.inject.Inject
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.ListProperty
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations

/**
 * Extension configuration for the prompt-better integration.
 * Apply this script plugin to your project and configure via:
 *
 * ```kotlin
 * configure<PromptBetterExtension> {
 *     promptsDir.set("prompts")
 *     datasetDir.set("data")
 *     // ...
 * }
 * ```
 */
interface PromptBetterExtension {
    val pythonCommand: Property<String>
    val commandPrefix: ListProperty<String>
    val promptsDir: Property<String>
    val datasetDir: Property<String>
    val promptName: Property<String>
    val autoMode: Property<String>
    val numThreads: Property<String>
    val trainRatio: Property<String>
    val swiftOutputDir: Property<String>
    val language: Property<String>
    val templateFile: Property<String>
    val apply: Property<Boolean>

    val studentBaseUrl: Property<String>
    val studentModel: Property<String>
    val studentApiKey: Property<String>
    val teacherBaseUrl: Property<String>
    val teacherModel: Property<String>
    val teacherApiKey: Property<String>
}

// Create and initialize the extension with default convention values
val promptBetter = extensions.create<PromptBetterExtension>("promptBetter").apply {
    pythonCommand.convention("python3")
    commandPrefix.convention(listOf("mise", "exec", "--"))
    promptsDir.convention("prompts")
    datasetDir.convention("data")
    promptName.convention("ALL")
    autoMode.convention("light")
    numThreads.convention("1")
    trainRatio.convention("0.8")
    swiftOutputDir.convention("src/main/swift/Generated")
    language.convention("swift")
    templateFile.convention("")
    apply.convention(false)

    studentBaseUrl.convention("")
    studentModel.convention("")
    studentApiKey.convention("")
    teacherBaseUrl.convention("")
    teacherModel.convention("")
    teacherApiKey.convention("")
}

// Helper to resolve project properties dynamically (CLI overrides take precedence)
fun <T> getProp(name: String, extensionProp: Property<T>, defaultVal: T): T {
    val gradleProp = providers.gradleProperty(name)
    return if (gradleProp.isPresent) {
        val raw = gradleProp.get()
        @Suppress("UNCHECKED_CAST")
        when (defaultVal) {
            is Boolean -> raw.toBoolean() as T
            else -> raw as T
        }
    } else {
        extensionProp.getOrElse(defaultVal)
    }
}

// Helper to construct CLI and environment settings for validation and optimization
fun Exec.configurePromptBetterRuntime(
    command: String,
    includeRuntimeEndpoints: Boolean,
) {
    group = "prompt-better"
    workingDir = projectDir

    doFirst {
        val python = getProp("promptBetterPython", promptBetter.pythonCommand, "python3")
        val prefix = promptBetter.commandPrefix.get()
        val promptsDirVal = getProp("promptBetterPromptsDir", promptBetter.promptsDir, "prompts")
        val datasetDirVal = getProp("promptBetterDataset", promptBetter.datasetDir, "data")
        val promptNameVal = getProp("promptBetterPrompt", promptBetter.promptName, "ALL")
        val autoModeVal = getProp("promptBetterAutoMode", promptBetter.autoMode, "light")
        val numThreadsVal = getProp("promptBetterNumThreads", promptBetter.numThreads, "1")
        val trainRatioVal = getProp("promptBetterTrainRatio", promptBetter.trainRatio, "0.8")
        val applyVal = getProp("promptBetterApply", promptBetter.apply, false)

        val argsList = mutableListOf<String>()
        argsList.addAll(prefix)
        argsList.addAll(listOf(
            python, "-m", "prompt_better.cli",
            command,
            "--prompts-dir", project.file(promptsDirVal).absolutePath,
            "--dataset", project.file(datasetDirVal).absolutePath,
            "--prompt", promptNameVal,
            "--auto", autoModeVal,
            "--num-threads", numThreadsVal,
            "--train-ratio", trainRatioVal
        ))
        if (applyVal) {
            argsList.add("--apply")
        }
        commandLine(argsList)

        if (includeRuntimeEndpoints) {
            val studentBase = getProp("promptBetterStudentBaseUrl", promptBetter.studentBaseUrl, "")
            val studentModel = getProp("promptBetterStudentModel", promptBetter.studentModel, "")
            val studentKey = getProp("promptBetterStudentApiKey", promptBetter.studentApiKey, "")
            val teacherBase = getProp("promptBetterTeacherBaseUrl", promptBetter.teacherBaseUrl, "")
            val teacherModel = getProp("promptBetterTeacherModel", promptBetter.teacherModel, "")
            val teacherKey = getProp("promptBetterTeacherApiKey", promptBetter.teacherApiKey, "")

            if (studentBase.isNotEmpty()) environment("PROMPT_BETTER_STUDENT_BASE_URL", studentBase)
            if (studentModel.isNotEmpty()) environment("PROMPT_BETTER_STUDENT_MODEL", studentModel)
            if (studentKey.isNotEmpty()) environment("PROMPT_BETTER_STUDENT_API_KEY", studentKey)
            if (teacherBase.isNotEmpty()) environment("PROMPT_BETTER_TEACHER_BASE_URL", teacherBase)
            if (teacherModel.isNotEmpty()) environment("PROMPT_BETTER_TEACHER_MODEL", teacherModel)
            if (teacherKey.isNotEmpty()) environment("PROMPT_BETTER_TEACHER_API_KEY", teacherKey)
        }
    }
}

// Register Tasks
tasks.register<Exec>("promptBetterList") {
    group = "prompt-better"
    description = "Lists prompts defined in JSON files."
    workingDir = projectDir
    doFirst {
        val python = getProp("promptBetterPython", promptBetter.pythonCommand, "python3")
        val prefix = promptBetter.commandPrefix.get()
        val promptsDirVal = getProp("promptBetterPromptsDir", promptBetter.promptsDir, "prompts")

        commandLine(
            prefix + listOf(
                python, "-m", "prompt_better.cli",
                "list-prompts",
                "--prompts-dir", project.file(promptsDirVal).absolutePath
            )
        )
    }
}

tasks.register<Exec>("promptBetterPreviewSchema") {
    group = "prompt-better"
    description = "Prints the JSON schema for the selected prompt."
    workingDir = projectDir
    doFirst {
        val python = getProp("promptBetterPython", promptBetter.pythonCommand, "python3")
        val prefix = promptBetter.commandPrefix.get()
        val promptsDirVal = getProp("promptBetterPromptsDir", promptBetter.promptsDir, "prompts")
        val promptNameVal = getProp("promptBetterPrompt", promptBetter.promptName, "ALL")

        commandLine(
            prefix + listOf(
                python, "-m", "prompt_better.cli",
                "preview-schema",
                "--prompts-dir", project.file(promptsDirVal).absolutePath,
                "--prompt", promptNameVal
            )
        )
    }
}

tasks.register<Exec>("promptBetterValidate") {
    description = "Runs baseline prompt validation against the configured student endpoint using JSON schema."
    configurePromptBetterRuntime(command = "validate", includeRuntimeEndpoints = true)
}

tasks.register<Exec>("promptBetterOptimize") {
    description = "Runs prompt optimization using the configured Student and Teacher endpoints."
    configurePromptBetterRuntime(command = "optimize", includeRuntimeEndpoints = true)
}

abstract class PromptBetterGenerateSwiftTask @Inject constructor(
    private val execOperations: ExecOperations
) : DefaultTask() {
    @get:Input
    abstract val promptsDir: Property<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Input
    abstract val pythonCommand: Property<String>

    @get:Input
    abstract val commandPrefix: ListProperty<String>

    @get:Input
    abstract val language: Property<String>

    @get:Input
    abstract val templateFile: Property<String>

    @TaskAction
    fun generate() {
        val dir = project.file(promptsDir.get())
        val outDir = outputDir.get().asFile
        val pythonCmd = pythonCommand.get()
        val prefix = commandPrefix.get()
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
                val args = mutableListOf<String>()
                args.addAll(prefix)
                args.addAll(listOf(
                    pythonCmd, "-m", "prompt_better.cli", "generate",
                    "--source", file.absolutePath,
                    "--target", outputFile.absolutePath
                ))
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

tasks.register<PromptBetterGenerateSwiftTask>("promptBetterGenerateSwift") {
    group = "prompt-better"
    description = "Generates Swift GenerableWithPrompt structs from JSON definitions."
    promptsDir.set(promptBetter.promptsDir)
    outputDir.set(project.layout.projectDirectory.dir(promptBetter.swiftOutputDir))
    pythonCommand.set(promptBetter.pythonCommand)
    commandPrefix.set(promptBetter.commandPrefix)
    language.set(promptBetter.language)
    templateFile.set(promptBetter.templateFile)
}
