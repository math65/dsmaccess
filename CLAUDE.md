# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet
DSM Access — client macOS SwiftUI natif et **accessible VoiceOver** pour administrer un NAS Synology, en remplacement de l'admin web DSM inutilisable au lecteur d'écran. Cible macOS 14 (Sonoma), Swift 5 (isolation MainActor par défaut, approachable concurrency), aucune dépendance externe.

## Build & lancement
- Build : `xcodebuild -project dsmaccess.xcodeproj -scheme dsmaccess -destination 'platform=macOS' build`
- L'app compilée est dans `~/Library/Developer/Xcode/DerivedData/dsmaccess-*/Build/Products/Debug/dsmaccess.app` (lancer avec `open`).
- Les cibles `dsmaccessTests` / `dsmaccessUITests` ne sont que des squelettes vides.

## Ajouter des fichiers
- Le projet utilise un **groupe synchronisé** (`PBXFileSystemSynchronizedRootGroup`, Xcode 26) : tout fichier créé sous `dsmaccess/` est **automatiquement** inclus dans la cible. Ne PAS éditer `project.pbxproj` pour référencer de nouveaux fichiers Swift.
- SourceKit affiche de faux « Cannot find type … » entre fichiers dans cette configuration. Les ignorer ; se fier au `xcodebuild` complet.

## Accessibilité — exigence centrale
C'est la raison d'être du projet. Chaque vue doit avoir : libellés VoiceOver explicites, ordre de focus logique, annonces de chargement/erreur (`AccessibilityNotification.Announcement`), et repositionnement du focus (`@AccessibilityFocusState`) à chaque changement d'écran. Jamais de spinner ni d'erreur muets.

## Localisation (FR/EN)
- Langue source = **français** ; catalogue `dsmaccess/Localizable.xcstrings` (pas de `fr.lproj` ; seul `en` est traduit).
- Texte dans les vues SwiftUI (`Text`, `Button`, `.accessibilityLabel`…) : se localise seul → ajouter la clé + traduction EN au catalogue.
- Texte hors SwiftUI (ViewModels, erreurs, annonces VoiceOver — type `String`) : **envelopper dans `String(localized:)`**, sinon non traduit.

## Réseau / API Synology
- Passer par `SYNO.API.Info` pour résoudre chemins CGI et versions (ne jamais coder `auth.cgi` / `entry.cgi` en dur) ; joindre `_sid` à toutes les requêtes post-login.
- Étendre via le protocole `DSMClientProtocol` (`Networking/DSMClient.swift`) sans retoucher l'authentification.
- Appels réseau en `async`/`await` uniquement — jamais d'appel bloquant.

## Sandbox
App Sandbox activé + `com.apple.security.network.client` et ATS `NSAllowsLocalNetworking` (Info.plist) pour joindre le NAS en local. Toute nouvelle capacité passe par `dsmaccess/dsmaccess.entitlements`.

## Git
Dépôt perso public `math65/dsmaccess` (solo). Pour une fonctionnalité, travailler sur une branche locale courte puis la fusionner dans `main` soi-même — **pas de PR**. Committer une étape terminée ET vérifiée ; ne pousser que sur demande.
