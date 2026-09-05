import Foundation
import os

/// Combines local cumulative usage with a persisted daily baseline and optional model status.
@Observable
@MainActor
final class OmlxUsageService {
    private(set) var isAvailable = false
    private(set) var today: OmlxDailyUsage?
    private(set) var allTime: OmlxStats?
    private(set) var loadedModels: [OmlxModelStatus] = []
    private(set) var lastError: String?

    var referenceModelId: String {
        get {
            access(keyPath: \.referenceModelId)
            return UserDefaults.standard.string(forKey: "claudebar.omlxReferenceModel") ?? "claude-sonnet-5"
        }
        set {
            withMutation(keyPath: \.referenceModelId) {
                UserDefaults.standard.set(newValue, forKey: "claudebar.omlxReferenceModel")
            }
        }
    }

    var todayApiEquivalentCost: Double {
        let pricing = CostCalculator.pricing(for: referenceModelId)
        return today?.perModel.reduce(0) {
            $0 + OmlxDailyUsage.apiEquivalentCost(of: $1.usage, reference: pricing)
        } ?? 0
    }

    private struct Baseline: Codable {
        let date: String
        let stats: OmlxStats
    }

    private struct Settings: Decodable {
        let api_key: String?
        let port: Int?
    }

    private let omlxDirectory: URL
    private let baselineDirectory: URL
    private let session: URLSession
    private let now: () -> Date
    private let watcher = FileWatcher()
    private nonisolated let pollingTimer = ServiceTimer()
    private var isRefreshingModels = false
    private var baselineError: String? {
        didSet { lastError = baselineError ?? modelsError }
    }
    private var modelsError: String? {
        didSet { lastError = baselineError ?? modelsError }
    }

    init(
        omlxDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".omlx"),
        baselineDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBar"),
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init,
        disablePolling: Bool = false
    ) {
        self.omlxDirectory = omlxDirectory
        self.baselineDirectory = baselineDirectory
        self.session = session
        self.now = now
        reload()
        if !disablePolling {
            Task { [weak self] in await self?.refreshModels() }
            pollingTimer.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reload()
                    await self?.refreshModels()
                }
            }
        }
    }

    deinit {
        pollingTimer.invalidate()
    }

    func reload() {
        let statsURL = omlxDirectory.appendingPathComponent("stats.json")
        // Atomic replacement changes the file inode, so reattach after every read.
        defer {
            let path = FileManager.default.fileExists(atPath: statsURL.path) ? statsURL.path : omlxDirectory.path
            watcher.watch(path: path) { [weak self] in self?.reload() }
        }
        guard let data = try? Data(contentsOf: statsURL),
              let current = try? OmlxStats.decode(data) else {
            isAvailable = false
            today = nil
            allTime = nil
            return
        }

        baselineError = nil
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: now())
        let baselineURL = baselineDirectory.appendingPathComponent("omlx-baseline.json")
        let saved = (try? Data(contentsOf: baselineURL)).flatMap { try? JSONDecoder().decode(Baseline.self, from: $0) }
        let baseline: OmlxStats
        if let saved, saved.date == date {
            baseline = saved.stats
        } else {
            baseline = current
        }
        var delta = OmlxDailyUsage.delta(current: current, baseline: baseline)
        if saved?.date != date || delta.resetDetected {
            do {
                try FileManager.default.createDirectory(at: baselineDirectory, withIntermediateDirectories: true)
                try JSONEncoder().encode(Baseline(date: date, stats: current)).write(to: baselineURL, options: .atomic)
            } catch {
                baselineError = "Unable to save oMLX usage baseline"
            }
        }
        if delta.resetDetected {
            let zero = OmlxStats(totalPromptTokens: 0, totalCompletionTokens: 0, totalCachedTokens: 0,
                                 totalRequests: 0, totalPrefillDuration: 0, totalGenerationDuration: 0,
                                 perModel: [:])
            delta = OmlxDailyUsage.delta(current: current, baseline: zero)
            Log.omlx.info("oMLX usage counters reset; daily baseline replaced")
        }
        allTime = current
        today = delta
        isAvailable = true
    }

    func refreshModels() async {
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        defer { isRefreshingModels = false }
        guard let data = try? Data(contentsOf: omlxDirectory.appendingPathComponent("settings.json")),
              let settings = try? JSONDecoder().decode(Settings.self, from: data),
              let key = settings.api_key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            loadedModels = []
            modelsError = nil
            return
        }
        let port = settings.port ?? 8000
        guard (1...65535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)/v1/models/status") else {
            loadedModels = []
            modelsError = "Invalid oMLX server port"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                loadedModels = []
                modelsError = "Invalid oMLX model status response"
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                loadedModels = []
                modelsError = "HTTP \(http.statusCode)"
                return
            }
            loadedModels = try OmlxModelStatus.decodeList(data)
            modelsError = nil
        } catch {
            loadedModels = []
            modelsError = "Unable to load oMLX model status"
        }
    }
}
