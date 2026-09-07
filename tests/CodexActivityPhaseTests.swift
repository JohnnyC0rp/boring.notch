import Foundation

@main
enum CodexActivityPhaseTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 100)
        func phase(service: String = "boringnotch-codex-activity", version: Int = 1,
                   updated: Double = 100, count: Int = 1) -> CodexActivityPhase {
            CodexActivitySnapshot(service: service, version: version, phase: .active,
                                  updatedAt: updated, activeCount: count).validatedPhase(at: now)
        }
        precondition(phase() == .active)
        precondition(phase(service: "unrelated-service") == .offline)
        precondition(phase(version: 2) == .offline)
        precondition(phase(updated: 90) == .offline)
        precondition(phase(updated: 110) == .offline)
        precondition(phase(count: -1) == .offline)
        let data = Data("{\"service\":\"boringnotch-codex-activity\",\"version\":1,\"phase\":\"waiting\",\"updatedAt\":100,\"activeCount\":1}".utf8)
        let decoded = try JSONDecoder().decode(CodexActivitySnapshot.self, from: data)
        precondition(decoded.validatedPhase(at: now) == .waiting)
        precondition(CodexActivityPhase.active.isInProgress)
        precondition(CodexActivityPhase.waiting.isInProgress)
        precondition(!CodexActivityPhase.idle.isInProgress)
        precondition(!CodexActivityPhase.offline.isInProgress)
        precondition(!CodexActivityPhase.error.isInProgress)
        print("12 Codex activity phase checks passed")
    }
}
