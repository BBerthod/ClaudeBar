import XCTest
@testable import ClaudeBarLib

private final class CatalogURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class ModelCatalogServiceTests: XCTestCase {
    private func service(cacheData: Data? = nil) throws -> (ModelCatalogService, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("model-catalog.json")
        try cacheData?.write(to: file)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogURLProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock {
            session.invalidateAndCancel()
            try FileManager.default.removeItem(at: directory)
            await MainActor.run {
                _ = ModelCatalogService(cacheDirectory: directory, session: session, disablePolling: true)
                CatalogURLProtocol.handler = nil
            }
        }
        return (ModelCatalogService(cacheDirectory: directory, session: session, disablePolling: true), file)
    }
    private func response(_ status: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: ModelCatalogService.remoteURL, statusCode: status, httpVersion: nil, headerFields: headers)!
    }
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "litellm-sample", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    func testStartsFromBundledWhenNoCache() throws {
        let (service, _) = try service()
        XCTAssertEqual(service.source, .bundled)
        XCTAssertNotNil(service.catalog.entries["claude-opus-5"])
        XCTAssertNil(service.lastError)
    }
    func testLoadsCacheWhenPresent() throws {
        let entry = ModelCatalogEntry(id: "claude-cache-marker", provider: "anthropic", family: "opus", inputPerMTok: 7, outputPerMTok: 25, cacheReadPerMTok: 0.5, cacheWritePerMTok: 6.25, contextWindow: 123456)
        let catalog = ModelCatalog(generatedAt: Date(timeIntervalSince1970: 0), entries: [entry.id: entry])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let (service, _) = try service(cacheData: encoder.encode(catalog))
        XCTAssertEqual(service.source, .cache)
        XCTAssertEqual(service.catalog.entries[entry.id], entry)
        XCTAssertEqual(ModelCatalogService.current.entries[entry.id], entry)
    }
    func testCorruptCacheFallsBackToBundled() throws {
        let (service, _) = try service(cacheData: Data("not json".utf8))
        XCTAssertEqual(service.source, .bundled)
        XCTAssertNil(service.lastError)
    }
    func testRefreshWritesCacheAndPublishes() async throws {
        let data = try fixture()
        let ok = response(headers: ["ETag": "\"abc\""]); let unchanged = response(304)
        var count = 0
        CatalogURLProtocol.handler = { request in
            count += 1
            XCTAssertEqual(request.timeoutInterval, 10)
            if count == 1 { return (ok, data) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
            return (unchanged, Data())
        }
        let (service, file) = try service()
        await service.refresh()
        XCTAssertEqual(service.source, .remote)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(ModelCatalog.self, from: Data(contentsOf: file)).entries, service.catalog.entries)
        XCTAssertEqual(ModelCatalogService.current.entries, service.catalog.entries)
        let date = service.lastUpdated
        await service.refresh()
        XCTAssertEqual(count, 2)
        XCTAssertEqual(service.lastUpdated, date)
        XCTAssertEqual(service.source, .remote)
        XCTAssertNil(service.lastError)
    }
    func testRefreshFailureKeepsCatalog() async throws {
        let failure = response(500)
        CatalogURLProtocol.handler = { _ in (failure, Data()) }
        let (service, _) = try service()
        let entries = service.catalog.entries
        await service.refresh()
        XCTAssertEqual(service.catalog.entries, entries)
        XCTAssertEqual(service.source, .bundled)
        XCTAssertEqual(service.lastError, "HTTP 500")
    }
    func testConcurrentRefreshesShareOneRequest() async throws {
        let data = try fixture(); let ok = response()
        let started = expectation(description: "request started")
        let release = DispatchSemaphore(value: 0)
        var count = 0
        CatalogURLProtocol.handler = { _ in
            count += 1; started.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return (ok, data)
        }
        let (service, _) = try service()
        let first = Task { await service.refresh() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await service.refresh() }
        await Task.yield()
        release.signal()
        await first.value; await second.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(service.source, .remote)
    }
    func testNoteResolutionFiresOncePerModel() throws {
        let (service, _) = try service()
        var ids: [String] = []
        service.onNewModelDetected = { id, _ in ids.append(id) }
        let estimated = try XCTUnwrap(service.catalog.resolve("claude-opus-6"))
        service.noteResolution(estimated, for: "claude-opus-6")
        service.noteResolution(estimated, for: "claude-opus-6")
        service.noteResolution(try XCTUnwrap(service.catalog.resolve("claude-opus-5")), for: "claude-opus-5")
        XCTAssertEqual(ids, ["claude-opus-6"])
        XCTAssertEqual(service.unknownModelsSeen, ["claude-opus-6": "claude-opus-5"])
    }
}

extension ModelCatalogServiceTests {
    func testCostAndContextUseCurrentCatalog() throws {
        let entry = ModelCatalogEntry(id: "claude-opus-99", provider: "anthropic", family: "opus", inputPerMTok: 7, outputPerMTok: 31, cacheReadPerMTok: 0.7, cacheWritePerMTok: 8.75, contextWindow: 345678)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let (service, _) = try service(cacheData: encoder.encode(ModelCatalog(generatedAt: Date(), entries: [entry.id: entry])))
        XCTAssertEqual(service.source, .cache)
        let price = CostCalculator.pricing(for: entry.id)
        XCTAssertEqual(price.inputPerMTok, 7)
        XCTAssertEqual(price.outputPerMTok, 31)
        XCTAssertEqual(price.cacheReadPerMTok, 0.7)
        XCTAssertEqual(price.cacheWritePerMTok, 8.75)
        XCTAssertEqual(SessionService.contextWindow(forModel: entry.id), 345678)
        XCTAssertFalse(CostCalculator.isEstimated(entry.id))
        XCTAssertTrue(CostCalculator.isEstimated("claude-opus-100"))
        XCTAssertTrue(CostCalculator.isEstimated("unrecognized-family"))
        XCTAssertEqual(CostCalculator.pricing(for: "unrecognized-family").inputPerMTok, 5)
    }
}

extension ModelCatalogServiceTests {
    func testNoteModelsIgnoresKnownAndSynthetic() throws {
        let (service, _) = try service()
        var ids: [String] = []
        service.onNewModelDetected = { id, _ in ids.append(id) }
        service.noteModels(["claude-opus-5", "<synthetic>", "unknown", "", "claude-opus-6"])
        service.noteModels(["claude-opus-6"])
        XCTAssertEqual(ids, ["claude-opus-6"])
    }
    func testNoteModelsEstimatesUnknownFamilyFromOpus5() throws {
        let (service, _) = try service()
        service.noteModels(["llama-new"])
        XCTAssertEqual(service.unknownModelsSeen["llama-new"], "claude-opus-5")
    }
    func testLiveScanReportsModelsToCatalog() throws {
        let (catalog, _) = try service()
        let live = LiveStatsService(modelCatalogService: catalog)
        var snapshot = LiveStatsSnapshot()
        snapshot.tokensByModel = [("claude-opus-6", 12)]
        live.apply(snapshot)
        XCTAssertEqual(catalog.unknownModelsSeen["claude-opus-6"], "claude-opus-5")
    }
    func testImporterCollapsesCloudDeploymentAliases() throws {
        let canonical: [String: Any] = ["litellm_provider": "anthropic", "input_cost_per_token": 5e-6, "output_cost_per_token": 25e-6]
        let cloud: [String: Any] = ["litellm_provider": "bedrock", "input_cost_per_token": 6e-6, "output_cost_per_token": 30e-6]
        let catalog = try ModelCatalogImporter.normalise(litellm: ["claude-opus-5": canonical, "databricks-claude-opus-5": cloud, "apac.anthropic.claude-opus-5-20260905-v1:0": cloud], generatedAt: Date())
        XCTAssertEqual(catalog.entries.count, 1)
        XCTAssertEqual(catalog.resolve("claude-opus-6")?.basedOn, "claude-opus-5")
        XCTAssertEqual(catalog.entries["claude-opus-5"]?.inputPerMTok, 5)
    }
}

extension ModelCatalogServiceTests {
    private func transcriptDirectory(daysAgo: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = directory.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let object: [String: Any] = ["type": "assistant", "cwd": "/tmp/catalog-project", "timestamp": formatter.string(from: date), "message": ["id": "message", "model": "claude-opus-6", "usage": ["input_tokens": 12]]]
        try JSONSerialization.data(withJSONObject: object).write(to: project.appendingPathComponent("session.jsonl"))
        return directory
    }
    func testProjectScanCollectsModelIDs() throws {
        let directory = try transcriptDirectory(daysAgo: 1)
        let result = ProjectService.scanWithModels(dirs: [directory.path])
        XCTAssertEqual(result.models, ["claude-opus-6"])
        XCTAssertEqual(result.projects.count, 1)
        let (catalog, _) = try service()
        catalog.noteModels(result.models)
        XCTAssertEqual(catalog.unknownModelsSeen["claude-opus-6"], "claude-opus-5")
    }
    func testYearlyScanCollectsModelsOlderThanThirtyDays() throws {
        let directory = try transcriptDirectory(daysAgo: 60)
        let result = YearlyHistoryService.scanWithModels(projectsDirs: [directory.path])
        XCTAssertEqual(result.models, ["claude-opus-6"])
        XCTAssertTrue(result.modelBreakdown.isEmpty)
        let (catalog, _) = try service()
        catalog.noteModels(result.models)
        XCTAssertEqual(catalog.unknownModelsSeen["claude-opus-6"], "claude-opus-5")
    }
}
