---
name: release
description: Release de bout en bout de DSM Access — rédige les notes de version (RELEASE_NOTES.md) puis build/signe/notarise/staple/publie via `./build.sh --release` + l'appcast Sparkle. À utiliser quand on coupe une release : « publie la nouvelle version », « release vX.Y », « ship », « sors la v1.1 », ou pour passer de « le code est sur main » à « les utilisateurs reçoivent la mise à jour ». Déclenché par l'utilisateur uniquement — la moitié publication a des effets irréversibles (release publique, push de l'appcast).
disable-model-invocation: true
---

# Release DSM Access (notes → publication)

Une skill, deux phases. Phase A (notes) est sûre — elle n'écrit que du Markdown.
Phase B (publication) est **irréversible** : elle build, notarise et pousse une
release publique. **Ne jamais lancer la Phase B sans feu vert explicite.**

Portée via argument :
- `/release notes` → Phase A seulement, puis stop.
- `/release` ou `/release publish` → Phase A, puis **pause + confirmation** avant Phase B.

Ne pas se fier à la mémoire de session pour « ce qui a changé » — toujours interroger git.

Contexte de distribution (déjà en place, voir mémoire `sparkle-distribution`) :
- App Developer ID + notarisée + staplée ; feed Sparkle `SUFeedURL` =
  `https://math65.github.io/dsmaccess/appcast.xml` servi par **GitHub Pages (main /docs)**.
- Le `.zip` de chaque version vit dans une **release GitHub** `vVERSION`.
- Clé EdDSA et profil notarytool (`ttaccessible-notary`, partagé) déjà dans le trousseau.

---

## Phase A — Rédiger les notes de version

### A1. Repérer le point de départ

```bash
git tag --sort=-v:refname | head -5          # dernier tag publié (ex. v1.0)
git log <dernier-tag>..HEAD --oneline --no-merges
```

Grouper les commits par thème (nouveautés, corrections, accessibilité, plomberie).
Ignorer les commits purement release (« Bump… », « Update appcast ») dans les notes.

### A2. Écrire `RELEASE_NOTES.md` (EN)

Le corps de la release GitHub est **en anglais**. Structure :

```markdown
## vX.Y (build N) — AAAA-MM-JJ

### Highlights
- Une phrase sur le changement le plus marquant.

### <Fixes / New / Changes>
- Une puce par changement, préfixée par la zone (Files, Storage, VoiceOver…).
```

**Pas de section « Download ».** Le lien vers le zip ne sert nulle part : sur la page
de release GitHub l'asset est déjà listé juste en dessous, et dans le dialogue de mise
à jour de Sparkle l'application se met à jour toute seule — proposer un téléchargement
manuel n'y a aucun sens. Les versions jusqu'à la 1.1 en portaient une, par habitude.

**Ton — écrire pour l'utilisateur VoiceOver, pas pour le changelog :**
- Mener par **l'effet visible**, pas le mécanisme. « Le renommage de dossier
  fonctionne à nouveau » — pas « corrigé le early-return dans Rename ».
- Zéro jargon interne (noms de classes/fonctions, chemins de fichiers, termes API).
- Une idée par puce. Test à voix haute : si ça sonne comme un titre de commit,
  reformuler comme on le dirait à un ami non technique.

### A3. Notes françaises + rendu HTML — DIFFÉRÉ (à brancher quand ça devient visible)

Pour v1.0 on a choisi **lean** : `RELEASE_NOTES.md` EN seul (personne ne met à jour
VERS une première version → le dialogue de notes Sparkle n'est jamais affiché).
Dès qu'une version met à jour depuis une précédente et qu'on veut de belles notes
FR/EN dans l'app, brancher le rendu riche :
- Copier `scripts/render-release-notes.sh` + `release-notes-template.html` depuis
  `~/dev/teamtalk/ttaccessible/scripts/` (pandoc, thème clair/sombre).
- Écrire `RELEASE_NOTES.fr.md` **en français idiomatique** (vouvoiement, PAS un calque
  mot à mot de l'anglais — Mathieu rejette le « translationese »).
- Rendre `docs/<base>.html` + `docs/<base>.fr.html` AVANT `generate_appcast` : il détecte
  les sidecars et émet les `<sparkle:releaseNotesLink>`. Ajouter ce rendu dans `build.sh`.

**Si invoqué avec `notes` : stop ici.** Sinon, continuer en Phase B.

---

## Phase B — Build & publier (irréversible — confirmer d'abord)

Avant de lancer quoi que ce soit : résumer ce qui va se passer (version, contenu des
notes) et obtenir un **go explicite**. Ces étapes signent, notarisent et poussent une
release publique qui atteint chaque utilisateur via l'updater in-app.

### B0. Prérequis

- **Bump de version committé** : `MARKETING_VERSION` **et** `CURRENT_PROJECT_VERSION`
  dans `dsmaccess.xcodeproj/project.pbxproj`. Sparkle compare par **build** (`CURRENT_PROJECT_VERSION`)
  → l'incrémenter à chaque release, sinon l'update n'est pas proposé. Le tag GitHub est
  `vMARKETING_VERSION` → lui donner une valeur distincte à chaque version (évite les collisions de tag).
- **Betas (canal `beta`)** : nommer `MARKETING_VERSION` avec un suffixe `-beta.N`
  (ex. `1.1-beta.1`, build 2 ; `1.1-beta.2`, build 3 ; puis la stable `1.1`, build suivant).
  `build.sh` détecte « beta » dans la version et, automatiquement : tague l'entrée d'appcast
  sur le canal `beta` (`--channel beta`) et marque la release GitHub `--prerelease`. Côté app,
  `UpdaterChannelDelegate.allowedChannels` n'ouvre le canal `beta` que pour un build dont la
  version contient « beta » → un build stable ignore les entrées beta, sans rien à basculer.
  Les entrées stables (sans canal) restent visibles de tous ; seules les entrées beta sont
  réservées aux builds beta.
- `RELEASE_NOTES.md` à jour (Phase A).
- Sur `main`, arbre de travail propre.

### B1. Build, signe, notarise, publie

```bash
./build.sh --release
```

Ce que ça fait (voir `build.sh` pour le détail) :
- Archive Release + signe **Developer ID**.
- Exporte (l'export gère la signature profonde du framework Sparkle + XPC).
- Zippe → **notarise** (`notarytool`, profil `ttaccessible-notary`) → **staple** → contrôle Gatekeeper → re-zip.
- Régénère `docs/appcast.xml` signé EdDSA (préserve les entrées précédentes).
- Crée la **release GitHub** `vVERSION` avec le zip + `RELEASE_NOTES.md`.
- Commit + push de `docs/appcast.xml` (depuis `main` uniquement).

Pour d'abord valider sans rien publier : `./build.sh` (local) ou `./build.sh --notarize`
(notarise + appcast, sans release/push).

### B2. Vérifier

- L'asset direct résout : `https://github.com/math65/dsmaccess/releases/download/vX.Y/dsmaccess-X.Y.zip`
- L'appcast charge et liste la nouvelle version : `https://math65.github.io/dsmaccess/appcast.xml`
  (le build Pages prend ~1-2 min après le push).
- Signature EdDSA de l'appcast cohérente avec le zip publié :
  `<...>/bin/sign_update <zip>` doit donner la même `sparkle:edSignature` que l'appcast.
- Idéal : tester l'updater in-app depuis une install de la version précédente.

### B3. Annoncer (optionnel, AppleVis)

Canal de retour = **AppleVis** (communauté lecteurs d'écran Apple). Post en anglais,
Markdown, sujet ≤ 64 caractères, titres H4 ou moins, URL directe de l'asset cliquable.
Rédiger la version AppleVis séparément — ne pas réutiliser tel quel le corps GitHub.
