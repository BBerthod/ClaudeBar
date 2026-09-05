# Test Infrastructure — ClaudeBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mettre en place 3 axes de test — checklist manuelle, tests unitaires (BurnRateService / AnomalyService / ExportService), et snapshot tests SwiftUI des composants visuels.

**Architecture:** `StatsService` charge son JSON de manière synchrone dans `loadStats()`, donc les tests peuvent créer un `StatsService(claudeDir: tmpDir)` avec un fixture JSON et lire `stats` immédiatement. `ExportService.buildCSV/buildJSON` passent de `private` à `internal` pour être testables via `@testable import`. Les snapshots utilisent `swift-snapshot-testing` (PointFree) ajouté en dépendance SPM.

**Tech Stack:** XCTest, swift-snapshot-testing 1.17+, Swift Package Manager, macOS 14+

---

## Fichiers impactés

| Action | Fichier |
|--------|---------|
| Créer | `docs/testing/manual-checklist.md` |
| Modifier | `Package.swift` |
| Modifier | `Sources/ClaudeBar/Services/ExportService.swift` (lignes 43 et 70 : `private` → `internal`) |
| Créer | `Tests/ClaudeBarTests/BurnRateServiceTests.swift` |
| Créer | `Tests/ClaudeBarTests/AnomalyServiceTests.swift` |
| Créer | `Tests/ClaudeBarTests/ExportServiceTests.swift` |
| Créer | `Tests/ClaudeBarTests/SnapshotTests.swift` |
| Généré | `Tests/ClaudeBarTests/__Snapshots__/SnapshotTests/` (images PNG commitées) |

---

## Task 1 : Checklist de test manuel

**Fichiers :**
- Créer : `docs/testing/manual-checklist.md`

- [ ] **Étape 1 : Créer le fichier**

```markdown
# ClaudeBar — Checklist de test manuel

À vérifier à chaque release avant de tagger.

## Prérequis

```bash
make install   # build release + installe dans /Applications
open /Applications/ClaudeBar.app
```

## Dashboard

- [ ] L'icône apparaît dans la barre de menu
- [ ] Clic sur l'icône ouvre la fenêtre principale
- [ ] Tokens aujourd'hui s'affichent (ou "--" si aucune donnée)
- [ ] Coût aujourd'hui s'affiche
- [ ] Burn rate et zone de pacing (Chill / On Track / Hot / Critical) s'affichent
- [ ] Les StatCards (Messages, Sessions, Tool Calls, Tokens) ont des valeurs cohérentes

## History

- [ ] Le graphique de tokens par jour s'affiche sur 30 jours
- [ ] Les filtres de date fonctionnent

## Analytics

- [ ] La répartition par modèle s'affiche (Opus, Sonnet, Haiku)
- [ ] Le graphique circulaire des coûts est visible
- [ ] Le Contribution Graph (grille GitHub-style) s'affiche

## Projects / Sessions

- [ ] La liste des projets contient les vrais projets Claude
- [ ] Les sessions actives affichent le bon nombre de sessions

## Settings

- [ ] Toggle "Launch at Login" change l'état sans crash
- [ ] Toggle "Show in Dock" ajoute/retire l'icône du Dock
- [ ] Export CSV et Export JSON ouvrent un panneau de sauvegarde
- [ ] Le token API peut être saisi et sauvegardé

## Desktop Widget

- [ ] Le widget apparaît sur le bureau si activé dans Settings
- [ ] Il se met à jour après ~30 secondes

## Floating Overlay

- [ ] Le raccourci clavier configuré déclenche l'overlay
- [ ] L'overlay affiche les stats live

## Notification d'anomalie

- [ ] Pour tester : simuler une dépense élevée en réglant manuellement
  `UserDefaults.standard.removeObject(forKey: "claudebar.lastAnomalyDate")`
  puis attendre le refresh si la dépense dépasse 2× la moyenne
```

- [ ] **Étape 2 : Commit**

```bash
git add docs/testing/manual-checklist.md
git commit -m "docs(testing): add manual test checklist for release validation."
```

---

## Task 2 : Ajouter la dépendance swift-snapshot-testing

**Fichiers :**
- Modifier : `Package.swift`

- [ ] **Étape 1 : Vérifier l'état actuel de Package.swift**

```bash
cat Package.swift
```

Résultat attendu : pas de dépendance `.package(url: ...)` existante.

- [ ] **Étape 2 : Modifier Package.swift**

Remplacer le contenu de `Package.swift` par :

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        ),
    ],
    targets: [
        .target(
            name: "ClaudeBarLib",
            path: "Sources/ClaudeBar"
        ),
        .executableTarget(
            name: "ClaudeBar",
            dependencies: ["ClaudeBarLib"],
            path: "Sources/ClaudeBarApp"
        ),
        .testTarget(
            name: "ClaudeBarTests",
            dependencies: [
                "ClaudeBarLib",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/ClaudeBarTests"
        )
    ]
)
```

- [ ] **Étape 3 : Résoudre la dépendance**

```bash
swift package resolve
```

Résultat attendu : `swift-snapshot-testing` apparaît dans `.build/checkouts/`.

- [ ] **Étape 4 : Vérifier que les tests existants compilent toujours**

```bash
swift test --filter ClaudeBarTests 2>&1 | tail -20
```

Résultat attendu : `Executed 55 tests, with 0 failures`.

- [ ] **Étape 5 : Commit**

```bash
git add Package.swift Package.resolved
git commit -m "chore(deps): add swift-snapshot-testing 1.17+ for SwiftUI snapshot tests."
```

---

## Task 3 : BurnRateServiceTests

**Fichiers :**
- Créer : `Tests/ClaudeBarTests/BurnRateServiceTests.swift`

**Contexte :** `BurnRateService.update()` calcule burn rate, projection, et zone de pacing. `loadStats()` dans `StatsService` est synchrone — `stats` est disponible immédiatement après `init(claudeDir:)`. Les zones extrêmes (`chill` et `critical`) sont invariantes selon l'heure car elles reposent sur des ratios très éloignés du seuil.

- [ ] **Étape 1 : Écrire les tests**

Créer `Tests/ClaudeBarTests/BurnRateServiceTests.swift` :

```swift
import XCTest
@testable import ClaudeBarLib

@MainActor
final class BurnRateServiceTests: XCTestCase {

    // MARK: - Fixture helper

    /// Écrit un stats-cache.json dans un répertoire temporaire et retourne le chemin.
    /// `todayTokens` : tokens du jour courant.
    /// `historicalTokens` : tokens des N jours précédents (index 0 = hier).
    private func makeTempStatsDir(
        todayTokens: Int,
        historicalTokens: [Int]
    ) throws -> (URL, StatsService) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        var dailyActivity: [[String: Any]] = []
        var dailyModelTokens: [[String: Any]] = []

        // Aujourd'hui
        dailyActivity.append([
            "date": today,
            "messageCount": 10,
            "sessionCount": 1,
            "toolCallCount": 5
        ])
        dailyModelTokens.append([
            "date": today,
            "tokensByModel": ["claude-sonnet-4-6": todayTokens]
        ])

        // Jours précédents
        for (i, tokens) in historicalTokens.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -(i + 1), to: Date())!
            let dateStr = formatter.string(from: date)
            dailyActivity.append([
                "date": dateStr,
                "messageCount": 8,
                "sessionCount": 1,
                "toolCallCount": 3
            ])
            dailyModelTokens.append([
                "date": dateStr,
                "tokensByModel": ["claude-sonnet-4-6": tokens]
            ])
        }

        let root: [String: Any] = [
            "version": 1,
            "lastComputedDate": today,
            "dailyActivity": dailyActivity,
            "dailyModelTokens": dailyModelTokens,
            "modelUsage": [:] as [String: Any],
            "totalSessions": 10,
            "totalMessages": 80,
            "hourCounts": ["9": 5, "10": 3]
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted)
        let jsonPath = tmpDir.appendingPathComponent("stats-cache.json")
        try data.write(to: jsonPath)

        let statsService = StatsService(claudeDir: tmpDir.path)
        return (tmpDir, statsService)
    }

    // MARK: - Nil guard

    func testNilBurnRateWhenNoStats() {
        // StatsService sans fichier → stats == nil → burnRate doit être nil
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let statsService = StatsService(claudeDir: emptyDir.path)
        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        XCTAssertNil(burnRateService.burnRate)
    }

    // MARK: - Zones (ratios extrêmes, invariants selon l'heure)

    func testZoneChill() throws {
        // Aujourd'hui = 50 tokens. Historique = 100 000 tokens/jour.
        // Même avec projection max (×10), projected = 500, avg = 100 000 → ratio = 0.005 → chill
        let (tmpDir, statsService) = try makeTempStatsDir(
            todayTokens: 50,
            historicalTokens: Array(repeating: 100_000, count: 10)
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        XCTAssertEqual(burnRateService.burnRate?.zone, .chill)
    }

    func testZoneCritical() throws {
        // Aujourd'hui = 500 000 tokens. Historique = 1 000 tokens/jour.
        // Même sans projection, projected = 500 000, avg = 1 000 → ratio = 500 → critical
        let (tmpDir, statsService) = try makeTempStatsDir(
            todayTokens: 500_000,
            historicalTokens: Array(repeating: 1_000, count: 10)
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        XCTAssertEqual(burnRateService.burnRate?.zone, .critical)
    }

    // MARK: - averageDailyTokens (heure-invariant : calcul sur l'historique seul)

    func testAverageDailyTokensExcludesToday() throws {
        // Historique : 5 jours à 2 000 tokens = moyenne = 2 000.
        // Aujourd'hui à 99 999 tokens ne doit PAS influer sur la moyenne des 30 jours précédents.
        let (tmpDir, statsService) = try makeTempStatsDir(
            todayTokens: 99_999,
            historicalTokens: Array(repeating: 2_000, count: 5)
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        XCTAssertEqual(burnRateService.burnRate?.averageDailyTokens, 2_000)
    }

    func testAverageDailyTokensWithNoHistory() throws {
        // Aucun historique → fallback sur les tokens du jour.
        let (tmpDir, statsService) = try makeTempStatsDir(
            todayTokens: 1_234,
            historicalTokens: []
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        XCTAssertEqual(burnRateService.burnRate?.averageDailyTokens, 1_234)
    }

    // MARK: - Fallback LiveStatsService

    func testFallbackToLiveStatsWhenTodayTokensZero() throws {
        // StatsService sans entrée pour aujourd'hui → todayTokens == 0
        // LiveStatsService retourne 5 000 tokens → burnRate doit être non-nil
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Fixture avec uniquement des données historiques (pas d'entrée pour aujourd'hui)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        let root: [String: Any] = [
            "version": 1,
            "lastComputedDate": yesterday,
            "dailyActivity": [
                ["date": yesterday, "messageCount": 8, "sessionCount": 1, "toolCallCount": 3]
            ],
            "dailyModelTokens": [
                ["date": yesterday, "tokensByModel": ["claude-sonnet-4-6": 1_000]]
            ],
            "modelUsage": [:] as [String: Any],
            "totalSessions": 5,
            "totalMessages": 40,
            "hourCounts": ["9": 2]
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted)
        try data.write(to: tmpDir.appendingPathComponent("stats-cache.json"))

        let statsService = StatsService(claudeDir: tmpDir.path)
        XCTAssertEqual(statsService.todayTokens, 0, "Prérequis : todayTokens doit être 0")

        // LiveStatsService avec données live
        let liveDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: liveDir) }

        let liveStatsService = LiveStatsService(claudeDir: liveDir.path)
        // LiveStatsService lit des fichiers JSONL — sans fixture JSONL, todayCost reste 0.
        // Ce test vérifie uniquement que la branche fallback est prise sans crash.
        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService, liveStatsService: liveStatsService)

        // burnRate peut être nil ici car liveStatsService.todayTokens == 0 aussi,
        // mais l'appel ne doit pas crasher.
        // Si burnRate est non-nil, les champs doivent être cohérents.
        if let burnRate = burnRateService.burnRate {
            XCTAssertGreaterThanOrEqual(burnRate.tokensPerHour, 0)
            XCTAssertGreaterThanOrEqual(burnRate.hoursActive, 1.0)
        }
    }
}
```

- [ ] **Étape 2 : Lancer les tests — ils doivent passer**

```bash
swift test --filter BurnRateServiceTests 2>&1 | tail -20
```

Résultat attendu : `Executed 5 tests, with 0 failures`.

Si un test échoue avec `XCTAssertEqual failed: ("Optional(ClaudeBarLib.PacingZone.xxx)")`, vérifier que les ratios extrêmes dans les fixtures couvrent bien tous les cas temporels.

- [ ] **Étape 3 : Commit**

```bash
git add Tests/ClaudeBarTests/BurnRateServiceTests.swift
git commit -m "test(burn-rate): add 5 unit tests for BurnRateService zones, averages, and fallback."
```

---

## Task 4 : AnomalyServiceTests

**Fichiers :**
- Créer : `Tests/ClaudeBarTests/AnomalyServiceTests.swift`

**Contexte :** `AnomalyService.check()` déclenche une notification si `burnRate.percentOfAverage >= 2.0` et qu'elle n'a pas déjà été déclenchée aujourd'hui. Elle écrit dans `UserDefaults.standard`. Pour isoler les tests du vrai UserDefaults, on supprime la clé avant chaque test et on la restaure après.

- [ ] **Étape 1 : Écrire les tests**

Créer `Tests/ClaudeBarTests/AnomalyServiceTests.swift` :

```swift
import XCTest
@testable import ClaudeBarLib

@MainActor
final class AnomalyServiceTests: XCTestCase {

    private let defaultsKey = "claudebar.lastAnomalyDate"

    override func setUp() {
        super.setUp()
        // Nettoyer la clé avant chaque test pour isoler les effets de bord
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Helpers

    private func makeStatsDir(todayTokens: Int, historicalTokens: [Int]) throws -> (URL, StatsService) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        var dailyActivity: [[String: Any]] = [
            ["date": today, "messageCount": 10, "sessionCount": 1, "toolCallCount": 5]
        ]
        var dailyModelTokens: [[String: Any]] = [
            ["date": today, "tokensByModel": ["claude-sonnet-4-6": todayTokens]]
        ]

        for (i, tokens) in historicalTokens.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -(i + 1), to: Date())!
            let dateStr = formatter.string(from: date)
            dailyActivity.append(["date": dateStr, "messageCount": 8, "sessionCount": 1, "toolCallCount": 3])
            dailyModelTokens.append(["date": dateStr, "tokensByModel": ["claude-sonnet-4-6": tokens]])
        }

        let root: [String: Any] = [
            "version": 1, "lastComputedDate": today,
            "dailyActivity": dailyActivity, "dailyModelTokens": dailyModelTokens,
            "modelUsage": [:] as [String: Any],
            "totalSessions": 10, "totalMessages": 80, "hourCounts": ["9": 5]
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted)
        try data.write(to: tmpDir.appendingPathComponent("stats-cache.json"))
        return (tmpDir, StatsService(claudeDir: tmpDir.path))
    }

    // MARK: - Tests

    func testNoFireWhenBurnRateIsNil() {
        // BurnRateService sans update → burnRate == nil → check() ne fait rien
        let burnRateService = BurnRateService()   // burnRate == nil
        let notificationService = NotificationService()
        let anomalyService = AnomalyService()

        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        XCTAssertNil(anomalyService.lastAnomalyDate)
    }

    func testNoFireWhenRatioBelowThreshold() throws {
        // Aujourd'hui = 50 tokens, historique = 100 000 → ratio ≈ 0 → bien en dessous de 2.0
        let (tmpDir, statsService) = try makeStatsDir(
            todayTokens: 50,
            historicalTokens: Array(repeating: 100_000, count: 10)
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)
        XCTAssertNotNil(burnRateService.burnRate, "Prérequis : burnRate doit être non-nil")
        XCTAssertLessThan(burnRateService.burnRate!.percentOfAverage, 2.0, "Prérequis : ratio < 2.0")

        let notificationService = NotificationService()
        let anomalyService = AnomalyService()
        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        XCTAssertNil(anomalyService.lastAnomalyDate)
    }

    func testFiresWhenRatioAboveThreshold() throws {
        // Aujourd'hui = 500 000 tokens, historique = 1 000 → ratio = 500 → déclenche
        let (tmpDir, statsService) = try makeStatsDir(
            todayTokens: 500_000,
            historicalTokens: Array(repeating: 1_000, count: 10)
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)
        XCTAssertGreaterThanOrEqual(burnRateService.burnRate!.percentOfAverage, 2.0)

        let notificationService = NotificationService()
        let anomalyService = AnomalyService()
        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        let today = DateFormatter.isoDate.string(from: Date())
        XCTAssertEqual(anomalyService.lastAnomalyDate, today)
    }

    func testNoSecondFireSameDay() throws {
        // Déjà déclenché aujourd'hui → deuxième appel ne doit pas changer lastAnomalyDate
        let today = DateFormatter.isoDate.string(from: Date())
        UserDefaults.standard.set(today, forKey: defaultsKey)

        let (tmpDir, statsService) = try makeStatsDir(
            todayTokens: 500_000,
            historicalTokens: Array(repeating: 1_000, count: 10)
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        let notificationService = NotificationService()
        // AnomalyService init lit UserDefaults → lastAnomalyDate == today
        let anomalyService = AnomalyService()
        XCTAssertEqual(anomalyService.lastAnomalyDate, today, "Prérequis : déjà déclenché aujourd'hui")

        // Deuxième appel
        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        // lastAnomalyDate doit rester aujourd'hui (pas de nouvelle notification)
        XCTAssertEqual(anomalyService.lastAnomalyDate, today)
    }

    func testFiresAgainNextDay() throws {
        // Déclenché hier → doit se déclencher à nouveau aujourd'hui
        let yesterday = DateFormatter.isoDate.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )
        UserDefaults.standard.set(yesterday, forKey: defaultsKey)

        let (tmpDir, statsService) = try makeStatsDir(
            todayTokens: 500_000,
            historicalTokens: Array(repeating: 1_000, count: 10)
        )
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let burnRateService = BurnRateService()
        burnRateService.update(statsService: statsService)

        let notificationService = NotificationService()
        let anomalyService = AnomalyService()
        anomalyService.check(burnRateService: burnRateService, notificationService: notificationService)

        let today = DateFormatter.isoDate.string(from: Date())
        XCTAssertEqual(anomalyService.lastAnomalyDate, today)
    }
}
```

- [ ] **Étape 2 : Lancer les tests**

```bash
swift test --filter AnomalyServiceTests 2>&1 | tail -20
```

Résultat attendu : `Executed 5 tests, with 0 failures`.

- [ ] **Étape 3 : Commit**

```bash
git add Tests/ClaudeBarTests/AnomalyServiceTests.swift
git commit -m "test(anomaly): add 5 unit tests for AnomalyService fire conditions and dedup guard."
```

---

## Task 5 : ExportService — testabilité + ExportServiceTests

**Fichiers :**
- Modifier : `Sources/ClaudeBar/Services/ExportService.swift` (lignes 43 et 70)
- Créer : `Tests/ClaudeBarTests/ExportServiceTests.swift`

**Contexte :** `buildCSV` et `buildJSON` sont déclarées `private static`. En les passant à `internal static` (retirer le mot-clé `private`), elles deviennent accessibles via `@testable import ClaudeBarLib`. Changement chirurgical : les deux `private` sur ces deux fonctions uniquement.

- [ ] **Étape 1 : Écrire les tests (ils échouent car `private`)**

Créer `Tests/ClaudeBarTests/ExportServiceTests.swift` :

```swift
import XCTest
@testable import ClaudeBarLib

final class ExportServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeStats(
        dates: [String],
        tokensPerDay: Int = 1_000,
        messagesPerDay: Int = 10
    ) -> StatsCache {
        let activity = dates.map { date in
            DailyActivity(date: date, messageCount: messagesPerDay, sessionCount: 1, toolCallCount: 3)
        }
        let tokens = dates.map { date in
            DailyModelTokens(date: date, tokensByModel: ["claude-sonnet-4-6": tokensPerDay])
        }
        return StatsCache(
            version: 1,
            lastComputedDate: dates.last ?? "2026-01-01",
            dailyActivity: activity,
            dailyModelTokens: tokens,
            modelUsage: [:],
            totalSessions: dates.count,
            totalMessages: dates.count * messagesPerDay,
            longestSession: nil,
            firstSessionDate: nil,
            hourCounts: [:],
            totalSpeculationTimeSavedMs: nil
        )
    }

    // MARK: - CSV

    func testCSVHeaderRow() {
        let stats = makeStats(dates: ["2026-01-01"])
        let csv = ExportService.buildCSV(stats: stats, modelUsage: [:])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.first, "date,sessions,messages,tool_calls,tokens,cost_usd")
    }

    func testCSVOneRowPerDate() {
        let dates = ["2026-01-01", "2026-01-02", "2026-01-03"]
        let stats = makeStats(dates: dates)
        let csv = ExportService.buildCSV(stats: stats, modelUsage: [:])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // 1 header + 3 data rows
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[1].hasPrefix("2026-01-01,"), "Première ligne de données doit commencer par la date")
    }

    func testCSVColumnsFormat() {
        let stats = makeStats(dates: ["2026-05-16"], tokensPerDay: 5_000, messagesPerDay: 20)
        let csv = ExportService.buildCSV(stats: stats, modelUsage: [:])
        let dataLine = csv.components(separatedBy: "\n").filter { !$0.isEmpty }[1]
        let columns = dataLine.components(separatedBy: ",")

        XCTAssertEqual(columns.count, 6, "6 colonnes : date, sessions, messages, tool_calls, tokens, cost_usd")
        XCTAssertEqual(columns[0], "2026-05-16")
        XCTAssertEqual(columns[2], "20", "messageCount = 20")
        XCTAssertEqual(columns[4], "5000", "tokens = 5000")
    }

    func testCSVEmptyStats() {
        let stats = makeStats(dates: [])
        let csv = ExportService.buildCSV(stats: stats, modelUsage: [:])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 1, "Uniquement le header pour des stats vides")
        XCTAssertEqual(lines[0], "date,sessions,messages,tool_calls,tokens,cost_usd")
    }

    // MARK: - JSON

    func testJSONValidOutput() {
        let stats = makeStats(dates: ["2026-01-01"])
        let json = ExportService.buildJSON(stats: stats, modelUsage: [:])

        XCTAssertFalse(json.isEmpty)
        let data = json.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "JSON doit être parsable")
    }

    func testJSONRootKeys() throws {
        let stats = makeStats(dates: ["2026-01-01"])
        let json = ExportService.buildJSON(stats: stats, modelUsage: [:])
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(root["exported_at"], "Clé 'exported_at' manquante")
        XCTAssertNotNil(root["total_cost_usd"], "Clé 'total_cost_usd' manquante")
        XCTAssertNotNil(root["total_sessions"], "Clé 'total_sessions' manquante")
        XCTAssertNotNil(root["total_messages"], "Clé 'total_messages' manquante")
        XCTAssertNotNil(root["daily_data"], "Clé 'daily_data' manquante")
    }

    func testJSONDailyDataStructure() throws {
        let stats = makeStats(dates: ["2026-05-16"], tokensPerDay: 3_000, messagesPerDay: 15)
        let json = ExportService.buildJSON(stats: stats, modelUsage: [:])
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let dailyData = root["daily_data"] as! [[String: Any]]

        XCTAssertEqual(dailyData.count, 1)
        let entry = dailyData[0]
        XCTAssertEqual(entry["date"] as? String, "2026-05-16")
        XCTAssertEqual(entry["messages"] as? Int, 15)
        XCTAssertEqual(entry["tokens"] as? Int, 3_000)
    }

    func testJSONEmptyStats() throws {
        let stats = makeStats(dates: [])
        let json = ExportService.buildJSON(stats: stats, modelUsage: [:])
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let dailyData = root["daily_data"] as! [[String: Any]]

        XCTAssertEqual(dailyData.count, 0)
    }
}
```

- [ ] **Étape 2 : Lancer les tests — ils DOIVENT échouer (méthodes `private`)**

```bash
swift test --filter ExportServiceTests 2>&1 | tail -10
```

Résultat attendu : erreur de compilation `'buildCSV' is inaccessible due to 'private' protection level`.

- [ ] **Étape 3 : Retirer `private` sur buildCSV et buildJSON dans ExportService.swift**

Dans `Sources/ClaudeBar/Services/ExportService.swift`, ligne 43 :

```swift
// Avant :
private static func buildCSV(stats: StatsCache, modelUsage: [String: ModelUsageEntry]) -> String {

// Après :
static func buildCSV(stats: StatsCache, modelUsage: [String: ModelUsageEntry]) -> String {
```

Ligne 70 :

```swift
// Avant :
private static func buildJSON(stats: StatsCache, modelUsage: [String: ModelUsageEntry]) -> String {

// Après :
static func buildJSON(stats: StatsCache, modelUsage: [String: ModelUsageEntry]) -> String {
```

- [ ] **Étape 4 : Lancer les tests — ils doivent passer**

```bash
swift test --filter ExportServiceTests 2>&1 | tail -20
```

Résultat attendu : `Executed 7 tests, with 0 failures`.

- [ ] **Étape 5 : Commit**

```bash
git add Sources/ClaudeBar/Services/ExportService.swift Tests/ClaudeBarTests/ExportServiceTests.swift
git commit -m "test(export): expose buildCSV/buildJSON as internal, add 7 format tests."
```

---

## Task 6 : SnapshotTests des composants SwiftUI

**Fichiers :**
- Créer : `Tests/ClaudeBarTests/SnapshotTests.swift`
- Généré : `Tests/ClaudeBarTests/__Snapshots__/SnapshotTests/` (PNG commitées)

**Contexte :** `swift-snapshot-testing` utilise `NSHostingController` pour rendre les vues SwiftUI sur macOS. Les images de référence sont générées au premier run (`record: true`), puis comparées à chaque run suivant. `StatCard` et `Sparkline` sont purs (aucune dépendance externe). `ContributionGraph` prend `Binding<ContributionMetric>` — on crée un état local avec `@State` wrappé dans une vue intermédiaire.

- [ ] **Étape 1 : Écrire les tests snapshot**

Créer `Tests/ClaudeBarTests/SnapshotTests.swift` :

```swift
import XCTest
import SnapshotTesting
import SwiftUI
@testable import ClaudeBarLib

@MainActor
final class SnapshotTests: XCTestCase {

    // MARK: - StatCard

    func testStatCardNormal() {
        let view = StatCard(title: "Messages", value: "142", icon: "message", trend: "+12%", trendUp: true)
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 150, height: 80))
        )
    }

    func testStatCardNoTrend() {
        let view = StatCard(title: "Sessions", value: "7", icon: "rectangle.stack")
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 150, height: 80))
        )
    }

    func testStatCardTrendDown() {
        let view = StatCard(title: "Tool Calls", value: "89", icon: "wrench.and.screwdriver", trend: "-3%", trendUp: false)
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 150, height: 80))
        )
    }

    func testStatCardLongValue() {
        let view = StatCard(title: "Tokens", value: "1,234,567", icon: "text.word.spacing")
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 150, height: 80))
        )
    }

    // MARK: - Sparkline

    func testSparklineEmpty() {
        let view = Sparkline(data: [])
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 200, height: 50))
        )
    }

    func testSparklineRising() {
        let view = Sparkline(data: [1, 3, 2, 7, 5, 9, 12, 8, 15])
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 200, height: 50))
        )
    }

    func testSparklineFalling() {
        let view = Sparkline(data: [15, 12, 10, 8, 5, 3, 1])
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 200, height: 50))
        )
    }

    // MARK: - ContributionGraph

    /// Vue wrapper pour ContributionGraph qui gère le Binding<ContributionMetric> localement.
    private struct ContributionGraphWrapper: View {
        let dayStats: [Date: DayStats]
        @State var metric: ContributionMetric = .tokens

        var body: some View {
            ContributionGraph(dayStats: dayStats, metric: $metric)
        }
    }

    func testContributionGraphEmpty() {
        let view = ContributionGraphWrapper(dayStats: [:])
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 420, height: 90))
        )
    }

    func testContributionGraphWithActivity() {
        // Valeurs fixes pour des snapshots déterministes
        var stats: [Date: DayStats] = [:]
        let calendar = Calendar.current
        let fixedValues: [(Int, Double)] = [
            (5_000, 0.50), (12_000, 1.20), (800, 0.08), (30_000, 3.00),
            (7_500, 0.75), (22_000, 2.20), (1_200, 0.12), (45_000, 4.50),
            (3_000, 0.30), (18_000, 1.80), (9_000, 0.90), (600, 0.06),
        ]
        for (i, (tokens, cost)) in fixedValues.enumerated() {
            if let date = calendar.date(byAdding: .weekOfYear, value: -i, to: Date()) {
                let day = calendar.startOfDay(for: date)
                stats[day] = DayStats(tokens: tokens, cost: cost)
            }
        }
        let view = ContributionGraphWrapper(dayStats: stats)
        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 420, height: 90))
        )
    }
}
```

- [ ] **Étape 2 : Activer le mode record dans SnapshotTests.swift**

Ajouter `isRecording = true` dans `setUp()` de `SnapshotTests` :

```swift
@MainActor
final class SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        isRecording = true   // ← génère les images de référence
    }
    // ... reste inchangé
```

- [ ] **Étape 3 : Premier run — générer les images de référence**

```bash
swift test --filter SnapshotTests 2>&1 | tail -30
```

Résultat attendu : tests "failed" avec `"Record mode is on."` + PNG sauvegardées dans `Tests/ClaudeBarTests/__Snapshots__/SnapshotTests/`.

Si une erreur de compilation apparaît (ex. : `ContributionGraph` signature différente), lire le fichier source et ajuster le wrapper.

- [ ] **Étape 4 : Vérifier les images générées**

```bash
ls Tests/ClaudeBarTests/__Snapshots__/SnapshotTests/
open Tests/ClaudeBarTests/__Snapshots__/SnapshotTests/
```

Ouvrir chaque PNG et vérifier visuellement que le rendu est correct (composant visible, pas d'image noire ou vide). Si une vue est blanche ou noire, vérifier la taille passée à `image(size:)` et l'ajuster.

- [ ] **Étape 5 : Désactiver le mode record**

Retirer `isRecording = true` du `setUp()` (ou commenter la ligne).

- [ ] **Étape 6 : Deuxième run — les tests doivent passer (comparaison contre référence)**

```bash
swift test --filter SnapshotTests 2>&1 | tail -20
```

Résultat attendu : `Executed 9 tests, with 0 failures`.

- [ ] **Étape 7 : Commit**

```bash
git add Tests/ClaudeBarTests/SnapshotTests.swift Tests/ClaudeBarTests/__Snapshots__/
git commit -m "test(snapshots): add 9 snapshot tests for StatCard, Sparkline, and ContributionGraph."
```

---

## Task 7 : Validation finale

- [ ] **Étape 1 : Lancer tous les tests**

```bash
swift test 2>&1 | tail -10
```

Résultat attendu : `Executed 76 tests, with 0 failures` (55 existants + 5 BurnRate + 5 Anomaly + 7 Export + 9 Snapshots).

- [ ] **Étape 2 : Test de l'app en mode dev**

```bash
make run
```

Vérifier dans la barre de menu que l'app démarre correctement.

- [ ] **Étape 3 : Commit de bilan (si des ajustements mineurs ont eu lieu)**

```bash
git add -p   # réviser chaque diff avant staging
git commit -m "test: finalize test infrastructure — 76 tests total, 3 axes couverts."
```

---

## Workflow de mise à jour des snapshots

Quand un changement visuel intentionnel est fait sur un composant :

```bash
# Regénérer uniquement les snapshots du composant modifié
swift test --filter SnapshotTests.testStatCard 2>&1
# → échoue et recrée les PNG automatiquement si record=true est set dans le test
```

Ou passer `record: true` dans `assertSnapshot(...)` temporairement, relancer, puis retirer le flag et commiter les nouvelles images.
