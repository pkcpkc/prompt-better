import SwiftUI

/// The chat screen: a sidebar with every saved chat and a "new chat" action, plus the selected chat.
/// `onClose` returns to the dashboard.
struct ChatRootView: View {
    @EnvironmentObject var serverManager: ServerManager
    @StateObject private var store = ChatStore()

    let onClose: () -> Void

    @State private var selection: UUID?
    @State private var showNewChat = false
    @State private var pendingDelete: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let id = selection, store.conversation(id) != nil {
                ChatConversationView(conversationID: id)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "No Chat Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a new chat or pick a previous one.")
                )
            }
        }
        .environmentObject(store)
        .sheet(isPresented: $showNewChat) {
            NewChatSheet { modelId in
                selection = store.create(modelId: modelId).id
            }
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Chat and All Data", role: .destructive) {
                if let id = pendingDelete {
                    if selection == id { selection = nil }
                    store.delete(id)
                }
                pendingDelete = nil
            }
        } message: {
            Text("The messages and all attached media are permanently removed from this device.")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(store.conversations) { conversation in
                ConversationRow(conversation: conversation, isSelected: selection == conversation.id) {
                    pendingDelete = conversation.id
                }
                    .tag(conversation.id)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = conversation.id }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = conversation.id }
                    }
            }
        }
        .overlay {
            if store.conversations.isEmpty {
                ContentUnavailableView("No Chats Yet", systemImage: "bubble.left", description: Text("Start one with the + button."))
            }
        }
        // The header is part of the sidebar itself so Close and New Chat are always visible,
        // whatever window or toolbar the screen is hosted in.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.title3)
                }
                .help("Close")
                Text("Chats").font(.title2.bold()).lineLimit(1).fixedSize()
                Spacer()
                Button { showNewChat = true } label: {
                    Image(systemName: "plus").font(.title3)
                }
                .help("New Chat")
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            details
            if isSelected {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete chat")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(ModelRegistry.displayName(for: conversation.modelId))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(conversation.updatedAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Starting a chat requires an explicit model choice; it is fixed for the life of the chat.
private struct NewChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String) -> Void

    @State private var modelId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Model", selection: $modelId) {
                        Text("Select a model").tag(String?.none)
                        ForEach(ChatModels.pickerIds, id: \.self) { id in
                            Text(modelLabel(for: id)).tag(String?.some(id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Model")
                } footer: {
                    Text("The model can't be changed once the chat has started.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Chat")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        if let modelId { onCreate(modelId) }
                        dismiss()
                    }
                    .disabled(modelId == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }
}

/// Picker label with the model type, e.g. "[llm] System Default Model: ...".
func modelLabel(for modelId: String) -> String {
    let type = CanonicalModel(rawValue: modelId)?.type.rawValue
    return (type.map { "[\($0)] " } ?? "") + ModelRegistry.displayName(for: modelId)
}
