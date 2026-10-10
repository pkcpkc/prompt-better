import Foundation
import ImageIO

/// Loads image bytes from the reference formats accepted in OpenAI-style requests.
enum ImageLoading {
    /// Accepts a data URL, http(s) URL, file path, or bare base64. Throws a descriptive error otherwise.
    static func data(fromReference reference: String) throws -> Data {
        if reference.hasPrefix("data:") {
            guard let comma = reference.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(reference[reference.index(after: comma)...])) else {
                throw AIError.unsupportedOperation("Image data URL is not valid base64.")
            }
            return data
        }
        if let url = URL(string: reference), url.scheme != nil {
            guard let data = try? Data(contentsOf: url) else {
                throw AIError.unsupportedOperation("Could not load the image from '\(reference)'.")
            }
            return data
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: reference)) { return data }
        if let data = Data(base64Encoded: reference) { return data }
        throw AIError.unsupportedOperation("Could not load the image: expected a data URL, http(s) URL, file path or base64 data.")
    }

    static func cgImage(fromReference reference: String) throws -> CGImage {
        let bytes = try data(fromReference: reference)
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIError.unsupportedOperation("Could not decode the image.")
        }
        return image
    }
}
