# Auto-Update System — Design Spec

**Projet :** ClaudeBar (macOS menu bar app, Swift 5.9, SwiftUI)  
**Auteur :** Billy Berthod — 2026-05-26  
**Statut :** approuvé

---

## Objectif

Quand le développeur pousse une nouvelle version sur `main`, l'app en cours d'exécution :
1. Détecte la nouvelle version via GitHub Releases API
2. Télécharge le `.app` zippé
3. Remplace silencieusement `/Applications/ClaudeBar.app`
4. Redémarre automatiquement — sans aucune interaction utilisateur

---

## Contraintes

- Distribution actuelle : `.app` bundle copié dans `/Applications/` via `make install` (cp -R)
- Pas de Sparkle, pas de Homebrew, pas de notarisation
- `UpdateCheckService` existant détecte déjà les nouvelles versions via GitHub Releases API
- Vérification : au lancement + toutes les heures
- UX : 100 % silencieux (aucune alerte, aucune notification)
- Le développeur est un admin macOS → `/Applications/` est writable sans sudo

---

## Architecture

### Vue d'ensemble

```
[Push → main]
       ↓
CI: release.yml
  → make app (avec VERSION)
  → zip ClaudeBar.zip
  → gh release create v{version} + upload zip
       ↓
[App : lancement ou timer 1h]
       ↓
UpdateCheckService.checkForUpdate()
  → GitHub API /releases/latest
  → compare versions sémantiques
  → si plus récent : set assetDownloadURL
       ↓ (mise à jour détectée)
AutoUpdater.downloadAndInstall(from: assetDownloadURL)
  → télécharge dans ~/Library/Application Support/ClaudeBar/update.zip
  → extrait dans /tmp/ClaudeBar-update/
  → vérifie que ClaudeBar.app est présent dans l'extraction
  → écrit /tmp/claudebar-update.sh
  → lance le script (Process, arrière-plan)
  → NSApp.terminate()
       ↓ (app quittée)
Script shell (sleep 2, puis) :
  → mv /Applications/ClaudeBar.app → .bak
  → cp -R /tmp/ClaudeBar-update/ClaudeBar.app → /Applications/
  → rm -rf .bak
  → open /Applications/ClaudeBar.app
```

---

## Gestion des versions

### Fichier `VERSION` (nouveau, à la racine)

```
1.0.0
```

Source de vérité unique. Le Makefile et le CI lisent ce fichier.

### Makefile — `make app` (modifié)

Remplacer les deux lignes `CFBundleVersion` et `CFBundleShortVersionString` hardcodées `1.0.0` par une lecture dynamique :

```make
app: release
    @VERSION=$$(cat VERSION); \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $$VERSION" \
                             -c "Add :CFBundleVersion string $$VERSION" \
                             ...
```

### `UpdateCheckService` — lecture (inchangée)

Lit déjà `CFBundleShortVersionString` depuis le bundle au runtime :
```swift
private(set) var currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
```

---

## Composants

### 1. `.github/workflows/release.yml` (nouveau)

Déclenché sur push vers `main` (pas sur PR).

```yaml
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: macos-14
    steps:
      - checkout
      - read VERSION from file
      - check if tag v{VERSION} exists → skip if yes (idempotent)
      - make app
      - cd build && zip -r ClaudeBar.zip ClaudeBar.app
      - gh release create v{VERSION} build/ClaudeBar.zip
          --title "ClaudeBar v{VERSION}"
          --notes "Auto-release from CI"
```

**Idempotence :** si le tag `v{version}` existe déjà (même version pushée deux fois), le job skip la création de release sans erreur.

**Auth :** utilise `GITHUB_TOKEN` (auto-injecté par GitHub Actions), avec permission `write: contents`.

---

### 2. `UpdateCheckService.swift` (modifié)

Ajouter `assetDownloadURL: String?` parsé depuis le tableau `assets` de la réponse GitHub.

**Parsing additionnel :**
```swift
// Dans le bloc de parsing JSON existant, après avoir lu tag_name :
if let assets = json["assets"] as? [[String: Any]],
   let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
   let downloadURL = zipAsset["browser_download_url"] as? String {
    assetDownloadURL = downloadURL
}
```

**Propriétés nouvelles :**
```swift
private(set) var assetDownloadURL: String?
```

---

### 3. `AutoUpdater.swift` (nouveau)

```swift
@Observable @MainActor final class AutoUpdater {
    private(set) var isUpdating: Bool = false
    private let supportDir: URL  // ~/Library/Application Support/ClaudeBar/
    private let session: URLSession

    init(session: URLSession = .shared)

    func downloadAndInstall(from urlString: String) async
    // 1. Guard isUpdating (debounce)
    // 2. Télécharger vers supportDir/update.zip
    // 3. Extraire vers /tmp/ClaudeBar-update/ (Process "unzip")
    // 4. Vérifier /tmp/ClaudeBar-update/ClaudeBar.app existe
    // 5. Écrire et lancer le script shell
    // 6. NSApp.terminate()
}
```

**Script shell généré (`/tmp/claudebar-update.sh`) :**
```sh
#!/bin/sh
sleep 2
if [ -d "/tmp/ClaudeBar-update/ClaudeBar.app" ]; then
    mv "/Applications/ClaudeBar.app" "/Applications/ClaudeBar.app.bak" 2>/dev/null || true
    cp -R "/tmp/ClaudeBar-update/ClaudeBar.app" "/Applications/"
    rm -rf "/Applications/ClaudeBar.app.bak" 2>/dev/null || true
    open "/Applications/ClaudeBar.app"
fi
```

**Isolation des I/O :** `Task.detached(priority: .utility)` pour le téléchargement et l'extraction — les propriétés observables restent sur MainActor.

---

### 4. `AppDelegate.swift` (modifié)

```swift
let autoUpdater = AutoUpdater()
let updateTimer: Timer?  // 1h interval

// Dans applicationDidFinishLaunching :
// - UpdateCheckService déjà instancié → pas de changement
// - Observer updateCheckService.assetDownloadURL via withObservationTracking ou Task

// Timer 1h :
updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
    Task { @MainActor in
        await self.updateCheckService.checkForUpdate()
    }
}

// Observer les changements de mise à jour :
Task { @MainActor in
    while true {
        await Task.yield()
        if updateCheckService.updateAvailable,
           let url = updateCheckService.assetDownloadURL,
           !autoUpdater.isUpdating {
            await autoUpdater.downloadAndInstall(from: url)
            break
        }
    }
}
```

> **Note :** L'observation sera implémentée proprement via `withObservationTracking` ou `@Observable` conformance — le pattern exact sera choisi pour s'aligner sur le style existant d'AppDelegate.

---

## Edge Cases

| Cas | Comportement |
|-----|-------------|
| Téléchargement échoue | Silent failure — log dans `Log.stats`, retry au prochain check (1h) |
| Même version pushée deux fois | CI skip (tag existe) → API retourne la même version → `isNewer` = false → rien |
| Extraction échoue | Vérifie l'existence du `.app` avant de lancer le script → abort propre |
| App sans permission sur `/Applications/` | `cp -R` échoue dans le script, l'app ne se relance pas → pas de corruption (`.bak` conservé) |
| Mise à jour pendant que l'utilisateur interagit | L'app quitte immédiatement (`NSApp.terminate()` — aucune boîte de dialogue) |
| Deux updates simultanées | `isUpdating: Bool` flag debounce |

---

## Fichiers touchés

| Action | Fichier |
|--------|---------|
| Créer | `VERSION` (racine) |
| Créer | `.github/workflows/release.yml` |
| Créer | `Sources/ClaudeBar/Services/AutoUpdater.swift` |
| Modifier | `Makefile` — VERSION dynamique dans `make app` |
| Modifier | `Sources/ClaudeBar/Services/UpdateCheckService.swift` — `assetDownloadURL` |
| Modifier | `Sources/ClaudeBar/AppDelegate.swift` — AutoUpdater + timer 1h |

**Pas de tests unitaires pour `AutoUpdater`** : les I/O réelles (download, unzip, Process) sont difficilement mockables et le comportement est vérifié par intégration (pousser une version, vérifier la mise à jour).

---

## Non-inclus (hors scope)

- Vérification cryptographique du binaire (code signing / notarisation) → YAGNI pour un outil dev perso
- Delta updates / diff binaire → YAGNI
- UI de progression / rollback explicite → silencieux par décision UX
- Support `~/Applications/` comme fallback → YAGNI (admin macOS garanti)
