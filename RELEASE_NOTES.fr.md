## v1.1-beta.15 (build 16) — 29 juillet 2026

### En bref

- Fichiers : la création d'un lien de partage fonctionne à nouveau. Depuis la
  beta.6, elle échouait à chaque fois sur « la réponse du NAS n'a pas pu être
  lue », alors que le NAS avait bel et bien créé le lien. Si vous avez essayé
  pendant cette période, ces liens vous attendent dans la liste des liens de
  partage, à utiliser ou à supprimer.

### Corrections

- Fichiers : un lien de partage est créé et vous est rendu comme avant. L'app
  exigeait une information que DSM n'envoie qu'en cas d'échec, et jetait la
  réponse entière quand elle était, à juste titre, absente.
- Fichiers : sur certains modèles de NAS, l'écran Fichiers lui-même pouvait
  refuser de s'ouvrir, pour la même raison. Il ne dépend plus de détails que
  votre NAS n'est pas tenu de fournir.
- Fichiers : la fenêtre des tâches suit à nouveau une tâche en cours. Elle
  affichait la progression qu'elle avait à son ouverture et n'en bougeait plus,
  ce qui donnait l'impression qu'une longue compression restait bloquée à un
  pour cent.
- Fichiers : une compression terminée n'est plus présentée comme une opération
  interrompue. Le NAS retire une tâche achevée au lieu de l'annoncer, et ce
  silence était pris pour un échec.

### Nouveautés

- Fichiers : coller ou déplacer nomme désormais le dossier dans lequel les
  éléments vont atterrir, avant que vous validiez. Sélectionner un dossier dans
  la liste n'en fait pas la destination : il faut l'avoir ouvert, comme dans le
  Finder.
- Fichiers : à la création d'une archive, vous pouvez choisir l'encodage des
  noms qu'elle contient, pour une archive destinée à être ouverte sur un autre
  système.
- Quand l'app ne parvient pas à comprendre une réponse de votre NAS, elle le
  dit et propose de la signaler. Signaler ouvre le formulaire de contact, déjà
  rempli, en y joignant l'appel qui a échoué et le nom des champs que votre NAS
  a envoyés — jamais leur contenu, donc aucun nom de fichier, chemin ou compte
  ne quitte votre machine.

## v1.1-beta.14 (build 15) — 28 juillet 2026

### En bref

- Connexion : vous pouvez désormais ouvrir une session sans saisir le moindre
  mot de passe, en approuvant la demande dans l'app Synology Secure SignIn sur
  votre téléphone.
- Fichiers : une copie longue n'est plus abandonnée au bout de cinq minutes, et
  quitter l'écran Fichiers ne l'interrompt plus.

### Nouveautés

- Connexion : un menu Authentification, sur l'écran de connexion, choisit entre
  votre mot de passe et l'approbation envoyée sur votre téléphone. Avec la
  seconde, le champ du mot de passe s'efface et un écran d'attente vous indique
  quoi faire, en annonçant le chiffre à confirmer quand votre NAS en demande un.
  La session ainsi ouverte devra être approuvée de nouveau à la prochaine
  ouverture de l'app, ce que l'écran précise.
- Mise à jour DSM : un nouvel écran présente la mise à jour proposée par votre
  NAS et l'installe, en annonçant la progression au fil de l'opération.

### Corrections

- Fichiers : copier, déplacer, supprimer, compresser ou extraire était
  abandonné au bout de cinq minutes exactement, et présenté comme un échec,
  alors que le NAS poursuivait sans rien dire. Une copie de plusieurs heures est
  désormais suivie jusqu'au bout.
- Fichiers : passer à un autre écran pendant une copie l'arrêtait pour de bon
  sur le NAS. Elle continue maintenant, et revenir dans Fichiers en reprend le
  suivi, même après avoir quitté et rouvert l'app. Seul le bouton Annuler
  interrompt une tâche.
- Fichiers : le résultat d'une opération longue reste affiché jusqu'à ce que
  vous le masquiez. Une annonce vocale émise pendant que l'app est en
  arrière-plan n'est jamais entendue, et ne laissait aucune trace de ce qui
  s'était passé.
- Fichiers : un dossier contenant un fichier dont le nom n'était pas enregistré
  en Unicode ne s'ouvrait pas du tout — un seul nom sur trois mille rendait le
  dossier entier inaccessible. Il s'ouvre désormais, ce nom-là affichant un
  caractère de remplacement, comme le fait DSM lui-même.

### Téléchargement

[dsmaccess-1.1-beta.14.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.14/dsmaccess-1.1-beta.14.zip)

## v1.1-beta.13 (build 14) — 28 juillet 2026

### En bref

- Utilisateurs et groupes : les groupes auxquels un compte appartient peuvent
  désormais être modifiés après coup, et plus seulement à la création.

### Nouveautés

- Utilisateurs et groupes : l'écran des permissions gagne un onglet Groupes, à
  côté des dossiers partagés et des applications. Il présente tous les groupes
  du NAS, cochés pour ceux auxquels le compte appartient, et s'enregistre avec
  le reste.

### Téléchargement

[dsmaccess-1.1-beta.13.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.13/dsmaccess-1.1-beta.13.zip)

## v1.1-beta.12 (build 13) — 28 juillet 2026

### En bref

- Utilisateurs et groupes : vous pouvez désormais donner à un compte l'accès à
  vos dossiers partagés et aux applications de votre NAS, sans quitter DSM
  Access. Créer un compte à quelqu'un et lui permettre de s'en servir
  redeviennent une seule et même tâche.

### Nouveautés

- Utilisateurs et groupes : un écran Permissions présente chaque dossier
  partagé avec l'accès accordé au compte, celui dont il hérite de ses groupes,
  et les quatre choix proposés par DSM. Il se lit comme un tableau, une ligne
  par dossier, et se parcourt aux flèches.
- Utilisateurs et groupes : un second onglet fait de même pour les
  applications. C'est là que se décide si quelqu'un peut ouvrir DSM, File
  Station, Synology Photos ou se connecter en SMB. Rien n'est envoyé au NAS
  avant l'enregistrement, et seul ce que vous avez modifié part.
- Utilisateurs et groupes : le même écran fonctionne sur un groupe. Donnez les
  droits une fois au groupe, ajoutez-y des personnes, et chacune en hérite sans
  que vous ayez à recommencer. C'est la façon commode d'organiser les accès
  d'une famille.
- Utilisateurs et groupes : la fenêtre de création propose d'ouvrir les
  permissions du compte qu'elle vient de créer, pour ne plus avoir à le
  retrouver dans la liste avant de lui donner le moindre accès.

### Corrections

- Utilisateurs et groupes : les groupes choisis à la création d'un compte
  étaient perdus en silence. Le compte était bien créé, mais n'appartenait à
  aucun d'eux. Il arrive maintenant dans les groupes que vous avez cochés.

### Accessibilité

- Utilisateurs et groupes : une application déjà restreinte à des adresses
  précises reste en lecture, avec une explication, plutôt que d'être réécrite
  sans prévenir en « depuis n'importe où ».
- Utilisateurs et groupes : lorsqu'un groupe se voit refuser un dossier,
  l'écran le signale sur la ligne concernée, car ce refus l'emporte sur ce que
  le compte a reçu par ailleurs.
- Utilisateurs et groupes : l'écran n'affiche qu'un bouton Fermer tant que rien
  n'a été modifié, au lieu d'un Annuler qui laisse croire qu'on revient sur
  quelque chose et d'un Enregistrer estompé sans explication.

### Téléchargement

[dsmaccess-1.1-beta.12.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.12/dsmaccess-1.1-beta.12.zip)

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
