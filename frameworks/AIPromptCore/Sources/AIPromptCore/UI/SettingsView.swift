import SwiftUI

/// Multiplatform Settings & Configuration View for Apple AI Bridge and AIPromptCore.
/// Designed for macOS Preferences (Cmd+,) and iOS Navigation/Sheet.
public struct SettingsView: View {
    @State private var enableOpenAIAliases: Bool
    @State private var customAliases: [AliasEntry] = []
    @State private var newAliasKey: String = ""
    @State private var newAliasTarget: String = CanonicalModel.omni.rawValue
    @State private var indexCounts: (spotlight: Int, vector: Int) = (0, 0)
    @State private var showResetConfirmation: Bool = false
    
    struct AliasEntry: Identifiable {
        let id = UUID()
        var alias: String
        var target: String
    }
    
    public init() {
        _enableOpenAIAliases = State(initialValue: AliasConfiguration.shared.enableOpenAIAliases)
    }
    
    public var body: some View {
        Form {
            // MARK: - Model Aliases Section
            Section(
                header: Text("Model Aliases & Routing"),
                footer: Text("When OpenAI aliases are enabled, requests for gpt-4o, whisper-1, tts-1, etc., are automatically routed to corresponding Apple Intelligence on-device models.")
            ) {
                Toggle("Enable OpenAI Standard Aliases", isOn: $enableOpenAIAliases)
                    .onChange(of: enableOpenAIAliases) { oldValue, newValue in
                        AliasConfiguration.shared.enableOpenAIAliases = newValue
                    }
                
                // Custom Aliases List
                if !customAliases.isEmpty {
                    ForEach(customAliases) { entry in
                        HStack {
                            Text(entry.alias)
                                .font(.system(.body, design: .monospaced))
                                .bold()
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            Text(entry.target)
                                .foregroundColor(.secondary)
                                .font(.system(.caption, design: .monospaced))
                            Button(action: {
                                removeAlias(entry.alias)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Add New Custom Alias
                HStack {
                    TextField("Custom alias (e.g. 'my-agent')", text: $newAliasKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("Target", selection: $newAliasTarget) {
                        ForEach(CanonicalModel.allCases, id: \.rawValue) { model in
                            Text(model.rawValue).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Button("Add") {
                        addAlias()
                    }
                    .disabled(newAliasKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            // MARK: - Local Search & RAG Index Section
            Section(
                header: Text("Local RAG & Indexing"),
                footer: Text("Indexed documents are stored safely on-device across CoreSpotlight (lexical) and NaturalLanguage vector embeddings.")
            ) {
                HStack {
                    Text("CoreSpotlight Indexed Items:")
                    Spacer()
                    Text("\(indexCounts.spotlight)")
                        .bold()
                }
                
                HStack {
                    Text("Vector Embedding Items:")
                    Spacer()
                    Text("\(indexCounts.vector)")
                        .bold()
                }
                
                Button(role: .destructive, action: {
                    showResetConfirmation = true
                }) {
                    Text("Clear All Local Indexes")
                }
                .confirmationDialog("Clear All Local Indexes?", isPresented: $showResetConfirmation) {
                    Button("Clear Indexes", role: .destructive) {
                        clearIndexes()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all documents and vectors from local search indexes.")
                }
            }
            
            // MARK: - System & Diagnostics
            Section(header: Text("System & Hardware Diagnostics")) {
                LabeledContent("Active System Model", value: ModelRegistry.systemDefaultConcreteName)
                LabeledContent("Architecture", value: "Neural Engine (Apple Silicon)")
                LabeledContent("Diagnostics", value: ModelRegistry.systemModelDiagnostics)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Apple AI Bridge Settings")
        .task {
            loadState()
        }
    }
    
    private func loadState() {
        enableOpenAIAliases = AliasConfiguration.shared.enableOpenAIAliases
        customAliases = AliasConfiguration.shared.customAliases.map { AliasEntry(alias: $0.key, target: $0.value) }
        Task { @MainActor in
            indexCounts = await IndexClient().count()
        }
    }
    
    private func addAlias() {
        let trimmed = newAliasKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AliasConfiguration.shared.setAlias(alias: trimmed, target: newAliasTarget)
        newAliasKey = ""
        loadState()
    }
    
    private func removeAlias(_ alias: String) {
        AliasConfiguration.shared.removeAlias(alias: alias)
        loadState()
    }
    
    private func clearIndexes() {
        Task { @MainActor in
            await IndexClient().clear()
            indexCounts = await IndexClient().count()
        }
    }
}
