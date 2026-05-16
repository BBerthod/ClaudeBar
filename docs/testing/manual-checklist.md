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
