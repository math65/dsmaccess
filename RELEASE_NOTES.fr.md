## v1.1-beta.5 (build 6) — 19 juillet 2026

### En bref

- Corrige un problème de connexion apparu dans la beta.4 : l'approbation du
  certificat de votre NAS fonctionne à nouveau, au lieu de voir la demande de
  confiance revenir sans arrêt.

### Corrections

- Lorsque macOS ne reconnaît pas le certificat de votre NAS, l'approuver une fois
  vous connecte désormais du premier coup, et le choix est retenu pour ce serveur.
  Dans la beta.4, l'approbation n'était pas prise en compte : la demande de
  confiance revenait en boucle et vous restiez bloqué sur l'écran de connexion.

### Remerciements

- Merci à Ashley Cox, qui a identifié et corrigé ce problème.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.5.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.5/dsmaccess-1.1-beta.5.zip)
