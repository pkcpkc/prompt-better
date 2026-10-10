import Foundation

/// Which models a chat can use: everything that serves chat completions, plus the image generators,
/// which answer a prompt with a picture instead of text.
enum ChatModels {
    static let imageModels: [CanonicalModel] = [.imagePlayground]

    static var pickerIds: [String] {
        ModelRegistry.chatModelIds + imageModels.map(\.rawValue)
    }

    static func isImageModel(_ modelId: String) -> Bool {
        CanonicalModel(rawValue: ModelRegistry.resolveCanonicalId(modelId))?.type == .imageGeneration
    }
}
