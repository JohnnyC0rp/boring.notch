import Defaults

enum CodexAvatarStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case smile
    case codex
    case codexSpin
    case iris

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smile: return "Smile"
        case .codex: return "Codex thinking"
        case .codexSpin: return "Codex spin"
        case .iris: return "Colorful iris"
        }
    }
}
