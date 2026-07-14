## v1.1-beta.3 (build 4) — 14 juillet 2026

Cette bêta apporte deux nouveautés et corrige un souci de connexion — le tout
issu directement de vos retours. Merci.

### Nouveautés

- Panneau de configuration : une nouvelle section « Panneau de configuration »
  fait son entrée, en commençant par « Réseau et identité ». Elle affiche le nom
  de votre serveur, l'adresse IP locale, le masque de sous-réseau, la passerelle,
  les serveurs DNS, l'IPv6 et l'interface réseau, dans des fiches claires et
  accessibles. Cette première étape est en lecture seule ; le renommage du
  serveur suivra.
- Centre de paquets : vous pouvez désormais appliquer une mise à jour de paquet,
  et non plus seulement constater qu'elle est disponible. Quand un paquet
  officiel Synology a une mise à jour, un bouton « Mettre à jour » l'installe —
  c'est le NAS qui gère le téléchargement et l'installation. Cette nouveauté est
  toute fraîche et je n'ai pas pu la tester complètement de mon côté : essayez-la
  et dites-moi ce que ça donne. Une précision honnête : quelques mises à jour
  demandent un redémarrage du NAS pour se terminer — l'app vous prévient, mais ce
  redémarrage-là, vous le lancez depuis DSM.

### Corrections

- Connexion : l'erreur occasionnelle « délai dépassé » à la connexion a disparu.
  L'app relance désormais cette première requête automatiquement et
  silencieusement, si bien qu'une connexion « à froid » n'échoue plus au premier
  essai.

Chaque écran conserve l'approche VoiceOver : libellés clairs, ordre de focus
logique, et annonces vocales au chargement, en cas d'erreur et après chaque
action.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.3.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.3/dsmaccess-1.1-beta.3.zip)
