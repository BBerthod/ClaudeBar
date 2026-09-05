# Test Infrastructure — ClaudeBar

**Date :** 2026-05-16  
**Statut :** approuvé

---

## Contexte

ClaudeBar est une app macOS menu bar (Swift, SPM, macOS 14+). Elle contient 55 tests unitaires couvrant `StatsService`, `UsageService`, `CostCalculator`, `UpdateCheckService`, `PaceLevel`, `UsageData`. L'objectif est de mettre en place une infrastructure complète pour détecter les bugs existants et prévenir les régressions futures.

---

## Trois axes

### 1. Lancer l'app manuellement

Aucun changement au Makefile. Workflow de dev :

```bash
make run      # build debug + lance (itération rapide)
make install  # build release + installe dans /Applications (test utilisateur final)
```

Un fichier `docs/testing/manual-checklist.md` listera les scénarios à vérifier manuellement à chaque release : Dashboard, History, Analytics, Projects, Sessions, Settings, Desktop Widget, FloatingOverlay.

### 2. Tests unitaires — services non couverts

Trois nouveaux fichiers dans `Tests/ClaudeBarTests/` :

#### `BurnRateServiceTests.swift` (~10 cas)
- Calcul `tokensPerHour`, `messagesPerHour`, `costPerHour` à différentes heures du jour
- Zones de pacing : `chill` (<70%), `onTrack` (70–130%), `hot` (130–200%), `critical` (>200%)
- Projection fin de journée (workday = 10h)
- Fallback vers `LiveStatsService` quand `StatsService.todayTokens == 0`
- Exclusion du jour en cours dans le calcul de la moyenne des 30 derniers jours
- Cas limites : zéro messages, zéro historique

#### `AnomalyServiceTests.swift` (~6 cas)
- Pas de déclenchement si `burnRate == nil`
- Pas de déclenchement si `percentOfAverage < 2.0`
- Déclenchement si `percentOfAverage >= 2.0` (première fois du jour)
- Pas de second déclenchement le même jour (`lastAnomalyDate == today`)
- Déclenchement à nouveau le lendemain

#### `ExportServiceTests.swift` (si ExportService génère CSV/JSON)
- Structure des données exportées
- Format des headers CSV / clés JSON
- Cas vide (aucune donnée)

**Services exclus** de la couverture unitaire (couplés au filesystem macOS) : `SessionService`, `YearlyHistoryService`, `ProviderUsageService`, `ProjectService` — refactorisation nécessaire pour injecter le chemin, hors scope.

### 3. Snapshot testing SwiftUI

#### Dépendance

```swift
// Package.swift
.package(
    url: "https://github.com/pointfreeco/swift-snapshot-testing",
    from: "1.17.0"
)
// testTarget dependencies:
.product(name: "SnapshotTesting", package: "swift-snapshot-testing")
```

#### Fichier `Tests/ClaudeBarTests/SnapshotTests.swift`

Composants ciblés (isolés, sans dépendances externes) :

| Composant | Cas de test |
|---|---|
| `StatCard` | Valeur vide, valeur normale, valeur longue |
| `Sparkline` | Données vides, courbe croissante, courbe décroissante |
| `TokenBar` | 0%, 50%, 100% |
| `ContextGauge` | Niveaux low / medium / high |
| `ContributionGraph` | Grille vide, grille avec activité |

Vues principales (avec données mockées) :
- `ContentView` — vue racine
- `DashboardView` — vue principale (données minimales injectées)

#### Workflow

```bash
# Génération des images de référence (premier run)
swift test --filter SnapshotTests

# Mise à jour intentionnelle après un changement visuel voulu
swift test --filter SnapshotTests -- record
```

Les images de référence sont commitées dans `Tests/__Snapshots__/`.

---

## Structure finale des tests

```
Tests/ClaudeBarTests/
├── CostCalculatorTests.swift       (existant)
├── PaceLevelTests.swift            (existant)
├── StatsServiceTests.swift         (existant)
├── UpdateCheckServiceTests.swift   (existant)
├── UsageDataTests.swift            (existant)
├── UsageServiceTests.swift         (existant)
├── BurnRateServiceTests.swift      (nouveau)
├── AnomalyServiceTests.swift       (nouveau)
├── ExportServiceTests.swift        (nouveau, si applicable)
├── SnapshotTests.swift             (nouveau)
└── __Snapshots__/                  (généré + commité)
```

---

## Checklist de test manuel (`docs/testing/manual-checklist.md`)

Sections à couvrir à chaque release :
- [ ] Dashboard : stats affichées, burn rate, pacing zone
- [ ] History : graphique, filtres date
- [ ] Analytics : répartition par modèle, coûts
- [ ] Projects : liste des projets, tri
- [ ] Sessions : sessions actives, recent sessions
- [ ] Settings : tous les toggles, sauvegarde
- [ ] Desktop Widget : affichage, mise à jour
- [ ] Floating Overlay : apparition, données
- [ ] Notification d'anomalie : déclenche si dépense > 2× la moyenne

---

## Ce qui est hors scope

- XCUITest : trop complexe pour une app menu bar SPM sans projet Xcode et signing
- Tests des services filesystem (`SessionService`, `YearlyHistoryService`) : nécessite un refactor d'injection de dépendance
- CI/CD automatisé : non demandé
