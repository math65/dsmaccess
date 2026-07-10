# DSM Access

**FR** — Un client macOS natif et **accessible** pour administrer un NAS Synology, pensé
en priorité pour les utilisateurs de **VoiceOver**. Il remplace l'interface web DSM,
difficilement utilisable au lecteur d'écran, par une application SwiftUI où chaque écran
est correctement étiqueté, ordonné et annoncé.

**EN** — A native, **accessible** macOS client to manage a Synology NAS, built first and
foremost for **VoiceOver** users. It replaces the DSM web interface — hard to use with a
screen reader — with a SwiftUI app where every screen is properly labeled, ordered and
announced.

---

## 🇫🇷 Français

### Pourquoi ce projet
L'administration web de DSM (Synology) est peu exploitable avec VoiceOver sur Mac.
DSM Access vise une expérience 100 % accessible : navigation clavier logique, libellés
explicites, annonces des chargements et des erreurs, gestion du focus à chaque écran.

### État actuel
- ✅ **Connexion au NAS** en adresse locale (HTTP/HTTPS, certificat auto-signé géré), avec option **« Rester connecté »** (reconnexion automatique au lancement)
- ✅ Prise en charge de la **double authentification** (code de vérification si DSM le demande)
- ✅ **File Station complet** : navigation, téléchargement (un dossier arrive en ZIP), créer/renommer/supprimer, envoi de fichiers, copier/déplacer, liens de partage (mot de passe + expiration)
- ✅ **Informations système** (modèle, version DSM, mémoire, uptime, température)
- ✅ **Stockage** : volumes et disques (santé, température, capacité), groupes de stockage/RAID
- ✅ **Moniteur de ressources** en temps réel (CPU, mémoire, réseau)
- ✅ **Mises à jour automatiques** via **Sparkle**
- ✅ **Multilingue** : français et anglais

### Télécharger
Dernière version, **notariée par Apple** (s'ouvre sans avertissement Gatekeeper) :
**[Télécharger DSM Access](https://github.com/math65/dsmaccess/releases/latest)** — macOS 14 (Sonoma) ou ultérieur.
Une fois installée, l'app se met à jour toute seule via Sparkle.

### Feuille de route
- 👥 Utilisateurs & dossiers partagés
- 📦 Paquets / Docker (Container Manager)
- 💽 Actions de stockage (test SMART, etc.)

### Prérequis
- macOS 14 (Sonoma) ou ultérieur
- Un NAS Synology sous DSM 7
- Xcode 26 pour compiler

### Compilation
```bash
git clone https://github.com/math65/dsmaccess.git
cd dsmaccess
open dsmaccess.xcodeproj   # puis Cmd+R dans Xcode
```
> Note : le projet est signé avec un identifiant d'équipe Apple personnel
> (`DEVELOPMENT_TEAM`). Remplacez-le par le vôtre dans les réglages de la cible pour
> compiler sur votre machine.

### Confidentialité
Aucune donnée n'est envoyée à un tiers. L'app communique uniquement avec **votre** NAS.
Les identifiants ne sont pas écrits en clair ; le jeton d'appareil est conservé dans le
**Trousseau** macOS.

---

## 🇬🇧 English

### Why this project
DSM's web admin (Synology) is barely usable with VoiceOver on Mac. DSM Access aims for a
fully accessible experience: logical keyboard navigation, explicit labels, loading/error
announcements, and focus management on every screen.

### Current status
- ✅ **NAS login** over local address (HTTP/HTTPS, self-signed certificate handled), with a **"stay signed in"** option (automatic reconnection at launch)
- ✅ **Two-factor authentication** support (verification code when DSM requires it)
- ✅ **Full File Station**: browsing, downloads (a folder comes down as a ZIP), create/rename/delete, uploads, copy/move, share links (password + expiry)
- ✅ **System information** (model, DSM version, memory, uptime, temperature)
- ✅ **Storage**: volumes and disks (health, temperature, capacity), storage pools/RAID
- ✅ **Resource monitor** in real time (CPU, memory, network)
- ✅ **Automatic updates** via **Sparkle**
- ✅ **Localized** in French and English

### Download
Latest build, **notarized by Apple** (opens with no Gatekeeper warning):
**[Download DSM Access](https://github.com/math65/dsmaccess/releases/latest)** — macOS 14 (Sonoma) or later.
Once installed, the app updates itself via Sparkle.

### Roadmap
- 👥 Users & shared folders
- 📦 Packages / Docker (Container Manager)
- 💽 Storage actions (SMART test, etc.)

### Requirements
- macOS 14 (Sonoma) or later
- A Synology NAS running DSM 7
- Xcode 26 to build

### Building
```bash
git clone https://github.com/math65/dsmaccess.git
cd dsmaccess
open dsmaccess.xcodeproj   # then Cmd+R in Xcode
```
> Note: the project is signed with a personal Apple team ID (`DEVELOPMENT_TEAM`). Replace
> it with your own in the target settings to build on your machine.

### Privacy
No data is sent to any third party. The app talks only to **your** NAS. Credentials are
never stored in clear text; the device token is kept in the macOS **Keychain**.

---

## Licence / License
[MIT](LICENSE) © 2026 Mathieu Martin
