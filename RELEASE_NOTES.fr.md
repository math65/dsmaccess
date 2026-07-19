## v1.1-beta.4 (build 5) — 19 juillet 2026

Grosse mise à jour. DSM Access a été repensée autour de macOS : une vraie barre
latérale, des barres d'outils et une fenêtre Réglages standard, le tout entièrement
utilisable au clavier et avec VoiceOver. Elle ajoute aussi plusieurs domaines à
gérer, une sécurité des certificats renforcée et une série de corrections.

### Nouveaux domaines

- File Station, reconstruite : sélection multiple, copier, couper, coller, envois
  et téléchargements, création de dossiers, recherche, et liens de partage avec mot
  de passe et date d'expiration facultatifs. Un panneau d'informations indique la
  taille, le type, le propriétaire, les autorisations et les chemins.
- Utilisateurs et groupes.
- Download Station.
- Gestionnaire de machines virtuelles.
- Container Manager, avec le journal de chaque conteneur.
- Surveillance Station, avec les instantanés des caméras.
- Journaux et sécurité.
- Plusieurs NAS : enregistrez plusieurs serveurs et passez de l'un à l'autre.

### Une app plus native

- Une barre latérale standard regroupe tout en sections — Vue d'ensemble, Fichiers
  et partage, Administration, Applications — avec un raccourci clavier par module.
- Une fenêtre Réglages native (Commande-virgule) permet de choisir les annonces que
  vous entendez et d'afficher, masquer ou réordonner les modules de la barre latérale.
- Les actions courantes sont désormais dans la barre d'outils et la barre des menus,
  avec des raccourcis standard.

### Sécurité

- DSM Access vérifie maintenant le certificat de votre NAS. Un certificat
  auto-signé n'est accepté qu'après que vous ayez approuvé son empreinte une fois ;
  ce choix est retenu pour ce serveur, et vous êtes de nouveau consulté si le
  certificat change par la suite. Cela remplace l'ancien comportement qui acceptait
  n'importe quel certificat — ce qui compte si votre NAS est joignable depuis
  l'extérieur.

### Accessibilité

- Libellés VoiceOver, déplacement du focus et retours parlés sur chaque écran et
  dans chaque état : chargement, contenu vide, erreur et réussite.
- Les annonces sont mises en file d'attente : les mises à jour rapides se lisent
  l'une après l'autre au lieu de se couper.

### Corrections

- Le détail d'un conteneur s'ouvre de nouveau sans accroc et affiche l'usage du
  processeur, la mémoire et l'heure de démarrage.
- Le journal des conteneurs se charge correctement.
- Les journaux système affichent leur message complet sur chaque ligne.
- Dans les fichiers, un clic droit sur plusieurs éléments sélectionnés conserve
  toute la sélection, et le titre de la fenêtre suit désormais le dossier courant.

### Remerciements

- Cette version est en grande partie l'œuvre d'Ashley Cox : la refonte native, les
  nouveaux modules et la sécurité des certificats lui reviennent. Merci, Ashley,
  pour cette contribution exceptionnelle.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.4.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.4/dsmaccess-1.1-beta.4.zip)
