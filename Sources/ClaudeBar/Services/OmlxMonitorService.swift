import Foundation
import os

/// Polls `GET /health` on the local oMLX inference server every 30 seconds.
/// No authentication required — the endpoint is public on localhost.
@Observable
@MainActor
final class OmlxMonitorService {

    // MARK: - StateSnapshot (testable pure value type)

    /// Computed state from one /health response. Pure value type for testability.
    struct StateSnapshot: Sendable {
        let isOnline: Bool
        let defaultModel: String?
        let modelCount: Int
        let loadedCount: Int
        let maxMemoryGB: Double
        let usedMemoryGB: Double

        init(from response: OmlxHealthResponse) {
            isOnline = response.isHealthy
            defaultModel = response.defaultModel
            modelCount = response.enginePool?.modelCount ?? 0
            loadedCount = response.enginePool?.loadedCount ?? 0
            maxMemoryGB = response.maxMemoryGB
            usedMemoryGB = response.usedMemoryGB
        }

        /// Offline default state.
        init() {
            isOnline = false
            defaultModel = nil
            modelCount = 0
            loadedCount = 0
            maxMemoryGB = 0
            usedMemoryGB = 0
        }

        /// E.g. "16.0 / 32.0 GB"
        var memoryLabel: String {
            String(format: "%.1f / %.1f GB", usedMemoryGB, maxMemoryGB)
        }
    }

    // MARK: - Published state

    private(set) var state = StateSnapshot()
    private(set) var lastChecked: Date?
    private(set) var lastError: String?

    // MARK: - Convenience forwarding (used by views)

    var isOnline: Bool { state.isOnline }
    var defaultModel: String? { state.defaultModel }
    var modelCount: Int { state.modelCount }
    var loadedCount: Int { state.loadedCount }
    var maxMemoryGB: Double { state.maxMemoryGB }
    var usedMemoryGB: Double { state.usedMemoryGB }
    var memoryLabel: String { state.memoryLabel }

    let endpoint: String

    private var pollingTimer: Timer?

    // MARK: - Init

    init(endpoint: String = "http://127.0.0.1:8000", skipInitialCheck: Bool = false) {
        self.endpoint = endpoint
        if !skipInitialCheck {
            Task { await checkHealth() }
            startPolling()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.checkHealth() }
        }
    }

    // MARK: - Health check

    func checkHealth() async {
        guard let url = URL(string: "\(endpoint)/health") else {
            lastError = "Invalid endpoint URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                state = StateSnapshot()
                lastError = "HTTP error"
                return
            }
            let decoded = try JSONDecoder().decode(OmlxHealthResponse.self, from: data)
            state = StateSnapshot(from: decoded)
            lastError = nil
            lastChecked = Date()
            Log.omlx.debug("oMLX health OK — model: \(decoded.defaultModel ?? "none", privacy: .public)")
        } catch {
            state = StateSnapshot()
            lastError = error.localizedDescription.prefix(60).description
            Log.omlx.warning("oMLX health check failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
