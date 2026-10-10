import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
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

/// One saved chat: transcript plus composer. The model is fixed by the conversation.
struct ChatConversationView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var store: ChatStore

    let conversationID: UUID

    @State private var inputText: String = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var attachmentError: String?

    private var conversation: Conversation? { store.conversation(conversationID) }
    private var isSending: Bool { store.isSending(conversationID) }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
        .navigationTitle(conversation?.title ?? "Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationSubtitle(conversation.map { modelLabel(for: $0.modelId) } ?? "")
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await addAttachments { for item in items { try await attachments.append(ChatAttachmentLoader.load(photo: item)) } } }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedFileTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await addAttachments { for url in urls { try await attachments.append(ChatAttachmentLoader.load(file: url)) } } }
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(conversation?.messages ?? []) { message in
                        MessageBubbleView(message: message, conversationID: conversationID)
                            .id(message.id)
                    }
                    if isSending {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Responding...").font(.caption).foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("loading-state")
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: conversation?.messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: isSending) { _, sending in
                if sending { withAnimation { proxy.scrollTo("loading-state", anchor: .bottom) } }
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AttachmentChipView(attachment: attachment) {
                                attachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            if let attachmentError {
                Text(attachmentError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            HStack(spacing: 10) {
                if acceptsImages {
                    PhotosPicker(selection: $photoSelection, maxSelectionCount: 5, matching: .any(of: [.images, .videos])) {
                        Image(systemName: "photo.on.rectangle").font(.title3).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add photos or videos")
                }

                if acceptsFiles {
                    Button(action: { showFileImporter = true }) {
                        Image(systemName: "paperclip").font(.title3).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach files")
                }

                if acceptsText {
                    TextField(inputPlaceholder, text: $inputText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(20)
                        .onSubmit { sendMessage() }
                } else {
                    Text(inputPlaceholder)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(canSend ? .green : .secondary)
                }
                .disabled(!canSend)
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color.platformBackground)
    }

    // MARK: Model capabilities

    private var canonicalModel: CanonicalModel? {
        conversation.flatMap { CanonicalModel(rawValue: ModelRegistry.resolveCanonicalId($0.modelId)) }
    }

    private var modalities: Set<InputModality> { canonicalModel?.inputModalities ?? [.text] }
    private var acceptsText: Bool { modalities.contains(.text) }
    private var acceptsImages: Bool { modalities.contains(.image) }
    private var acceptsFiles: Bool { !modalities.isDisjoint(with: [.image, .audio, .document]) }

    private var allowedFileTypes: [UTType] {
        var types: [UTType] = []
        if modalities.contains(.image) { types += [.image, .movie] }
        if modalities.contains(.audio) { types.append(.audio) }
        if modalities.contains(.document) {
            let formats = canonicalModel?.documentFormats ?? []
            if formats.contains("pdf") { types.append(.pdf) }
            if formats.contains("txt") { types.append(.text) }
        }
        return types
    }

    private var inputPlaceholder: String {
        switch modalities {
        case [.image]: return "Attach an image"
        case [.document]: return "Attach a PDF"
        case [.audio]: return "Attach an audio file"
        default: return "Type a message..."
        }
    }

    private var canSend: Bool {
        let hasText = acceptsText && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return conversation != nil && (hasText || !attachments.isEmpty) && !isSending
    }

    /// Runs an attachment load, surfacing a failure inline instead of dropping it silently.
    private func addAttachments(_ load: () async throws -> Void) async {
        attachmentError = nil
        do {
            try await load()
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        let text = acceptsText ? inputText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let sent = attachments
        inputText = ""
        attachments = []
        attachmentError = nil

        let server = serverManager
        store.send(
            to: conversationID,
            text: text,
            attachments: sent,
            log: { server.log($0) },
            ensureServer: { if !server.isRunning { await server.start() } }
        )
    }
}

struct AttachmentChipView: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let thumbnail = attachment.thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: attachment.kind.symbol)
                    .frame(width: 28, height: 28)
            }
            Text(attachment.name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 120)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    let conversationID: UUID

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(message.attachments) { attachment in
                        StoredAttachmentView(attachment: attachment, conversationID: conversationID)
                    }
                    textView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(message.generatedImages ?? [], id: \.self) { imageID in
                        GeneratedImageView(imageID: imageID, conversationID: conversationID)
                    }
                    textView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundColor(message.isError ? .red : .primary)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 40)
            }
        }
    }

    /// Long press (right-click on macOS) offers the share sheet and copy for the message text.
    @ViewBuilder
    private var textView: some View {
        if !message.text.isEmpty {
            Text(message.text)
                .font(.body)
                .contextMenu {
                    ShareLink(item: message.text) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { copyToPasteboard(message.text) } label: { Label("Copy", systemImage: "doc.on.doc") }
                }
        }
    }
}

private func copyToPasteboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

/// A sent attachment: its preview, and when the model got text instead of the media, a chevron that reveals that text.
/// Long press shares the media (and the extracted text, if any).
private struct StoredAttachmentView: View {
    @EnvironmentObject var store: ChatStore
    let attachment: ChatMessage.Attachment
    let conversationID: UUID

    @State private var thumbnail: CGImage?
    @State private var showText = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        if attachment.kind == .video {
                            Image(systemName: "play.circle.fill").font(.title2).padding(6)
                        }
                    }
            }
            if let text = attachment.extractedText {
                DisclosureGroup(isExpanded: $showText) {
                    Text(text.isEmpty ? "(no text was extracted)" : text)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Label(attachment.name, systemImage: attachment.kind.symbol)
                        .font(.caption)
                        .lineLimit(1)
                }
                .tint(.white)
                .frame(maxWidth: 260, alignment: .trailing)
            } else {
                Label(attachment.name, systemImage: attachment.kind.symbol)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            ShareLink(item: media, preview: SharePreview(attachment.name)) {
                Label("Share \(attachment.kind == .video ? "Frame" : "File")", systemImage: "square.and.arrow.up")
            }
            if let text = attachment.extractedText, !text.isEmpty {
                ShareLink(item: text) { Label("Share Extracted Text", systemImage: "text.alignleft") }
                Button { copyToPasteboard(text) } label: { Label("Copy Extracted Text", systemImage: "doc.on.doc") }
            }
        }
        .task {
            guard attachment.hasThumbnail else { return }
            thumbnail = await store.thumbnail(conversation: conversationID, attachment: attachment.id)
        }
    }

    private var media: StoredMedia {
        StoredMedia(
            source: .parts(store.attachmentPartsURL(conversation: conversationID, attachment: attachment.id)),
            name: attachment.name,
            fileExtension: attachment.kind == .video ? "jpg" : nil
        )
    }
}

/// An image the model generated; long press shares the PNG.
private struct GeneratedImageView: View {
    @EnvironmentObject var store: ChatStore
    let imageID: UUID
    let conversationID: UUID

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 160, height: 160)
                    .overlay { ProgressView() }
            }
        }
        .contextMenu {
            ShareLink(item: media, preview: SharePreview("Generated image")) {
                Label("Share Image", systemImage: "square.and.arrow.up")
            }
        }
        .task { image = await store.generatedImage(conversation: conversationID, image: imageID) }
    }

    private var media: StoredMedia {
        StoredMedia(source: .file(store.generatedImageURL(conversation: conversationID, image: imageID)), name: "Generated image.png")
    }
}
