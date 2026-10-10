import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Why an image could not be generated.
public enum ImageGenerationError: Error, LocalizedError, Sendable {
    /// The generator cannot run here: Apple Intelligence is off or unsupported, or there is no window to host Image Playground.
    case unavailable(String)
    /// The user closed Image Playground without choosing an image.
    case cancelled
    case noImage

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return "Image generation is unavailable: \(reason)"
        case .cancelled: return "Image generation was cancelled."
        case .noImage: return "The image generator returned no image."
        }
    }
}

/// On-device image generation through Apple's Image Playground framework.
///
/// `apple-image-playground` presents the system Image Playground sheet over the frontmost window,
/// pre-filled with the prompt, and returns the image the user picks. There is no headless path: Apple
/// deprecated `ImageCreator` in favour of the view controller and the SwiftUI sheet.
///
/// The API takes no output size, so `size` is ignored.
public final class ImageGenerationService: @unchecked Sendable {
    public static let shared = ImageGenerationService()

    public init() {}

    /// Generates images based on OpenAI ImageGenerationRequest.
    public func generate(request: OpenAI.ImageGenerationRequest) async throws -> OpenAI.ImageGenerationResponse {
        let count = max(1, min(request.n ?? 1, 4))

        var generatedObjects: [OpenAI.ImageObject] = []
        for _ in 0..<count {
            let png = try await generateWithImagePlayground(request: request)
            generatedObjects.append(formatImageObject(pngData: png, format: request.responseFormat))
        }

        return OpenAI.ImageGenerationResponse(created: Int(Date().timeIntervalSince1970), data: generatedObjects)
    }

    // MARK: - Apple Image Playground (system UI)

    @MainActor
    private func generateWithImagePlayground(request: OpenAI.ImageGenerationRequest) async throws -> Data {
        #if canImport(ImagePlayground)
        let data = try await PlaygroundSession().run(prompt: request.prompt, styleName: request.style)
        return try Self.pngData(fromImageData: data)
        #else
        throw ImageGenerationError.unavailable("ImagePlayground is not available on this platform.")
        #endif
    }

    // MARK: - Encoding

    private func formatImageObject(pngData: Data, format: String?) -> OpenAI.ImageObject {
        if format == "b64_json" || format == nil {
            return OpenAI.ImageObject(b64Json: pngData.base64EncodedString())
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("generated-\(UUID().uuidString).png")
        try? pngData.write(to: tempURL)
        return OpenAI.ImageObject(url: tempURL.absoluteString)
    }

    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageGenerationError.noImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageGenerationError.noImage }
        return data as Data
    }

    static func pngData(fromImageData data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageGenerationError.noImage
        }
        return try pngData(from: image)
    }
}

#if canImport(ImagePlayground)
/// Presents one Image Playground sheet and waits for the user's choice. Held strongly while the sheet is
/// up because the view controller only keeps a weak reference to its delegate.
@MainActor
private final class PlaygroundSession: NSObject, ImagePlaygroundViewController.Delegate {
    private var continuation: CheckedContinuation<Data, Error>?

    func run(prompt: String, styleName: String?) async throws -> Data {
        guard ImagePlaygroundViewController.isAvailable else {
            throw ImageGenerationError.unavailable("Image Playground requires Apple Intelligence to be enabled.")
        }
        let controller = ImagePlaygroundViewController()
        controller.concepts = [.text(prompt)]
        if let style = Self.style(named: styleName), controller.allowedGenerationStyles.contains(style) {
            controller.selectedGenerationStyle = style
        }
        controller.delegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if !present(controller) {
                self.continuation = nil
                continuation.resume(throwing: ImageGenerationError.unavailable("There is no foreground window to present Image Playground in."))
            }
        }
    }

    private static func style(named name: String?) -> ImagePlaygroundStyle? {
        switch name?.lowercased() {
        case "animation": return .animation
        case "illustration": return .illustration
        case "sketch": return .sketch
        case "emoji": return .emoji
        default: return nil
        }
    }

    private func present(_ controller: ImagePlaygroundViewController) -> Bool {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return false }
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
        return true
        #elseif os(macOS)
        // NSApp is nil in processes without an NSApplication (command-line tools, test runners).
        let app: NSApplication? = NSApp
        guard let host = (app?.keyWindow ?? app?.mainWindow)?.contentViewController else { return false }
        host.presentAsSheet(controller)
        return true
        #else
        return false
        #endif
    }

    private func dismiss(_ controller: ImagePlaygroundViewController) {
        #if os(iOS)
        controller.dismiss(animated: true)
        #elseif os(macOS)
        controller.dismiss(nil)
        #endif
    }

    func imagePlaygroundViewController(_ imagePlaygroundViewController: ImagePlaygroundViewController, didCreateImageAt imageURL: URL) {
        dismiss(imagePlaygroundViewController)
        // Read now: the file is the system's to clean up once the sheet is gone.
        if let data = try? Data(contentsOf: imageURL) {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: ImageGenerationError.noImage)
        }
        continuation = nil
    }

    func imagePlaygroundViewControllerDidCancel(_ imagePlaygroundViewController: ImagePlaygroundViewController) {
        dismiss(imagePlaygroundViewController)
        continuation?.resume(throwing: ImageGenerationError.cancelled)
        continuation = nil
    }
}
#endif
