import Foundation

@main
enum CodexActivityPhaseTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 100)
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func phase(service: String = "boringnotch-codex-activity", version: Int = 1,
                   updated: Double = 100, count: Int = 1, status: CodexActivityPhase = .active) -> CodexActivityPhase {
            CodexActivitySnapshot(service: service, version: version, phase: status,
                                  updatedAt: updated, activeCount: count).validatedPhase(at: now)
        }
        expect(phase() == .active, "Fresh activity is accepted")
        expect(phase(service: "unrelated-service") == .offline, "Unrelated services stay offline")
        expect(phase(version: 2) == .offline, "Unknown schemas stay offline")
        expect(phase(updated: 90) == .offline, "Stale counts cannot select a busy avatar")
        expect(phase(updated: 110) == .offline, "Future timestamps stay offline")
        expect(phase(count: -1) == .offline, "Negative counts are invalid")
        expect(phase(count: 0) == .offline, "Active metadata must contain an active thread")
        expect(phase(count: 1, status: .idle) == .offline, "Idle metadata cannot retain an old count")
        expect(phase(count: 0, status: .idle) == .idle, "Zero active threads is idle")
        let data = Data("{\"service\":\"boringnotch-codex-activity\",\"version\":1,\"phase\":\"waiting\",\"updatedAt\":100,\"activeCount\":1}".utf8)
        let decoded = try JSONDecoder().decode(CodexActivitySnapshot.self, from: data)
        expect(decoded.validatedPhase(at: now) == .waiting, "Waiting threads remain active")
        for state in [CodexActivityPhase.active, .waiting] {
            expect(state.isInProgress, "Running and waiting phases are in progress")
        }
        for state in [CodexActivityPhase.idle, .offline, .error] {
            expect(!state.isInProgress, "Other phases stay still")
        }
        let tiers: [(Int, CodexActivityTier)] = [
            (Int.min, .smile), (-1, .smile), (0, .smile), (1, .syncing), (2, .syncing),
            (3, .spin), (4, .iris), (5, .iris), (100, .iris), (Int.max, .iris)
        ]
        for (count, expected) in tiers {
            expect(CodexActivityLevel(activeCount: count).tier == expected, "Every tier boundary must select the expected avatar")
        }
        for count in 0...3 {
            expect(CodexActivityLevel(activeCount: count).speedMultiplier == 1, "Only Iris accelerates")
        }
        expect(abs(CodexActivityLevel(activeCount: 4).speedMultiplier - 1.15) < 0.000001, "Iris starts slightly above normal speed")
        var previousSpeed = CodexActivityLevel(activeCount: 4).speedMultiplier
        var previousIncrement = Double.infinity
        for count in 5...100 {
            let speed = CodexActivityLevel(activeCount: count).speedMultiplier
            let increment = speed - previousSpeed
            expect(increment > 0 && increment < previousIncrement, "Each added thread has a smaller speed effect")
            expect(speed.isFinite && speed <= 2.5, "Speed is always bounded")
            previousSpeed = speed
            previousIncrement = increment
        }
        expect(CodexActivityLevel(activeCount: Int.max).speedMultiplier <= 2.5, "Huge counts cannot overflow the speed cap")
        print("\(checks) Codex phase, avatar tier and speed checks passed")
    }
}
