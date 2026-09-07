import Combine
import Foundation

@MainActor
final class CodexActivityManager: ObservableObject {
    static let shared = CodexActivityManager()

    @Published private(set) var phase: CodexActivityPhase = .offline
    var isActive: Bool { phase == .active }
    var statusText: String { phase.statusText }

    private var monitoringTask: Task<Void, Never>?
    private let session: URLSession
    private let endpoint = URL(string: "http://127.0.0.1:48731/activity")!

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        phase = .offline
    }

    private func refresh() async {
        do {
            let (data, response) = try await session.data(from: endpoint)
            guard !Task.isCancelled else { return }
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200, data.count <= 4096 else {
                phase = .offline
                return
            }
            phase = try JSONDecoder().decode(CodexActivitySnapshot.self, from: data)
                .validatedPhase(at: Date())
        } catch {
            guard !Task.isCancelled else { return }
            // A disconnected bird stays still instead of pretending to be busy.
            phase = .offline
        }
    }
}
