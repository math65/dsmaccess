## v1.1-beta.11 (build 12) — 27 juillet 2026

### En bref

- Connexion : les comptes sans droits d'administration peuvent à nouveau se
  connecter. Toute personne à qui vous avez créé un compte sur votre NAS peut
  utiliser DSM Access, et pas seulement vous.

### Corrections

- Connexion : un compte qui n'est pas administrateur était refusé avec
  « Permission refusée pour ce compte », alors que ce même compte entrait sans
  difficulté dans DSM depuis un navigateur.
- Utilisateurs et groupes : la création d'un utilisateur échouait sur un simple
  code d'erreur lorsque le mot de passe ne respectait pas les règles imposées
  par votre NAS. Le message dit maintenant ce qui s'est passé, et le formulaire
  énonce ces règles avant même que vous ne saisissiez quoi que ce soit.
- Utilisateurs et groupes : une création qui échoue ne referme plus la fenêtre
  en effaçant tout ce que vous aviez saisi. Le message s'affiche sur place et
  vous corrigez le mot de passe sans tout recommencer.

### Nouveautés

- Connexion : lorsque votre NAS exige un nouveau mot de passe avant d'autoriser
  un compte, DSM Access vous le demande et vous connecte dans la foulée, au
  lieu de s'arrêter sur une erreur contre laquelle vous ne pouviez rien.
- Utilisateurs et groupes : un bouton génère un mot de passe conforme aux
  règles de votre NAS. Il s'affiche en clair pour que vous puissiez le relire,
  et un second bouton le copie, afin de le transmettre à la personne concernée.
  Les caractères qui se ressemblent à l'oreille et à la lecture en sont
  écartés : il supporte d'être dicté ou recopié.

### Téléchargement

[dsmaccess-1.1-beta.11.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.11/dsmaccess-1.1-beta.11.zip)

## v1.1-beta.10 (build 11) — 25 juillet 2026

### En bref

- Fichiers : copiez des fichiers dans le Finder, puis collez-les dans un
  dossier du NAS avec Commande-V. Les dossiers entiers suivent, avec tout ce
  qu'ils contiennent.
- Fichiers : faites glisser un élément hors de la liste et déposez-le dans le
  Finder pour l'y télécharger.
- Copier-coller se comporte maintenant comme dans le Finder : Commande-C
  copie, Commande-V colle une copie, Commande-Option-V déplace. La commande
  Couper n'existe plus.

### Nouveautés

- Fichiers : Commande-V envoie ce que vous avez copié dans le Finder vers le
  dossier où vous êtes. Les fichiers y sont déposés ; un dossier est recréé
  sur le NAS avec toute son arborescence, sous-dossiers vides compris. Les
  fichiers .DS_Store du Finder sont écartés, et si un élément de votre Mac ne
  peut pas être lu, le transfert se déclare incomplet au lieu de laisser
  croire que tout est passé.
- Fichiers : un élément peut être glissé hors de la liste et déposé dans le
  Finder. Rien n'est téléchargé avant le dépôt, et un dossier arrive sous
  forme d'archive ZIP, exactement comme avec Télécharger. Télécharger reste
  la voie clavier et ne change pas.
- Fichiers : l'envoi vers le NAS accepte désormais les dossiers autant que
  les fichiers, et les options affichées avant un transfert indiquent combien
  de fichiers et combien de dossiers partent.

### Modifications

- Fichiers : Couper disparaît. Commande-C copie, Commande-V colle une copie et
  Commande-Option-V déplace ce que vous avez copié — le choix se fait au
  moment de coller, comme dans le Finder. Le menu Fichiers propose maintenant
  Déplacer ici à côté de Coller, et la confirmation annonce ce qu'un
  déplacement va faire. Déplacer des fichiers venus de votre Mac est refusé,
  avec l'explication : cela supprimerait vos originaux.
- Mises à jour : l'app cherche une nouvelle version à chaque lancement. La
  planification de Sparkle ne vérifie au mieux qu'une fois par jour, ce qui
  laissait un testeur une version en retard dès que deux builds sortaient le
  même jour. Rien ne s'affiche s'il n'y a pas de mise à jour, et le réglage du
  panneau des mises à jour décide toujours si la vérification a lieu.
- Mises à jour : la vérification automatique est maintenant le réglage par
  défaut déclaré par l'app, au lieu d'une préférence écrite à votre place au
  premier lancement — une préférence que vous n'avez jamais choisie, et qui
  faisait taire la question que Sparkle pose lui-même. Le panneau des mises à
  jour reste le seul endroit où changer cela.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.10.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.10/dsmaccess-1.1-beta.10.zip)

## v1.1-beta.9 (build 10) — 23 juillet 2026

### En bref

- Nouveau module USB Copy : configurez et lancez vos copies USB entièrement
  depuis l'app — les sélecteurs de l'interface web de DSM sont inutilisables
  au lecteur d'écran, il fallait jusqu'ici une aide voyante. Une contribution
  d'Ashley Cox.
- Fichiers : l'envoi de fichiers vers le NAS fonctionne à nouveau. Une mise à
  jour de DSM avait discrètement cassé tous les envois.
- DSM Access a désormais sa propre icône, dessinée elle aussi par Ashley Cox.

### Nouveautés

- USB Copy : chaque tâche s'affiche avec son sens de copie, ses dossiers et
  son état ; créez des tâches d'import ou d'export avec de vrais sélecteurs de
  dossiers accessibles pour la source et la destination ; choisissez le mode
  de copie, la rotation des versions, les filtres de fichiers et la
  planification ; exécutez, annulez, activez, désactivez ou supprimez une
  tâche ; consultez le journal du paquet et réglez ses paramètres généraux.
  Les opérations risquées expliquent leur conséquence et demandent
  confirmation — une tâche miroir prévient qu'elle supprime à destination, et
  la suppression d'une tâche la nomme. Le module n'apparaît que si le paquet
  USB Copy est installé sur le NAS.

### Corrections

- Fichiers : l'envoi d'un fichier se soldait par une erreur depuis le passage
  du NAS à la dernière mise à jour de DSM 7.4, qui a changé la façon dont DSM
  attend les envois. L'app suit désormais la même convention que le File
  Station de DSM et les envois fonctionnent à nouveau — y compris le choix
  entre remplacer ou ignorer un fichier existant.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.9.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.9/dsmaccess-1.1-beta.9.zip)

## v1.1-beta.8 (build 9) — 23 juillet 2026

### En bref

- L'app s'affiche désormais en anglais quand la langue du Mac n'est ni le
  français ni l'anglais — sans rien configurer.
- Centre de paquets : le sélecteur entre paquets installés et catalogue
  officiel fait maintenant partie de l'écran lui-même, là où VoiceOver le
  trouve naturellement.

### Corrections

- Centre de paquets : le sélecteur Installés / Catalogue officiel se trouvait
  dans la barre d'outils de la fenêtre, une zone que VoiceOver traite à part
  sans jamais signaler qu'un choix s'y trouve. Le sélecteur est désormais en
  tête de l'écran, dans l'ordre de lecture, annoncé comme un vrai choix à
  deux options.
- Centre de paquets : avec un compte sans droits d'administration, l'onglet
  Catalogue affichait un message trompeur « Aucun paquet correspondant ». Il
  explique maintenant que DSM réserve le catalogue aux comptes administrateurs.
- Langue : sur un Mac réglé dans une langue que l'app ne propose pas (le
  hongrois, par exemple), l'app s'affichait en français. Elle s'affiche
  désormais en anglais, et le choix d'une langue pour l'app dans Réglages
  Système fonctionne comme prévu.
- VoiceOver : les listes principales se présentent désormais — « Fichiers et
  dossiers », « Dossiers partagés », « Utilisateurs », « Groupes », « Services
  de fichiers », « Paquets installés », « Pools, volumes et disques » — au lieu
  d'annoncer un tableau anonyme. Les lignes des Dossiers partagés annoncent
  aussi correctement leur nature.
- VoiceOver : le sélecteur du Centre de paquets n'annonce plus son nom deux
  fois.
- Lisibilité : les textes d'état et de détail dans toute l'app — état des
  paquets, versions, santé des disques, détails des journaux, résumés en bas
  d'écran — sont nettement plus foncés et respectent le contraste recommandé
  pour les petits textes, en mode clair comme en mode sombre. Un vrai plus en
  cas de basse vision.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.8.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.8/dsmaccess-1.1-beta.8.zip)

## v1.1-beta.7 (build 8) — 22 juillet 2026

### En bref

- L'installation d'un fichier de paquet (.spk) fonctionne désormais : elle
  échouait systématiquement avec une erreur du NAS (code 101).
- L'app vérifie elle-même les mises à jour au lancement, et un nouveau panneau
  de réglages permet de les installer automatiquement, sans dialogue.

### Nouveautés

- Réglages > Mises à jour : la vérification au lancement est désormais active
  d'office (désactivable), et une option « Télécharger et installer
  automatiquement » installe la nouvelle version à la fermeture de l'app —
  plus besoin de répondre à un dialogue à chaque mise à jour. Le panneau
  affiche aussi la version installée et un bouton de vérification immédiate.

### Corrections

- Paquets : installer ou mettre à jour un paquet depuis un fichier .spk
  téléchargé par vos soins aboutit maintenant, au lieu d'échouer aussitôt avec
  une erreur du NAS (code 101). L'app dialogue désormais avec le Centre de
  paquets exactement comme DSM lui-même, vérifié sous DSM 7.4.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.7.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.7/dsmaccess-1.1-beta.7.zip)

## v1.1-beta.6 (build 7) — 21 juillet 2026

### En bref

- Connectez-vous avec QuickConnect : saisissez votre identifiant QuickConnect
  au lieu d'une adresse et d'un port, et l'app trouve elle-même le meilleur
  chemin vers votre NAS.
- Le Centre de paquets devient un module complet : parcourez le catalogue
  officiel Synology et installez, mettez à jour, réparez ou désinstallez vos
  paquets sans quitter l'app — et l'installation fonctionne désormais de façon
  fiable sous DSM 7.4.
- Fichiers gagne les fonctions qui manquaient encore : informations détaillées,
  recherche avancée, favoris, liens de partage, exploration d'archives et
  progression des transferts.
- La création d'utilisateurs fonctionne à nouveau sous DSM 7.4, et le nombre de
  membres des groupes est correct.

### Nouveautés

- Connexion par QuickConnect : choisissez « QuickConnect » sur l'écran de
  connexion, saisissez votre identifiant QuickConnect et votre compte DSM
  habituel. L'app privilégie une route directe et vérifiée vers votre NAS, et
  ne passe par le relais Synology qu'en dernier recours — toujours en HTTPS.
  À savoir : QuickConnect n'a pas d'interface publique officielle, Synology
  peut donc faire évoluer ce service sans préavis.
- Paquets : parcourez le catalogue officiel, installez un paquet en une action,
  ou installez un fichier de paquet (.spk) téléchargé par vos soins. Mises à
  jour, réparations et désinstallations se font depuis la même liste, avec une
  confirmation claire avant chaque opération.
- Paquets : gérez les sources de paquets et les réglages du Centre de paquets
  depuis l'app.
- Fichiers : consultez les informations complètes d'un fichier ou d'un dossier,
  cherchez selon des critères avancés (nom, type, taille, dates, propriétaire)
  et gérez vos favoris.
- Fichiers : créez et gérez des liens de partage, mot de passe et date
  d'expiration compris.
- Fichiers : explorez le contenu d'une archive et n'extrayez que ce dont vous
  avez besoin.
- Fichiers : les envois et téléchargements affichent leur progression, et les
  copies ou déplacements vous demandent votre avis avant d'écraser quoi que ce
  soit.
- Un formulaire de contact dans le menu Aide vous permet d'écrire au développeur
  directement depuis l'app ; des annonces ponctuelles peuvent s'afficher au
  lancement.

### Corrections

- Comptes : la création d'un utilisateur sous DSM 7.4 n'échoue plus avec une
  erreur de permission, le nombre de membres des groupes est exact, et en cas de
  problème l'app vous le dit clairement au lieu d'échouer en silence.
- Paquets : installer ou mettre à jour un paquet sous DSM 7.4 ne se solde plus
  par une erreur du NAS.
- VoiceOver : à l'ouverture de Fichiers, plus d'annonce « Dossier vide » pendant
  le chargement — vous entendez directement le vrai nombre d'éléments.
- VoiceOver : si votre session expire et que l'app se reconnecte
  automatiquement, un avis vous explique désormais que l'opération en cours a
  été interrompue, au lieu de vous ramener à la vue d'ensemble sans un mot.

### Remerciements

- Merci à Ashley Cox pour le travail sur QuickConnect, File Station et le
  Centre de paquets, au cœur de cette version.

### Configuration requise

- macOS 14 (Sonoma) ou version ultérieure.
- Un NAS Synology sous DSM 7 sur votre réseau local.

### Téléchargement

[dsmaccess-1.1-beta.6.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.6/dsmaccess-1.1-beta.6.zip)

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
