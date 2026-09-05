import Foundation

@Observable @MainActor
final class ModelCatalogService {
    enum Source: String, Sendable { case bundled, cache, remote }
    private(set) var catalog: ModelCatalog
    private(set) var source: Source
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    private(set) var unknownModelsSeen: [String: String] = [:]
    var onNewModelDetected: ((String, String) -> Void)?

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    static let refreshInterval: TimeInterval = 24 * 3600
    /// Below this the remote payload is treated as broken (the real file has hundreds of entries).
    private let minimumRemoteEntries: Int
    private let cacheURL: URL
    /// Ids already reported to the user — persisted so a restart does not re-notify.
    private let seenModelsURL: URL
    private let session: URLSession
    private var etag: String?
    private var refreshTask: Task<Void, Never>?
    private nonisolated let timer = ServiceTimer()

    /// Synchronous snapshots are available before any service is instantiated.
    nonisolated static var current: ModelCatalog { Holder.shared.catalog }

    private final class Holder: @unchecked Sendable {
        static let shared = Holder()
        private let lock = NSLock()
        private var storedCatalog = (try? ModelCatalog.bundled())
            ?? ModelCatalog(generatedAt: .distantPast, entries: [:])
        var catalog: ModelCatalog {
            get { lock.lock(); defer { lock.unlock() }; return storedCatalog }
            set { lock.lock(); defer { lock.unlock() }; storedCatalog = newValue }
        }
    }

    init(
        cacheDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBar", isDirectory: true),
        session: URLSession = .shared,
        disablePolling: Bool = false,
        minimumRemoteEntries: Int = 50
    ) {
        self.minimumRemoteEntries = minimumRemoteEntries
        self.cacheURL = cacheDirectory.appendingPathComponent("model-catalog.json")
        self.seenModelsURL = cacheDirectory.appendingPathComponent("unknown-models.json")
        self.session = session
        if let data = try? Data(contentsOf: seenModelsURL),
           let seen = try? JSONDecoder().decode([String: String].self, from: data) {
            unknownModelsSeen = seen
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? decoder.decode(ModelCatalog.self, from: data) {
            catalog = cached
            source = .cache
        } else {
            catalog = (try? ModelCatalog.bundled()) ?? ModelCatalog(generatedAt: .distantPast, entries: [:])
            source = .bundled
        }
        lastUpdated = catalog.generatedAt
        Holder.shared.catalog = catalog
        if !disablePolling {
            Task { [weak self] in await self?.refresh() }
            timer.timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
        }
    }

    deinit { timer.invalidate() }

    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        isRefreshing = true
        defer { isRefreshing = false }
        let task = Task { await fetchCatalog() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func fetchCatalog() async {
        do {
            var request = URLRequest(url: Self.remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 304 { lastError = nil; return }
            guard response.statusCode == 200 else {
                lastError = "HTTP \(response.statusCode)"
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }
            let remote = try ModelCatalogImporter.normalise(litellm: json, generatedAt: Date())
            // A truncated or partial payload must never wipe reliable prices: refuse implausibly
            // small catalogs and always keep bundled entries the remote file no longer lists.
            let bundled = (try? ModelCatalog.bundled())?.entries ?? [:]
            guard remote.entries.count >= minimumRemoteEntries else {
                throw URLError(.cannotParseResponse)
            }
            let updated = ModelCatalog(generatedAt: remote.generatedAt,
                                       entries: bundled.merging(remote.entries) { _, fresh in fresh })
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encoded = try encoder.encode(updated)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: cacheURL, options: .atomic)
            catalog = updated
            Holder.shared.catalog = updated
            source = .remote
            lastUpdated = updated.generatedAt
            etag = response.value(forHTTPHeaderField: "ETag")
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    func noteModels(_ ids: some Sequence<String>) {
        for id in Set(ids) where !id.isEmpty && id != "<synthetic>" && id != "unknown" {
            if let resolution = catalog.resolve(id) {
                noteResolution(resolution, for: id)
            } else if let opus = catalog.entries["claude-opus-5"]
                ?? (try? ModelCatalog.bundled())?.entries["claude-opus-5"] {
                noteResolution(ModelCatalog.Resolution(entry: opus, isEstimated: true, basedOn: opus.id), for: id)
            }
        }
    }

    func noteResolution(_ r: ModelCatalog.Resolution, for id: String) {
        guard r.isEstimated, let basedOn = r.basedOn, unknownModelsSeen[id] == nil,
              !id.isEmpty, id != "<synthetic>", id != "unknown" else { return }
        unknownModelsSeen[id] = basedOn
        if let data = try? JSONEncoder().encode(unknownModelsSeen) {
            try? FileManager.default.createDirectory(at: seenModelsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: seenModelsURL, options: .atomic)
        }
        onNewModelDetected?(id, basedOn)
    }
}
