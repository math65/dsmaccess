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
- ✅ **Connexion au NAS** en adresse locale (HTTPS par défaut, approbation explicite de l'empreinte des certificats auto-signés), avec option **« Rester connecté »**
- ✅ Prise en charge de la **double authentification** (code de vérification si DSM le demande)
- ✅ **File Station** : navigation, téléchargement (un dossier arrive en ZIP), créer/renommer/supprimer, envoi de fichiers, copier/déplacer, liens de partage (mot de passe + expiration)
- ✅ **Informations système** (modèle, version DSM, mémoire, uptime, température)
- ✅ **Stockage** : volumes et disques (santé, température, capacité), groupes de stockage/RAID
- ✅ **Moniteur de ressources** en temps réel (CPU, mémoire, réseau)
- ✅ **Administration** des dossiers partagés, services de fichiers, utilisateurs, groupes et paquets
- ✅ **Container Manager** : conteneurs, projets Compose, images, réseaux et journal — démarrer, arrêter, redémarrer, reconstruire un projet, mettre à jour ou supprimer une image, le tout en tableaux triables
- ✅ **Applications** : Download Station, Virtual Machine Manager et Surveillance Station
- ✅ **Journaux et sécurité** : journal système et déblocage d'adresses lorsque les API sont exposées
- ✅ **Mises à jour automatiques** via **Sparkle**
- ✅ **Multilingue** : français et anglais

### Télécharger
Dernière version, **notariée par Apple** (s'ouvre sans avertissement Gatekeeper) :
**[Télécharger DSM Access](https://github.com/math65/dsmaccess/releases/latest)** — macOS 14 (Sonoma) ou ultérieur.
Une fois installée, l'app se met à jour toute seule via Sparkle.

### Feuille de route
- 💽 Actions de stockage (tests SMART, maintenance et progression des tâches)
- 🧪 Validation de compatibilité sur davantage de modèles de NAS et versions de DSM
- 🔌 Couverture supplémentaire des API publiées par Synology

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
DSM Access ne contient ni télémétrie ni publicité. Les opérations d'administration et les
données du NAS sont échangées uniquement avec **votre** NAS. Sparkle consulte l'appcast du
projet sur GitHub Pages et les fichiers de version publiés sur GitHub afin de rechercher et
télécharger les mises à jour. Les mots de passe, jetons d'appareil et empreintes de
certificats approuvées sont conservés dans le **Trousseau** macOS.

---

## 🇬🇧 English

### Why this project
DSM's web admin (Synology) is barely usable with VoiceOver on Mac. DSM Access aims for a
fully accessible experience: logical keyboard navigation, explicit labels, loading/error
announcements, and focus management on every screen.

### Current status
- ✅ **NAS login** over a local address (HTTPS by default, explicit fingerprint approval for self-signed certificates), with a **"stay signed in"** option
- ✅ **Two-factor authentication** support (verification code when DSM requires it)
- ✅ **File Station**: browsing, downloads (a folder comes down as a ZIP), create/rename/delete, uploads, copy/move, share links (password + expiry)
- ✅ **System information** (model, DSM version, memory, uptime, temperature)
- ✅ **Storage**: volumes and disks (health, temperature, capacity), storage pools/RAID
- ✅ **Resource monitor** in real time (CPU, memory, network)
- ✅ **Administration** of shared folders, file services, users, groups, and packages
- ✅ **Container Manager**: containers, Compose projects, images, networks, and log — start, stop, restart, rebuild a project, update or delete an image, all in sortable tables
- ✅ **Applications**: Download Station, Virtual Machine Manager, and Surveillance Station
- ✅ **Logs and security**: system logs and address unblocking when DSM exposes the APIs
- ✅ **Automatic updates** via **Sparkle**
- ✅ **Localized** in French and English

### Download
Latest build, **notarized by Apple** (opens with no Gatekeeper warning):
**[Download DSM Access](https://github.com/math65/dsmaccess/releases/latest)** — macOS 14 (Sonoma) or later.
Once installed, the app updates itself via Sparkle.

### Roadmap
- 💽 Storage actions (SMART tests, maintenance, and task progress)
- 🧪 Compatibility validation across more NAS models and DSM releases
- 🔌 Broader coverage of Synology's published APIs

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
DSM Access contains no telemetry or advertising. NAS administration operations and NAS data
are exchanged only with **your** NAS. Sparkle contacts the project's GitHub Pages appcast
and release files hosted on GitHub to check for and download updates. Passwords, device
tokens, and approved certificate fingerprints are stored in the macOS **Keychain**.

---

## Licence / License
[MIT](LICENSE) © 2026 Mathieu Martin
