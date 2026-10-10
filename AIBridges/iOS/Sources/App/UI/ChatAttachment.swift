import Foundation
import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

typealias ContentPart = OpenAI.ChatCompletionRequest.ContentPart

/// A file, image or video the user attached to a chat message, already converted into OpenAI content parts.
struct ChatAttachment: Identifiable, Equatable {
    enum Kind: String, Codable, Equatable {
        case image, video, audio, document

        /// Images and video frames: the media a vision model can look at directly.
        var isVisual: Bool { self == .image || self == .video }

        var symbol: String {
            switch self {
            case .image: return "photo"
            case .video: return "video"
            case .audio: return "waveform"
            case .document: return "doc.text"
            }
        }
    }

    let id = UUID()
    let name: String
    let kind: Kind
    let parts: [ContentPart]
    let thumbnail: CGImage?

    static func == (lhs: ChatAttachment, rhs: ChatAttachment) -> Bool { lhs.id == rhs.id }
}

enum ChatAttachmentError: LocalizedError {
    case unreadable(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Could not read '\(name)'."
        case .unsupported(let name): return "'\(name)' is not a supported file type."
        }
    }
}

/// A movie handed over by the photo picker, copied to a temporary location we own.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

enum ChatAttachmentLoader {
    /// Number of evenly spaced frames sampled from a video. The perception pipeline reads images
    /// through OCR, so a video contributes the text visible in these frames.
    static let videoFrameCount = 4

    static func load(photo item: PhotosPickerItem) async throws -> ChatAttachment {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                throw ChatAttachmentError.unreadable("video")
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            return try await loadVideo(at: movie.url, name: movie.url.lastPathComponent)
        }
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ChatAttachmentError.unreadable("image")
        }
        let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
        return try image(data: data, name: "Photo.\(type?.preferredFilenameExtension ?? "jpg")", mime: type?.preferredMIMEType ?? "image/jpeg")
    }

    /// Loads a file chosen through the file dialog. Callers pass security-scoped URLs on iOS.
    static func load(file url: URL) async throws -> ChatAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension.lowercased())

        if type?.conforms(to: .movie) == true {
            return try await loadVideo(at: url, name: name)
        }
        guard let data = try? Data(contentsOf: url) else { throw ChatAttachmentError.unreadable(name) }

        if type?.conforms(to: .image) == true {
            return try image(data: data, name: name, mime: type?.preferredMIMEType ?? "image/jpeg")
        }
        if type?.conforms(to: .audio) == true {
            let part = ContentPart.inputAudio(.init(data: data.base64EncodedString(), format: url.pathExtension.lowercased()))
            return ChatAttachment(name: name, kind: .audio, parts: [part], thumbnail: nil)
        }
        if type?.conforms(to: .pdf) == true {
            let part = ContentPart.document(.init(data: data.base64EncodedString(), format: "pdf", filename: name))
            return ChatAttachment(name: name, kind: .document, parts: [part], thumbnail: nil)
        }
        // Anything else is treated as UTF-8 text (txt, md, json, source files, ...).
        guard String(data: data, encoding: .utf8) != nil else { throw ChatAttachmentError.unsupported(name) }
        let part = ContentPart.document(.init(data: data.base64EncodedString(), format: "txt", filename: name))
        return ChatAttachment(name: name, kind: .document, parts: [part], thumbnail: nil)
    }

    // MARK: - Images & video

    private static func image(data: Data, name: String, mime: String) throws -> ChatAttachment {
        guard let thumb = thumbnail(from: data) else { throw ChatAttachmentError.unreadable(name) }
        let url = "data:\(mime);base64,\(data.base64EncodedString())"
        return ChatAttachment(name: name, kind: .image, parts: [.imageUrl(.init(url: url))], thumbnail: thumb)
    }

    private static func loadVideo(at url: URL, name: String) async throws -> ChatAttachment {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ChatAttachmentError.unreadable(name) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        var parts: [ContentPart] = []
        var poster: CGImage?
        for index in 0..<videoFrameCount {
            let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(videoFrameCount), preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image,
                  let jpeg = jpegData(from: frame) else { continue }
            poster = poster ?? frame
            parts.append(.imageUrl(.init(url: "data:image/jpeg;base64,\(jpeg.base64EncodedString())")))
        }
        guard !parts.isEmpty else { throw ChatAttachmentError.unreadable(name) }
        return ChatAttachment(name: name, kind: .video, parts: parts, thumbnail: poster.flatMap { thumbnail(from: $0) })
    }

    private static func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func thumbnail(from image: CGImage) -> CGImage? {
        jpegData(from: image).flatMap { thumbnail(from: $0) }
    }

    static func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
