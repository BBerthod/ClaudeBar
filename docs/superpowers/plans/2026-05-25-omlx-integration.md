# oMLX Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Intégrer oMLX (serveur LLM local Apple Silicon) dans ClaudeBar : état de santé en temps réel, comptage des appels quotidiens depuis les JSONL, et affichage dans DashboardView + AnalyticsView.

**Architecture:** Nouveau `OmlxMonitorService` (@Observable, poll HTTP `/health` toutes les 30 s) pour les stats runtime. Extension de `ProviderUsageService` pour compter les appels `mcp__omlx-delegate__delegate_to_omlx` dans les JSONL Claude Code (même pattern que `LiveStatsService`). UI : provider pill dans DashboardView + GroupBox dans `systemPanel` de AnalyticsView.

**Tech Stack:** Swift 5.9, SwiftUI, Observation framework (`@Observable`), URLSession, Foundation (JSONL parsing), XCTest.

---

## Résultat des tests préliminaires

`curl http://localhost:8000/health` retourne (sans auth) :
```json
{
  "status": "healthy",
  "default_model": "Qwen3.6-27B",
  "engine_pool": {
    "model_count": 2,
    "loaded_count": 0,
    "max_model_memory": 115964116992,
    "current_model_memory": 0
  },
  "mcp": null
}
```

`/v1/models` → 401 (API key requise — skip pour MVP)  
`/metrics` → 404 (non implémenté)

**Seul `/health` est utilisé** (no auth required).

---

## Fichiers

### Créer
| Fichier | Responsabilité |
|---------|---------------|
| `Sources/ClaudeBar/Models/OmlxHealthResponse.swift` | Codable pour la réponse `/health` |
| `Sources/ClaudeBar/Services/OmlxMonitorService.swift` | Poll HTTP `/health` toutes les 30 s |
| `Tests/ClaudeBarTests/OmlxHealthResponseTests.swift` | Tests décodage JSON |
| `Tests/ClaudeBarTests/OmlxMonitorServiceTests.swift` | Tests parsing/computed props |
| `Tests/ClaudeBarTests/ProviderUsageServiceOmlxTests.swift` | Tests countOmlxCallsInLines |

### Modifier
| Fichier | Changement |
|---------|-----------|
| `Sources/ClaudeBar/Services/ProviderUsageService.swift` | Ajouter omlxCallsToday, isOmlxActive, refreshOmlx(), countOmlxCallsInLines() |
| `Sources/ClaudeBar/AppDelegate.swift` | Ajouter OmlxMonitorService, passer claudeDir à ProviderUsageService |
| `Sources/ClaudeBar/Views/DashboardView.swift` | @Environment OmlxMonitorService, provider pill oMLX |
| `Sources/ClaudeBar/Views/AnalyticsView.swift` | @Environment OmlxMonitorService, GroupBox systemPanel |

---

## Task 1 — OmlxHealthResponse model

**Files:**
- Create: `Sources/ClaudeBar/Models/OmlxHealthResponse.swift`
- Test: `Tests/ClaudeBarTests/OmlxHealthResponseTests.swift`

- [ ] **Step 1.1 : Écrire les tests de décodage (TDD — ils doivent échouer)**

```swift
// Tests/ClaudeBarTests/OmlxHealthResponseTests.swift
import XCTest
@testable import ClaudeBarLib

final class OmlxHealthResponseTests: XCTestCase {

    private let fullJSON = """
    {
      "status": "healthy",
      "default_model": "Qwen3.6-27B",
      "engine_pool": {
        "model_count": 2,
        "loaded_count": 0,
        "max_model_memory": 115964116992,
        "current_model_memory": 0
      },
      "mcp": null
    }
    """.data(using: .utf8)!

    func testDecodesStatus() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.status, "healthy")
    }

    func testIsHealthyTrueWhenStatusHealthy() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertTrue(r.isHealthy)
    }

    func testIsHealthyFalseWhenStatusNotHealthy() throws {
        let json = #"{"status":"degraded","default_model":null,"engine_pool":null,"mcp":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: json)
        XCTAssertFalse(r.isHealthy)
    }

    func testDecodesDefaultModel() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.defaultModel, "Qwen3.6-27B")
    }

    func testDecodesEnginePool() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.enginePool?.modelCount, 2)
        XCTAssertEqual(r.enginePool?.loadedCount, 0)
        XCTAssertEqual(r.enginePool?.maxModelMemory, 115964116992)
        XCTAssertEqual(r.enginePool?.currentModelMemory, 0)
    }

    func testMaxMemoryGB() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        // 115964116992 / 1073741824 ≈ 108.0
        XCTAssertEqual(r.maxMemoryGB, 115964116992.0 / 1073741824.0, accuracy: 0.01)
    }

    func testUsedMemoryGBWhenZero() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.usedMemoryGB, 0.0, accuracy: 0.01)
    }

    func testMinimalJSONWithoutEnginePool() throws {
        let json = #"{"status":"healthy","default_model":null,"engine_pool":null,"mcp":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: json)
        XCTAssertTrue(r.isHealthy)
        XCTAssertNil(r.enginePool)
        XCTAssertEqual(r.maxMemoryGB, 0.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 1.2 : Vérifier que les tests échouent**

```bash
cd /Users/billyberthod/Dev/suissegrele/ClaudeBar
swift test --filter OmlxHealthResponseTests 2>&1 | tail -10
```
Expected: `error: no such module 'ClaudeBarLib'` ou `error: cannot find type 'OmlxHealthResponse'`

- [ ] **Step 1.3 : Créer le modèle**

```swift
// Sources/ClaudeBar/Models/OmlxHealthResponse.swift
import Foundation

/// Response from `GET http://localhost:8000/health` (no auth required).
/// Example: {"status":"healthy","default_model":"Qwen3.6-27B",
///           "engine_pool":{"model_count":2,"loaded_count":0,
///                          "max_model_memory":115964116992,"current_model_memory":0},"mcp":null}
struct OmlxHealthResponse: Codable, Sendable {
    let status: String
    let defaultModel: String?
    let enginePool: EnginePool?

    struct EnginePool: Codable, Sendable {
        let modelCount: Int
        let loadedCount: Int
        let maxModelMemory: Int64
        let currentModelMemory: Int64

        enum CodingKeys: String, CodingKey {
            case modelCount = "model_count"
            case loadedCount = "loaded_count"
            case maxModelMemory = "max_model_memory"
            case currentModelMemory = "current_model_memory"
        }
    }

    /// True when `status == "healthy"`.
    var isHealthy: Bool { status == "healthy" }

    /// Max engine memory in GB (0 if no engine_pool).
    var maxMemoryGB: Double {
        Double(enginePool?.maxModelMemory ?? 0) / 1_073_741_824
    }

    /// Current memory used in GB (0 if no engine_pool).
    var usedMemoryGB: Double {
        Double(enginePool?.currentModelMemory ?? 0) / 1_073_741_824
    }

    enum CodingKeys: String, CodingKey {
        case status
        case defaultModel = "default_model"
        case enginePool = "engine_pool"
    }
}
```

- [ ] **Step 1.4 : Tests passent**

```bash
swift test --filter OmlxHealthResponseTests 2>&1 | tail -5
```
Expected: `Test Suite 'OmlxHealthResponseTests' passed`

- [ ] **Step 1.5 : Commit**

```bash
git add Sources/ClaudeBar/Models/OmlxHealthResponse.swift Tests/ClaudeBarTests/OmlxHealthResponseTests.swift
git commit -m "feat(omlx): add OmlxHealthResponse Codable model."
```

---

## Task 2 — OmlxMonitorService

**Files:**
- Create: `Sources/ClaudeBar/Services/OmlxMonitorService.swift`
- Test: `Tests/ClaudeBarTests/OmlxMonitorServiceTests.swift`

- [ ] **Step 2.1 : Écrire les tests des computed props (TDD)**

```swift
// Tests/ClaudeBarTests/OmlxMonitorServiceTests.swift
import XCTest
@testable import ClaudeBarLib

final class OmlxMonitorServiceTests: XCTestCase {

    // MARK: - applyHealth

    /// Test the static helper that maps a decoded response to service state.
    /// The real service calls this on the main actor — we test the pure mapping logic.

    func testApplyHealthSetsIsOnlineTrue() {
        let pool = OmlxHealthResponse.EnginePool(
            modelCount: 2, loadedCount: 1,
            maxModelMemory: 115964116992, currentModelMemory: 10737418240
        )
        let r = OmlxHealthResponse(status: "healthy", defaultModel: "Qwen3.6-27B", enginePool: pool)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertTrue(state.isOnline)
        XCTAssertEqual(state.defaultModel, "Qwen3.6-27B")
        XCTAssertEqual(state.modelCount, 2)
        XCTAssertEqual(state.loadedCount, 1)
        XCTAssertEqual(state.maxMemoryGB, 115964116992.0 / 1_073_741_824, accuracy: 0.01)
        XCTAssertEqual(state.usedMemoryGB, 10737418240.0 / 1_073_741_824, accuracy: 0.01)
    }

    func testApplyHealthSetsIsOnlineFalseWhenDegraded() {
        let r = OmlxHealthResponse(status: "degraded", defaultModel: nil, enginePool: nil)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertFalse(state.isOnline)
        XCTAssertNil(state.defaultModel)
        XCTAssertEqual(state.modelCount, 0)
    }

    func testMemoryUsageLabel_zeroUsed() {
        let pool = OmlxHealthResponse.EnginePool(
            modelCount: 1, loadedCount: 0,
            maxModelMemory: 115964116992, currentModelMemory: 0
        )
        let r = OmlxHealthResponse(status: "healthy", defaultModel: "Qwen3", enginePool: pool)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertEqual(state.memoryLabel, "0.0 / 108.0 GB")
    }

    func testMemoryUsageLabel_partialUsed() {
        let pool = OmlxHealthResponse.EnginePool(
            modelCount: 1, loadedCount: 1,
            maxModelMemory: 34359738368, currentModelMemory: 17179869184  // 16 / 32 GB
        )
        let r = OmlxHealthResponse(status: "healthy", defaultModel: "Llama", enginePool: pool)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertEqual(state.memoryLabel, "16.0 / 32.0 GB")
    }

    func testEndpointDefault() {
        let svc = OmlxMonitorService()
        XCTAssertEqual(svc.endpoint, "http://127.0.0.1:8000")
    }
}
```

- [ ] **Step 2.2 : Vérifier que les tests échouent**

```bash
swift test --filter OmlxMonitorServiceTests 2>&1 | tail -10
```
Expected: `error: cannot find type 'OmlxMonitorService'`

- [ ] **Step 2.3 : Créer le service**

```swift
// Sources/ClaudeBar/Services/OmlxMonitorService.swift
import Foundation
import os

/// Polls `GET /health` on the local oMLX inference server every 30 seconds.
/// No authentication required — the endpoint is public on localhost.
@Observable
@MainActor
final class OmlxMonitorService {

    // MARK: - Snapshot (testable value type)

    /// Pure value type holding the computed state from one /health response.
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

        init() {
            isOnline = false; defaultModel = nil; modelCount = 0
            loadedCount = 0; maxMemoryGB = 0; usedMemoryGB = 0
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

    init(endpoint: String = "http://127.0.0.1:8000") {
        self.endpoint = endpoint
        Task { await checkHealth() }
        startPolling()
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
```

- [ ] **Step 2.4 : Ajouter le canal de log oMLX dans Log.swift**

Chercher le fichier de logs :
```bash
grep -rn "Log\." /Users/billyberthod/Dev/suissegrele/ClaudeBar/Sources/ClaudeBar/ | grep "let usage\|let stats\|static let\|extension Log" | head -10
```

Ouvrir le fichier trouvé (ex : `Sources/ClaudeBar/Helpers/Log.swift` ou similaire) et ajouter :
```swift
static let omlx = Logger(subsystem: subsystem, category: "omlx")
```
… à la suite des autres canaux existants (même pattern exact).

- [ ] **Step 2.5 : Tests passent**

```bash
swift test --filter OmlxMonitorServiceTests 2>&1 | tail -5
```
Expected: `Test Suite 'OmlxMonitorServiceTests' passed`

- [ ] **Step 2.6 : Commit**

```bash
git add Sources/ClaudeBar/Services/OmlxMonitorService.swift \
        Tests/ClaudeBarTests/OmlxMonitorServiceTests.swift
git commit -m "feat(omlx): add OmlxMonitorService — polls /health every 30s."
```

---

## Task 3 — Extend ProviderUsageService : oMLX JSONL tracking

**Files:**
- Modify: `Sources/ClaudeBar/Services/ProviderUsageService.swift`
- Test: `Tests/ClaudeBarTests/ProviderUsageServiceOmlxTests.swift`

**Contexte :** Les JSONL Claude Code (dans `~/.claude/projects/**/*.jsonl`) contiennent des lignes de type `{"type":"assistant","message":{"id":"msg_...","content":[{"type":"tool_use","name":"mcp__omlx-delegate__delegate_to_omlx","input":{...}}],...}}`. On compte les message IDs uniques qui contiennent un tel appel.

- [ ] **Step 3.1 : Écrire les tests du parser statique (TDD)**

```swift
// Tests/ClaudeBarTests/ProviderUsageServiceOmlxTests.swift
import XCTest
@testable import ClaudeBarLib

final class ProviderUsageServiceOmlxTests: XCTestCase {

    // Helper : construit une ligne JSONL d'assistant avec un tool_use
    private func assistantLine(msgID: String, toolName: String) -> String {
        """
        {"type":"assistant","message":{"id":"\(msgID)","model":"claude-opus-4-7","content":[{"type":"tool_use","id":"tu_1","name":"\(toolName)","input":{"task":"do stuff"}}],"role":"assistant","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
    }

    private func userLine() -> String {
        """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}
        """
    }

    func testEmptyLinesReturnsZero() {
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([]), 0)
    }

    func testNonAssistantLineIgnored() {
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([userLine()]), 0)
    }

    func testOmlxToolCallCountedOnce() {
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line]), 1)
    }

    func testDuplicateMessageIDDeduplicatedToOne() {
        // Two streaming chunks for the same message → same ID → count = 1
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line, line]), 1)
    }

    func testTwoDifferentMessageIDsCountedAsTwoSeparate() {
        let line1 = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        let line2 = assistantLine(msgID: "msg_002", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line1, line2]), 2)
    }

    func testNonOmlxToolCallNotCounted() {
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__codex__codex")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line]), 0)
    }

    func testOmlxEmbedToolAlsoCounted() {
        // embed_text is also an oMLX tool
        let line = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__embed_text")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([line]), 1)
    }

    func testMixedToolsOnlyOmlxCounted() {
        let omlxLine = assistantLine(msgID: "msg_001", toolName: "mcp__omlx-delegate__delegate_to_omlx")
        let codexLine = assistantLine(msgID: "msg_002", toolName: "mcp__codex__codex")
        let geminiLine = assistantLine(msgID: "msg_003", toolName: "mcp__gemini-delegate__delegate_to_gemini")
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines([omlxLine, codexLine, geminiLine]), 1)
    }

    func testMalformedJSONIgnored() {
        XCTAssertEqual(ProviderUsageService.countOmlxCallsInLines(["not json at all", "{}"]), 0)
    }
}
```

- [ ] **Step 3.2 : Vérifier que les tests échouent**

```bash
swift test --filter ProviderUsageServiceOmlxTests 2>&1 | tail -10
```
Expected: `error: type 'ProviderUsageService' has no member 'countOmlxCallsInLines'`

- [ ] **Step 3.3 : Ajouter le paramètre claudeDir à ProviderUsageService.init()**

Localiser la déclaration `init()` dans `Sources/ClaudeBar/Services/ProviderUsageService.swift` et remplacer :
```swift
init() {
    Task { await refresh() }
    startPolling()
}
```
par :
```swift
private let projectsDir: String

init(claudeDir: String = NSString(string: "~/.claude").expandingTildeInPath) {
    self.projectsDir = claudeDir + "/projects"
    Task { await refresh() }
    startPolling()
}
```

- [ ] **Step 3.4 : Ajouter les propriétés et méthodes oMLX**

Ajouter dans la section `// MARK: - Published state` (après les propriétés Gemini existantes) :
```swift
private(set) var omlxCallsToday: Int = 0
private(set) var isOmlxActive: Bool = false
```

Ajouter la méthode de refresh dans la section `// MARK: - Refresh` après l'appel `refreshGemini()` dans `refresh()` :
```swift
// Dans func refresh() async, ajouter à la fin :
await refreshOmlx()
```

Ajouter la méthode statique nonisolated + la méthode de refresh — insérer après la section Gemini :
```swift
// MARK: - oMLX

/// Scans today's JSONL session files for tool_use blocks calling any oMLX tool.
/// Returns the count of distinct message IDs that contain at least one oMLX tool call.
/// `nonisolated static` for testability — no actor boundary crossing.
nonisolated static func countOmlxCallsInLines(_ lines: [String]) -> Int {
    var messageIDsWithOmlx: Set<String> = []

    for line in lines {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "assistant",
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]],
              let msgID = message["id"] as? String else { continue }

        let hasOmlx = content.contains { block in
            guard (block["type"] as? String) == "tool_use",
                  let name = block["name"] as? String else { return false }
            return name.contains("omlx")
        }

        if hasOmlx {
            messageIDsWithOmlx.insert(msgID)
        }
    }
    return messageIDsWithOmlx.count
}

private func refreshOmlx() async {
    let projectsDir = self.projectsDir
    let fm = FileManager.default
    let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

    let count = await Task.detached(priority: .utility) {
        var allLines: [String] = []

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
            return 0
        }

        for dir in projectDirs {
            let dirPath = projectsDir + "/" + dir
            for basePath in [dirPath, dirPath + "/subagents"] {
                guard let files = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
                for file in files where file.hasSuffix(".jsonl") {
                    let path = basePath + "/" + file
                    guard let attrs = try? fm.attributesOfItem(atPath: path),
                          let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
                          mtime >= todayStart else { continue }
                    guard let data = fm.contents(atPath: path),
                          let content = String(data: data, encoding: .utf8) else { continue }
                    allLines.append(contentsOf: content.split(separator: "\n").map(String.init))
                }
            }
        }

        return ProviderUsageService.countOmlxCallsInLines(allLines)
    }.value

    omlxCallsToday = count
    isOmlxActive = count > 0
}
```

- [ ] **Step 3.5 : Tests passent**

```bash
swift test --filter ProviderUsageServiceOmlxTests 2>&1 | tail -5
```
Expected: `Test Suite 'ProviderUsageServiceOmlxTests' passed`

- [ ] **Step 3.6 : Commit**

```bash
git add Sources/ClaudeBar/Services/ProviderUsageService.swift \
        Tests/ClaudeBarTests/ProviderUsageServiceOmlxTests.swift
git commit -m "feat(omlx): add oMLX JSONL usage tracking to ProviderUsageService."
```

---

## Task 4 — Câblage AppDelegate

**Files:**
- Modify: `Sources/ClaudeBar/AppDelegate.swift`

- [ ] **Step 4.1 : Déclarer OmlxMonitorService dans AppDelegate**

Ouvrir `Sources/ClaudeBar/AppDelegate.swift`. Localiser la ligne :
```swift
let updateCheckService = UpdateCheckService()
```
Ajouter immédiatement après :
```swift
let omlxMonitorService = OmlxMonitorService()
```

- [ ] **Step 4.2 : Mettre à jour ProviderUsageService pour lui passer le claudeDir**

Dans AppDelegate, localiser :
```swift
let providerUsageService = ProviderUsageService()
```
Remplacer par :
```swift
lazy var providerUsageService: ProviderUsageService = ProviderUsageService(
    claudeDir: NSString(string: AppDelegate.claudeDir).expandingTildeInPath
)
```

- [ ] **Step 4.3 : Injecter OmlxMonitorService dans l'environnement SwiftUI**

Localiser le bloc `.environment(updateCheckService)` dans la construction du ContentView (vers la ligne 152). Ajouter après :
```swift
.environment(omlxMonitorService)
```

- [ ] **Step 4.4 : Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!` (zéro erreur)

- [ ] **Step 4.5 : Commit**

```bash
git add Sources/ClaudeBar/AppDelegate.swift
git commit -m "feat(omlx): wire OmlxMonitorService into AppDelegate and SwiftUI environment."
```

---

## Task 5 — DashboardView : provider pill oMLX

**Files:**
- Modify: `Sources/ClaudeBar/Views/DashboardView.swift`

**Contexte :** Dans DashboardView, `var providers: [ProviderInfo]` construit les pills Claude/Gemini/Codex (lignes 73–117). Il faut ajouter oMLX.

- [ ] **Step 5.1 : Ajouter @Environment pour OmlxMonitorService**

Localiser dans DashboardView les déclarations `@Environment` (lignes 11–18). Ajouter après `@Environment(McpHealthService.self)` :
```swift
@Environment(OmlxMonitorService.self) private var omlxMonitorService
```

- [ ] **Step 5.2 : Ajouter le ProviderInfo oMLX dans la computed var providers**

Localiser la ligne `return [claudeProvider, geminiProvider, codexProvider]` (environ ligne 117). Remplacer par :

```swift
let hasOmlxMcp = mcpHealthService.servers.contains {
    $0.name.lowercased().contains("omlx")
}
let omlxProvider = ProviderInfo(
    name: "oMLX",
    icon: "cpu.fill",
    isConfigured: omlxMonitorService.isOnline || hasOmlxMcp,
    totalTokens: nil,
    estimatedCost: nil,
    details: omlxMonitorService.isOnline
        ? omlxMonitorService.defaultModel
        : (hasOmlxMcp ? "Offline" : nil),
    sessionCount: providerUsageService.omlxCallsToday > 0
        ? providerUsageService.omlxCallsToday
        : nil,
    contextLimitHits: nil
)
return [claudeProvider, geminiProvider, codexProvider, omlxProvider]
```

- [ ] **Step 5.3 : Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5.4 : Commit**

```bash
git add Sources/ClaudeBar/Views/DashboardView.swift
git commit -m "feat(omlx): add oMLX provider pill to DashboardView."
```

---

## Task 6 — AnalyticsView : GroupBox oMLX dans systemPanel

**Files:**
- Modify: `Sources/ClaudeBar/Views/AnalyticsView.swift`

**Contexte :** `systemPanel` est dans AnalyticsView. Le GroupBox "MCP Servers" se termine vers la ligne 1576 (`.padding(.horizontal)`). On insère le GroupBox oMLX juste après, avant "Quick Actions".

- [ ] **Step 6.1 : Ajouter @Environment pour OmlxMonitorService**

Localiser les déclarations `@Environment` dans AnalyticsView (lignes 26–32). Ajouter après `@Environment(McpHealthService.self)` :
```swift
@Environment(OmlxMonitorService.self) private var omlxMonitorService
```

- [ ] **Step 6.2 : Insérer le GroupBox oMLX dans systemPanel**

Localiser dans `systemPanel` le commentaire `// Quick actions` (environ ligne 1578). Insérer juste avant :

```swift
// oMLX inference server
GroupBox("oMLX — Local Inference") {
    VStack(spacing: 0) {
        systemInfoRow(
            "Status",
            value: omlxMonitorService.isOnline ? "Online ✓" : "Offline",
            valueColor: omlxMonitorService.isOnline ? .green : .secondary
        )
        if omlxMonitorService.isOnline {
            Divider().padding(.horizontal, 8)
            systemInfoRow(
                "Model",
                value: omlxMonitorService.defaultModel ?? "—"
            )
            Divider().padding(.horizontal, 8)
            systemInfoRow(
                "Models available",
                value: "\(omlxMonitorService.modelCount)"
            )
            Divider().padding(.horizontal, 8)
            systemInfoRow(
                "Loaded",
                value: "\(omlxMonitorService.loadedCount)"
            )
            Divider().padding(.horizontal, 8)
            systemInfoRow(
                "Memory",
                value: omlxMonitorService.memoryLabel
            )
        }
        if let checked = omlxMonitorService.lastChecked {
            Divider().padding(.horizontal, 8)
            systemInfoRow("Last check", value: checked.formattedTime)
        }
        if let err = omlxMonitorService.lastError {
            Divider().padding(.horizontal, 8)
            systemInfoRow("Error", value: err, valueColor: .red)
        }
        if providerUsageService.omlxCallsToday > 0 {
            Divider().padding(.horizontal, 8)
            systemInfoRow(
                "Calls today",
                value: "\(providerUsageService.omlxCallsToday)"
            )
        }
    }
    .padding(4)

    HStack {
        Spacer()
        Button("Refresh") {
            Task { await omlxMonitorService.checkHealth() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 4)
        .padding(.trailing, 4)
    }
}
.padding(.horizontal)

// Quick actions
```

**Note :** `checked.formattedTime` est déjà défini dans le codebase (utilisé dans UsageService). Vérifier avec `grep -n "formattedTime" Sources/ClaudeBar/` qu'il existe.

- [ ] **Step 6.3 : Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 6.4 : Commit**

```bash
git add Sources/ClaudeBar/Views/AnalyticsView.swift
git commit -m "feat(omlx): add oMLX GroupBox to AnalyticsView systemPanel."
```

---

## Task 7 — Full test suite + vérification finale

**Files:** Aucun nouveau fichier.

- [ ] **Step 7.1 : Lancer tous les tests**

```bash
swift test 2>&1 | tail -15
```
Expected: `Test Suite 'All tests' passed` — aucun test préexistant ne doit régresser.

- [ ] **Step 7.2 : Vérifier que oMLX est détecté (oMLX doit tourner)**

```bash
curl -s http://localhost:8000/health | python3 -m json.tool
```
Expected : JSON avec `"status": "healthy"`.

- [ ] **Step 7.3 : Build release**

```bash
swift build -c release 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 7.4 : Commit final si besoin**

Si des corrections mineures ont été faites lors de cette tâche :
```bash
git add -p
git commit -m "fix(omlx): post-review corrections."
```

---

## Checklist de self-review

- [x] **Spec coverage** : OmlxHealthResponse ✓, OmlxMonitorService ✓, ProviderUsageService extension ✓, DashboardView pill ✓, AnalyticsView GroupBox ✓
- [x] **Placeholder scan** : aucun TBD, TODO, ou "implement later"
- [x] **Type consistency** :
  - `OmlxHealthResponse.EnginePool` utilisé dans Task 1 + Task 2 ✓
  - `OmlxMonitorService.StateSnapshot` défini Task 2, référencé dans tests Task 2 ✓
  - `ProviderUsageService.countOmlxCallsInLines` défini Task 3, référencé dans tests Task 3 ✓
  - `omlxMonitorService.isOnline`, `.defaultModel`, `.modelCount`, `.loadedCount`, `.memoryLabel` tous forwarded depuis `StateSnapshot` ✓
  - `providerUsageService.omlxCallsToday` défini Task 3, utilisé Task 5 + Task 6 ✓
- [x] **Log canal** : `Log.omlx` ajouté en Task 2 Step 2.4 (sous-tâche explicite avec grep)
- [x] **`formattedTime`** : vérifié via grep en Task 6 Step 6.2 (note inline)
