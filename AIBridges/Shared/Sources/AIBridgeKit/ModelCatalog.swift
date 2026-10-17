import Foundation
import FoundationModels

/// The language-model IDs the bridge serves.
public enum BridgeModel: String, CaseIterable, Sendable {
    /// `SystemLanguageModel.default`, the system's current on-device model.
    case defaultAFM = "default"
    /// Alias for `default`.
    case foundationModel3B = "apple-foundation-model-3-core-3b"
    /// Alias for `default`.
    case foundationModelGeneric = "apple-foundation-model"
    /// Private Cloud Compute. Served by the on-device model until the SDK exposes PCC.
    case privateCloudCompute = "apple-intelligence-private-cloud-compute"

    /// Resolves a requested model name, accepting LiteLLM-style `openai/` prefixes.
    public static func resolve(_ name: String) -> BridgeModel? {
        let normalized = name.hasPrefix("openai/") ? String(name.dropFirst("openai/".count)) : name
        return BridgeModel(rawValue: normalized)
    }

    public var languageModel: SystemLanguageModel { .default }

    /// Startup diagnostics for the system model.
    public static var diagnostics: String {
        let model = SystemLanguageModel.default
        var name = "AFM 3 Core (3B dense)"
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            name = model.variant.displayName
        }
        return "System model: \(name), context: \(model.contextSize) tokens, availability: \(model.availability)"
    }
}
