import Foundation
import FoundationModels

/// Which Apple Foundation Model tier backs `SystemLanguageModel.default` on this device.
public enum AFMTier: String, Sendable, CaseIterable {
    /// The 3B dense on-device model.
    case core3B = "core-3b"
    /// The advanced sparse (MoE) on-device model, available on OS 27+ with enough memory.
    case coreAdvanced = "core-advanced"
    /// Apple Intelligence is not available (unsupported device, disabled, or model not ready).
    case unavailable

    /// How the tier was determined.
    public enum Source: String, Sendable {
        /// `SystemLanguageModel.variant`, reported by the system. Authoritative.
        case systemVariant
        /// Inferred from OS version or physical memory. A heuristic.
        case inferred
        case none
    }

    public var displayName: String {
        switch self {
        case .core3B: return "AFM 3 Core (3B dense)"
        case .coreAdvanced: return "AFM 3 Core Advanced (20B sparse)"
        case .unavailable: return "Unavailable"
        }
    }

    /// Whether the model at this tier accepts image input.
    ///
    /// Verified for `.coreAdvanced` (it described a generated image correctly). Assumed `false` for
    /// `.core3B`: the SDK exposes no capability flag and no 3B device was available to test.
    public var acceptsImages: Bool { self == .coreAdvanced }

    /// Physical memory at or above which an unrecognized OS 27+ variant is assumed to be the advanced tier.
    static let advancedMemoryThreshold: UInt64 = 12_000_000_000

    /// The active tier and how it was determined.
    ///
    /// Heuristic, in order:
    /// 1. Apple Intelligence not available: `.unavailable`.
    /// 2. OS 27+: trust `SystemLanguageModel.default.variant` (`coreAdvanced3` or `core3`).
    /// 3. OS 27+ with a variant this code does not recognize (a future model): fall back to physical
    ///    memory, at least 12 GB means `.coreAdvanced`, otherwise `.core3B`.
    /// 4. OS 26: only the 3B model ships and there is no variant API, so `.core3B`. Memory is not
    ///    consulted, since a high-RAM device on OS 26 still runs the 3B model.
    public static func detect(
        availability: SystemLanguageModel.Availability = SystemLanguageModel.default.availability,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> (tier: AFMTier, source: Source) {
        guard case .available = availability else { return (.unavailable, .none) }

        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            switch SystemLanguageModel.default.variant {
            case .coreAdvanced3: return (.coreAdvanced, .systemVariant)
            case .core3: return (.core3B, .systemVariant)
            default:
                return (physicalMemory >= advancedMemoryThreshold ? .coreAdvanced : .core3B, .inferred)
            }
        }
        return (.core3B, .inferred)
    }
}
