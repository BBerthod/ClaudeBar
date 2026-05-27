# Per-Model Cost Breakdown — Design Spec

**Projet :** ClaudeBar (macOS menu bar app, Swift/SwiftUI)
**Auteur :** Billy Berthod — 2026-05-27
**Statut :** approuvé

## Objectif
Nouvelle section "Models" dans la fenêtre Analytics : répartition du coût et des tokens par modèle sur les 30 derniers jours, avec le split input / output / cache-create / cache-read (le cache-read est le vrai driver de coût — insight des données : ~97% cache reads, Opus ≈ 88% du coût).

## Décisions (brainstorm)
- **Placement** : nouvelle section "Models" dans la sidebar Analytics (à côté de Trends/Projects/Savings).
- **Période** : 30 derniers jours.

## Source de données (corrigée après exploration)
`DailyModelTokens` ne contient que l'I/O (pas le split cache). MAIS `YearlyHistoryService.scan` **lit déjà** les 4 types de tokens par message (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, lignes ~115-118) — il les jette ensuite. On ajoute un accumulateur 30 jours par modèle qui capture les 4 types.

## Composants

### 1. Modèle `ModelTokenBreakdown` (nouveau, dans `Models/`)
```swift
struct ModelTokenBreakdown: Sendable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheCreation: Int = 0
    var total: Int { input + output + cacheRead + cacheCreation }
}
```

### 2. `YearlyHistoryService.scan` (étendu)
- Ajouter un accumulateur `var model30dBreakdown: [String: ModelTokenBreakdown] = [:]`.
- Dans la boucle, **en miroir exact** de l'accumulation `dayModelTokenMap` existante (mêmes sémantiques de fenêtre `day >= cutoff30` et de déduplication), accumuler les 4 types par `model` : `model30dBreakdown[model].input += inputTokens`, etc.
- Étendre le tuple de retour avec `modelBreakdown: [String: ModelTokenBreakdown]`.
- Exposer `private(set) var last30DaysModelBreakdown: [String: ModelTokenBreakdown] = [:]` sur le service, peuplé dans `refresh()` (comme `last30DaysTokens`).

### 3. `CostCalculator` (helper ajouté)
```swift
/// Coût USD direct depuis les 4 types de tokens (DailyModelTokens a déjà tout — pas de scaling).
static func cost(modelId: String, input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> Double {
    let p = pricing(for: modelId)
    let mTok = 1_000_000.0
    return Double(input)         / mTok * p.inputPerMTok
         + Double(output)        / mTok * p.outputPerMTok
         + Double(cacheRead)     / mTok * p.cacheReadPerMTok
         + Double(cacheCreation) / mTok * p.cacheWritePerMTok
}
```

### 4. Agrégation (pure, testable — nouveau fichier `ModelBreakdown.swift`)
```swift
struct ModelCostSummary: Sendable, Identifiable {
    let model: String          // id brut (ex. "claude-opus-4-7")
    let displayName: String    // nettoyé : "Opus 4.7"
    let breakdown: ModelTokenBreakdown
    let cost: Double
    var id: String { model }
}

/// Trie par coût décroissant. displayName = id sans "claude-", segments capitalisés.
static func summaries(from breakdown: [String: ModelTokenBreakdown]) -> [ModelCostSummary]
```

### 5. Vue `ModelsBreakdownView` (nouveau)
- En-tête : coût total 30j (`CostCalculator.formatCost`), période "30 derniers jours".
- Par modèle (trié par coût) : nom + coût + barre de part % (coût/total) ; ligne de split tokens input/output/cache-create/cache-read (compteurs formatés k/M) ; ratio cache-read (`cacheRead/total`).
- Empty state si `breakdown` vide.

### 6. `AnalyticsView`
- Ajouter `case models = "Models"` à l'enum `AnalyticsSection` (icône `chart.pie` ou `cpu.fill`).
- Dans le switch de rendu du détail, `case .models:` → `ModelsBreakdownView(breakdown: yearlyHistoryService.last30DaysModelBreakdown)`.
- (AnalyticsView a déjà `@Environment(YearlyHistoryService.self)` ? sinon l'ajouter — vérifier l'injection dans `openAnalytics()` d'AppDelegate qui passe déjà `.environment(yearlyHistoryService)`.)

## Tests (Swift Testing)
- `CostCalculator.cost(...)` : coût correct depuis les 4 types (vérifier chaque tarif).
- `ModelBreakdown.summaries(from:)` : tri par coût décroissant, displayName nettoyé, mapping breakdown→summary.

## Hors scope (YAGNI)
Pas de toggle de période (30j fixe), groupement par id exact (pas de regroupement par famille), barres simples (pas de lib charts).

## Fichiers
| Action | Fichier |
|--------|---------|
| Créer | `Sources/ClaudeBar/Models/ModelTokenBreakdown.swift` |
| Créer | `Sources/ClaudeBar/Models/ModelBreakdown.swift` (ModelCostSummary + summaries) |
| Créer | `Sources/ClaudeBar/Views/ModelsBreakdownView.swift` |
| Modifier | `Sources/ClaudeBar/Services/YearlyHistoryService.swift` (scan + propriété) |
| Modifier | `Sources/ClaudeBar/Utilities/CostCalculator.swift` (helper `cost`) |
| Modifier | `Sources/ClaudeBar/Views/AnalyticsView.swift` (section) |
| Créer | `Tests/ClaudeBarTests/ModelBreakdownTests.swift` |
