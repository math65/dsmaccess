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

### A3. Notes françaises + rendu HTML — ACTIF depuis la 1.1-beta.11

`RELEASE_NOTES.md` (EN) **et** `RELEASE_NOTES.fr.md` sont **tous les deux obligatoires**
et **cumulatifs** : la nouvelle section se met EN TÊTE, l'historique reste dessous
(écrasé par erreur en beta.12 ; le .fr.md oublié en beta.5 — les deux pièges sont réels).
- Le titre de section porte **la version ET le build** : `## vX.Y-beta.N (build M) — date`.
  Sparkle compare par build ; les dates EN sont en `AAAA-MM-JJ`, les FR en toutes lettres.
- Écrire `RELEASE_NOTES.fr.md` **en français idiomatique et accentué** (vouvoiement, PAS
  un calque mot à mot de l'anglais — et pas d'ASCII strict par contagion d'un e-mail :
  c'est arrivé en beta.13).
- Le rendu HTML est automatique : `build.sh` appelle `scripts/render-release-notes.sh`
  (pandoc) et `generate_appcast` détecte les sidecars `docs/<base>.html` + `.fr.html`
  pour émettre les `<sparkle:releaseNotesLink>` (`xml:lang="fr"` inclus).
- Rattrapage après publication : éditer les `.md`, re-rendre, pousser, puis
  `gh release edit vX.Y --notes-file RELEASE_NOTES.md`. **Ne pas toucher
  `docs/appcast.xml`** : la signature EdDSA du zip publié reste valide.

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
  **le canal est un choix de l'utilisateur depuis la 1.1-beta.20** : Réglages > Mises à jour
  porte « Recevoir les versions bêta » (`Preferences.receivesBetaUpdates`, lu par
  `allowedChannels`). Le défaut reprend l'ancien comportement — vrai si la version installée
  contient « beta » — pour que personne ne change de canal en installant une version.
  Cocher déclenche une vérification immédiate ; décocher ne redescend pas (l'app garde sa
  bêta jusqu'à ce qu'une stable la dépasse, l'écran le dit). Les entrées stables (sans
  canal) restent visibles de tous.
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

- **Le tag est sur le commit de bump** (régression réelle des beta.8 et 9, corrigée
  depuis, à contrôler quand même). `gh` pose le tag côté GitHub seulement :
  `git fetch --tags && git rev-parse vX.Y^{commit}` doit rendre le commit de bump.
- L'asset direct résout : `https://github.com/math65/dsmaccess/releases/download/vX.Y/dsmaccess-X.Y.zip`
- L'appcast charge et liste la nouvelle version : `https://math65.github.io/dsmaccess/appcast.xml`
  (le build Pages prend ~1-2 min après le push — re-sonder avant de conclure à un raté).
- Signature EdDSA de l'appcast cohérente avec le zip publié — `sign_update` vit dans
  `~/Library/Developer/Xcode/DerivedData/dsmaccess-*/SourcePackages/artifacts/sparkle/Sparkle/bin/` :
  `sign_update BuildArtifacts/dsmaccess-X.Y.zip` doit donner la même `sparkle:edSignature`
  que l'appcast.
- Idéal : tester l'updater in-app depuis une install de la version précédente.

### B3. Annoncer (AppleVis)

Canal de retour = **AppleVis** (communauté lecteurs d'écran Apple). Post en anglais,
Markdown, sujet ≤ 64 caractères, titres H4 ou moins, URL directe de l'asset cliquable.
Rédiger la version AppleVis séparément — ne pas réutiliser tel quel le corps GitHub.
L'annonce n'est pas un luxe : deux fois déjà, des testeurs sont restés sur une version
qu'ils croyaient à jour faute d'annonce au fil. Et dire aussi ce qui n'a **pas** marché —
taire un raté connu abîme la confiance plus sûrement que l'avouer.
