import Defaults

enum CodexAvatarStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case smile
    case codex
    case codexSpin
    case iris

    var id: String { rawValue }

    init(tier: CodexActivityTier) {
        switch tier {
        case .smile: self = .smile
        case .syncing: self = .codex
        case .spin: self = .codexSpin
        case .iris: self = .iris
        }
    }

    var displayName: String {
        switch self {
        case .smile: return "Smile"
        case .codex: return "Codex syncing"
        case .codexSpin: return "Codex spin"
        case .iris: return "Colorful iris"
        }
    }
}
