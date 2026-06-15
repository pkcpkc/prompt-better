import SwiftUI
import FoundationModels

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension Color {
    static var platformBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

struct ChatWindowView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var serverManager: ServerManager
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack {
                Text("Model Chat")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            
            // Conversation History (iMessage style)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                        }
                        
                        if isSending {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Responding...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading-state")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages) { oldValue, newValue in
                    if let last = newValue.last {
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: isSending) { oldValue, newValue in
                    if newValue {
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo("loading-state", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Input field and green send button
            HStack(spacing: 10) {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: {
                    sendMessage()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .green)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.platformBackground)
        }
        .frame(minWidth: 350, minHeight: 450)
        .onDisappear {
            messages.removeAll()
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        inputText = ""
        let userMsg = ChatMessage(isUser: true, text: text)
        messages.append(userMsg)
        
        isSending = true
        Task {
            // Implicitly start server if not running
            if !serverManager.isRunning {
                await serverManager.start()
            }
            
            // Log the request to make it appear in the dashboard logs
            serverManager.log("POST /v1/chat/completions (Chat Window)")
            
            do {
                let session = LanguageModelSession()
                // Combine history for context
                let historyPrompt = messages.map { ($0.isUser ? "User: " : "Model: ") + $0.text }.joined(separator: "\n\n")
                
                let response = try await session.respond(to: historyPrompt)
                let responseText = response.content
                
                serverManager.log("200 POST /v1/chat/completions (Chat Window)")
                
                await MainActor.run {
                    messages.append(ChatMessage(isUser: false, text: responseText))
                    isSending = false
                }
            } catch {
                serverManager.log("500 POST /v1/chat/completions (Chat Window) - Error: \(error.localizedDescription)")
                await MainActor.run {
                    messages.append(ChatMessage(isUser: false, text: "Error: \(error.localizedDescription)"))
                    isSending = false
                }
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundColor(.primary)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 40)
            }
        }
    }
}
