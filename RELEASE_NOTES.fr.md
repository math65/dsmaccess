## v1.1-beta.3 (build 4) — 14 juillet 2026

Cette bêta ajoute les informations d'identité réseau et la mise à jour des
paquets, avec une meilleure reprise après un délai d'attente dépassé.

### Nouveautés

- Panneau de configuration : le nouvel aperçu « Réseau et identité », en lecture
  seule, affiche le nom du serveur, l'adresse IP locale, le masque de sous-réseau,
  la passerelle, les serveurs DNS, l'adresse IPv6 et l'interface réseau.
- Centre de paquets : les mises à jour des paquets officiels Synology peuvent
  désormais être confirmées et installées depuis l'app. Le NAS télécharge,
  installe et redémarre le paquet. Si une mise à jour exige un redémarrage du NAS,
  terminez l'opération depuis DSM.

### Corrections

- Les connexions et les lectures reprennent après un délai d'attente dépassé
  grâce à une seconde tentative automatique. Les actions d'administration ne
  sont jamais relancées automatiquement.

Les deux nouveautés proposent des libellés VoiceOver explicites, un focus adapté
aux états de chargement et d'erreur, ainsi que des annonces de progression et de
résultat.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.3.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.3/dsmaccess-1.1-beta.3.zip)
