import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// A stored piece of media offered to the system share sheet. The file is produced only when the user
/// actually shares it, because attachments are kept as encoded content parts rather than as files.
struct StoredMedia: Transferable {
    enum Source {
        /// `<id>.parts.json` holding the attachment's content parts.
        case parts(URL)
        /// A ready file, e.g. a generated PNG.
        case file(URL)
    }

    let source: Source
    let name: String
    /// Replaces the extension of `name` when the stored bytes are a different format (a video's JPEG frame).
    var fileExtension: String? = nil

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { media in
            SentTransferredFile(try media.exportFile())
        }
    }

    private func exportFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        switch source {
        case .file(let url):
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        case .parts(let url):
            let parts = try JSONDecoder().decode([ContentPart].self, from: Data(contentsOf: url))
            // Videos are stored as sampled frames, so a video shares its first frame as a JPEG.
            guard let first = parts.first, let data = Self.payload(of: first) else {
                throw ChatAttachmentError.unreadable(name)
            }
            let base = (name as NSString).deletingPathExtension
            let fileName = fileExtension.map { "\(base).\($0)" } ?? name
            let destination = directory.appendingPathComponent(fileName)
            try data.write(to: destination)
            return destination
        }
    }

    private static func payload(of part: ContentPart) -> Data? {
        switch part {
        case .imageUrl(let image):
            guard let comma = image.url.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(image.url[image.url.index(after: comma)...])) else { return nil }
            return data
        case .inputAudio(let audio):
            return Data(base64Encoded: audio.data)
        case .document(let document):
            return Data(base64Encoded: document.data)
        case .text:
            return nil
        }
    }
}
