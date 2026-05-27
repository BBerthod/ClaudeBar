# Context Compaction Alert — Design Spec

**Projet :** ClaudeBar (macOS menu bar app, Swift/SwiftUI)
**Auteur :** Billy Berthod — 2026-05-27
**Statut :** approuvé

## Objectif

Notifier (macOS) quand une session Claude Code active franchit un seuil d'occupation de sa fenêtre de contexte (compaction imminente). La jauge passe déjà au rouge >80% visuellement ; il manque une vraie alerte.

## Décisions (brainstorm)
- **Mode** : notification macOS, dédupliquée par session (via l'infra `NotificationService` existante).
- **Seuil** : configurable, défaut **90%**, `0` = désactivé.
- **Réarmement** : hystérésis — alerte au franchissement du seuil, réarme quand le contexte retombe sous `seuil − 20%` (ex. seuil 90% → réarme sous 70%).

## Approche
Logique dans `NotificationService` (comme `checkUsageThreshold`/`sendCostAlertIfNeeded`), appelée depuis le cycle de refresh 30s d'`AppDelegate`, lisant `sessionService.activeSessions` + `sessionService.contextEstimates` (déjà normalisés 0–1 par le fix de jauge).

## Composants

### 1. Réglage (`SettingsView.swift`)
`@AppStorage("claudebar.contextAlertThreshold")` (Double, défaut `90`). Picker à côté du cost alert : Off (0) / 80 / 85 / 90 / 95.

### 2. `NotificationService`
- État : `private var contextAlertArmed: [String: Bool]` (sessionId → armé). Absent = considéré armé (premier franchissement alerte).
- Fonction pure testable :
  ```swift
  nonisolated static func contextAlertDecision(
      fraction: Double, thresholdFraction: Double, armed: Bool
  ) -> (shouldAlert: Bool, armed: Bool)
  ```
  - `rearm = max(0, thresholdFraction - 0.20)`
  - si `armed && fraction >= thresholdFraction` → `(true, false)` (alerte + désarme)
  - sinon si `!armed && fraction < rearm` → `(false, true)` (réarme, pas d'alerte)
  - sinon → `(false, armed)` (inchangé)
- `func checkContextThresholds(activeSessions: [ActiveSession], contextEstimates: [String: Double], thresholdPercent: Double)`
  - `guard thresholdPercent > 0` (0 = désactivé)
  - `thresholdFraction = thresholdPercent / 100`
  - pour chaque session active avec une estimate : applique `contextAlertDecision` avec l'état courant (défaut `true` si absent) ; si `shouldAlert`, `sendNotification(title:, body:, identifier: "compaction_\(sessionId)")` ; stocke le nouvel `armed`.
  - purge `contextAlertArmed` des sessionId qui ne sont plus actifs.

### 3. `AppDelegate`
Dans le timer 30s existant (où sont déjà `checkUsageThreshold`, `sendCostAlertIfNeeded`), ajouter :
```swift
let ctxThreshold = UserDefaults.standard.double(forKey: "claudebar.contextAlertThreshold")
self.notificationService.checkContextThresholds(
    activeSessions: self.sessionService.activeSessions,
    contextEstimates: self.sessionService.contextEstimates,
    thresholdPercent: ctxThreshold > 0 ? ctxThreshold : 90
)
```
(Si la clé n'est jamais réglée, `double(forKey:)` renvoie 0 → fallback 90.)

### 4. Notification
- Titre : `Contexte élevé — {projectName}`
- Corps : `{X}% de la fenêtre de contexte · compaction imminente`
- `projectName` = `URL(fileURLWithPath: session.cwd).lastPathComponent`, `X` = `Int(fraction * 100)`.

## Tests
Tests Swift Testing de `contextAlertDecision` :
1. armé + franchissement (0.92 ≥ 0.90) → `(true, false)`.
2. désarmé + reste haut (0.92, armed false) → `(false, false)` (pas de re-alerte).
3. désarmé + retombe sous réarmement (0.65 < 0.70) → `(false, true)`.
4. réarmé + nouveau franchissement → `(true, false)`.
5. armé + sous le seuil (0.5) → `(false, true)` (reste armé, pas d'alerte).
6. seuil élevé : `rearm` clampé à 0 si `threshold < 0.20`.

## Hors scope (YAGNI)
Pas d'icône barre menu, pas de son custom, pas de persistance de l'état entre redémarrages (réarmé au lancement — acceptable).

## Fichiers
| Action | Fichier |
|--------|---------|
| Modifier | `Sources/ClaudeBar/Services/NotificationService.swift` |
| Modifier | `Sources/ClaudeBar/AppDelegate.swift` |
| Modifier | `Sources/ClaudeBar/Views/SettingsView.swift` |
| Créer | `Tests/ClaudeBarTests/ContextAlertDecisionTests.swift` |
