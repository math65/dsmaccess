## v1.3-beta.2 (build 26) — 6 août 2026

### En bref

- Quand quelque chose échoue, DSM Access le dit désormais dans une boîte de
  dialogue qui reste à l'écran jusqu'à ce que vous la fermiez. Fini les
  erreurs prononcées une fois puis perdues — et un bouton Signaler transmet
  le message au développeur si vous le souhaitez.

### Changements

- Tous les modules : une opération qui échoue — une restauration, une
  suppression, un réglage — ouvre la même boîte de dialogue d'erreur.
  VoiceOver la lit de lui-même, OK la ferme, et Signaler ouvre le formulaire
  de contact prérempli avec l'erreur, que vous relisez avant tout envoi.
- Hyper Backup : télécharger ou restaurer depuis une sauvegarde joue
  désormais le son de fin d'opération, ou envoie une notification quand
  l'app est en arrière-plan — les mêmes signaux que les transferts de
  fichiers.
- Hyper Backup : le téléchargement d'un fichier laisse maintenant au NAS
  jusqu'à cinq minutes pour le préparer. Sur un NAS occupé, ou quand la
  sauvegarde vit sur un autre NAS, l'ancienne limite de vingt secondes
  pouvait couper court avant le premier octet.
- Utilisateurs et groupes, liens de partage, favoris, Centre de paquets et
  tâches File Station affichaient chacun leurs erreurs à leur manière ; tous
  passent par la même boîte de dialogue.

## v1.3-beta.1 (build 25) — 5 août 2026

### En bref

- Nouveau module Hyper Backup : suivez vos sauvegardes et, enfin, restaurez
  depuis elles sans l'écran DSM qui rendait la restauration inquiétante. Une
  sauvegarde se parcourt comme un dossier, et restaurer à côté des originaux
  est le comportement par défaut.

### Hyper Backup

- Le module (⌘⇧6) liste vos tâches de sauvegarde dans un tableau triable,
  avec leur destination, leur état et leur chiffrement. Une sauvegarde en
  cours annonce sa progression en direct. Lancez une sauvegarde, annulez-en
  une avec confirmation, parcourez les versions datées, et lisez le journal
  et les statistiques de la tâche.
- Explorateur de restauration : ouvrez n'importe quelle version et parcourez
  son contenu comme dans le module Fichiers — les flèches pour se déplacer,
  ⌘flèche bas pour ouvrir un dossier, ⌘flèche haut pour remonter. Chaque
  ligne dit son nom, son type, sa taille et sa date, et un élément endommagé
  le dit en toutes lettres.
- « Restaurer vers… » dépose une copie à côté des originaux — la direction
  sûre est celle par défaut. La feuille est elle-même le navigateur de
  dossiers : avancez jusqu'au dossier qui recevra la copie, créez-le au
  passage s'il n'existe pas encore, et une phrase écrite dit ce qui sera
  restauré et où, avant que vous ne confirmiez. Le remplacement de l'existant
  reste éteint tant que vous ne l'activez pas, et sa conséquence est écrite
  noir sur blanc.
- « Restaurer à l'emplacement d'origine… » remet la sélection là d'où elle
  vient. La confirmation nomme ce qui sera remplacé et où — pas seulement
  « vos fichiers originaux ».
- Téléchargez un fichier d'une sauvegarde vers le Mac, en choisissant où il
  arrive, avec une progression annoncée en octets reçus.
- Pas encore là, et dit franchement : la recherche dans une sauvegarde, le
  suivi d'une longue restauration, le déverrouillage des sauvegardes
  chiffrées, la mise en pause d'une sauvegarde, et la création ou la
  suppression de tâches.

### Dossiers partagés

- La création d'un dossier partagé propose désormais la corbeille, sa
  restriction aux administrateurs, les deux options de visibilité et le
  chiffrement. Une nouvelle feuille de réglages apporte les mêmes choix à un
  dossier existant, et un dossier chiffré se verrouille et se déverrouille
  depuis son menu.
- Les réglages gagnent le quota, la compression des fichiers, la somme de
  contrôle des données et les trois restrictions avancées (parcourir,
  modifier, télécharger). La corbeille d'un dossier peut être vidée, et une
  nouvelle feuille montre quels comptes atteignent le dossier, et avec quel
  droit.
- Le chiffrement d'un dossier existant est suivi jusqu'au bout : l'écran dit
  où en est la réécriture, que le dossier reste indisponible pendant ce
  temps, et propose de l'arrêter.
- Corrigé : la colonne Corbeille disait « Non » sur tous les dossiers, même
  ceux où elle est active.

### Changements

- Choisir un dossier du NAS — dans Conteneurs, USB Copy et Hyper Backup —
  passe par un même tableau façon Finder, avec les dossiers partagés à sa
  racine.

## v1.2 (build 24) — 4 août 2026

### En bref

- Conteneurs reçoit un terminal. Vous pouvez ouvrir un interpréteur de commandes
  dans un conteneur en marche et y travailler, avec des réponses présentées pour
  être lues ligne à ligne, au lieu du terminal en forme d'écran qu'affiche DSM
  et qu'aucun lecteur d'écran ne sait suivre.

### Conteneurs

- Terminal : sélectionnez un conteneur, ouvrez Terminal depuis son menu, et une
  session démarre à l'intérieur. Ce que vous envoyez et ce que l'interpréteur
  répond sont présentés comme un échange, un bloc chacun, pour se lire
  séparément. La sortie occupe un champ en lecture seule que vous parcourez
  ligne à ligne et d'où vous pouvez copier, et l'interpréteur est réglé pour
  écrire ses listes une entrée par ligne plutôt qu'en colonnes alignées.
- La session utilise `/bin/sh`, sauf si vous nommez un autre interpréteur avant
  qu'elle ne démarre. Un bouton Interrompre envoie ce qu'enverrait un vrai
  terminal, pour une commande qui n'en finit pas.
- Fermer la fenêtre met fin à la session, et ne laisse rien tourner dans le
  conteneur.
- Container Manager n'accepte un terminal que par une adresse que le NAS
  reconnaît comme la sienne. Si la vôtre est refusée, l'application le dit et
  nomme l'adresse au lieu d'annoncer une erreur de serveur, et elle essaie une
  fois votre nom QuickConnect avant d'abandonner.

## v1.1 (build 23) — 3 août 2026

La première version stable depuis la 1.0, parue le 10 juillet. Si vous venez de
la 1.0, tout ce qui suit est nouveau pour vous.

### En bref

- Sept modules qui n'existaient pas en 1.0 : Moniteur de ressources, Journaux et
  sécurité, Centre de paquets, Conteneurs, USB Copy, Périphériques externes, et
  les permissions dans Utilisateurs et groupes.
- Fichiers dialogue avec le Finder : on copie d'un côté, on colle de l'autre,
  dans les deux sens.
- L'application se met à jour toute seule, et dit ce qu'une opération longue est
  en train de faire pendant qu'elle se déroule.

### Nouveaux modules

- Périphériques externes : une section du Panneau de configuration liste les
  disques USB et eSATA connectés au NAS, avec leur fabricant, leur modèle, leur
  capacité et leur état, et les partitions du disque sélectionné avec leur
  système de fichiers, leurs tailles et leur dossier partagé. Vous pouvez
  éjecter un disque, ou le formater en EXT4, FAT32 ou EXFAT. Un bouton
  d'éjection apparaît dans la barre d'outils dès qu'un disque est branché.
- Moniteur de ressources : processeur, mémoire, réseau et disques, ainsi que les
  fichiers ouverts, les alertes enregistrées par le NAS et les connexions en
  cours. Vous pouvez mettre fin à une session qui n'a rien à faire là.
- Journaux et sécurité : les quatre journaux tenus par le NAS, et non plus un
  seul, avec les constats de Security Advisor, les adresses bloquées et
  l'export vers un fichier.
- Centre de paquets : parcourir le catalogue officiel Synology, installer,
  mettre à jour et supprimer des paquets, en installer un à la main, et gérer
  vos sources de paquets.
- Conteneurs : Container Manager est couvert en entier. Créer un conteneur, en
  dupliquer un, le renommer, plafonner sa mémoire, lire ses journaux et ses
  statistiques, et gérer les images, les réseaux, les projets et les registres.
- USB Copy : préparer et lancer vos tâches de copie USB entièrement depuis
  l'application — sens, dossiers, filtres et planification. Contribution
  d'Ashley Cox.
- Utilisateurs et groupes reçoit les permissions : un panneau liste chaque
  dossier partagé avec les droits d'un compte ou d'un groupe, et un second
  onglet fait de même pour les applications.

### Fichiers

- Copiez des fichiers dans le Finder et collez-les dans un dossier du NAS, ou
  faites glisser un élément de la liste vers le Finder. Un dossier déposé dans
  le Finder arrive sous forme d'archive fabriquée par le NAS.
- Le copier-coller se comporte comme dans le Finder : Commande-C copie,
  Commande-V colle, et Retour renomme.
- Une copie en cours indique ce qu'elle fait, où elle en est, sa vitesse et le
  temps restant, avec un bouton Annuler qui l'arrête vraiment. Les envois et les
  téléchargements affichent le même bandeau.
- Le résultat d'une opération longue reste à l'écran jusqu'à ce que vous le
  fermiez, et un son bref marque la fin d'un transfert. Ce son peut être coupé.
- Créez et gérez des liens de partage, avec mot de passe et date d'expiration.
- Consultez les informations détaillées d'un fichier ou d'un dossier, cherchez
  avec des critères avancés, ouvrez une archive et n'en extrayez que ce qui vous
  intéresse.

### Connexion et comptes

- Ouvrez une session sans taper de mot de passe, en l'approuvant sur votre
  téléphone avec Secure SignIn.
- Les sessions sont conservées d'un lancement à l'autre : cochez « Rester
  connecté » et l'application rouvre la session qu'elle avait déjà.
- Connectez-vous par QuickConnect en saisissant votre identifiant QuickConnect
  plutôt qu'une adresse. Contribution d'Ashley Cox.
- Les comptes sans droits d'administrateur peuvent se connecter, et
  l'application vous prévient quand votre NAS exige un nouveau mot de passe
  avant de laisser entrer un compte.
- Créez des utilisateurs et des groupes, choisissez ce qu'ils peuvent atteindre,
  et générez un mot de passe conforme à la politique de votre NAS.

### Changements

- Les raccourcis clavier des derniers modules utilisent Commande-Option plutôt
  que Commande-Majuscule. macOS réserve Commande-Majuscule-3, 4 et 5 pour les
  captures d'écran et l'emporte toujours, ce qui rendait trois modules
  inaccessibles au clavier.
- Vous choisissez de recevoir ou non les versions bêta, dans Réglages > Mises à
  jour. Essayer une bêta une fois ne condamne plus à y rester.
- L'application cherche une nouvelle version à chaque lancement, et possède sa
  propre icône, dessinée par Ashley Cox.

### Corrections

- Une copie longue n'est plus abandonnée au bout de cinq minutes, et quitter
  l'écran ne l'interrompt plus.
- Un paquet installé pendant que l'application tourne est désormais détecté, au
  lieu de rester indisponible jusqu'à la prochaine ouverture de session.
- La création d'un lien de partage, l'envoi de fichiers vers le NAS,
  l'installation d'un fichier de paquet et la création d'un utilisateur sur
  DSM 7.4 fonctionnent à nouveau.
- Approuver le certificat de votre NAS vous connecte, au lieu de bloquer là.

### Accessibilité et langue

- Les listes, les formulaires et les zones de défilement de l'application disent
  ce qu'ils contiennent, au lieu d'annoncer « zone de défilement ».
- Les textes d'état et de détail ont été rendus lisibles : les couleurs système
  passaient sous le seuil de contraste aux tailles utilisées ici.
- Les transferts nomment leur sens par des mots, et non plus par une icône
  seule.
- L'application s'affiche en anglais sur un Mac réglé dans une langue qu'elle ne
  propose pas, au lieu de mélanger les langues.

### Limites connues

- L'éjection et le formatage ont été éprouvés en USB. L'eSATA passe par les
  mêmes appels, mais aucun disque eSATA n'était disponible pour les essayer.

## v1.1-beta.21 (build 22) — 3 août 2026

### En bref

- Container Manager est couvert en entier : vous pouvez créer un conteneur, et
  plus seulement suivre ceux qui existent déjà.

### Nouveautés

- Conteneurs : un bouton Nouveau conteneur demande une image, un nom, les ports
  à publier, les dossiers à monter et les variables d'environnement, puis le
  crée. Un port laissé à 0 est choisi pour vous au démarrage du conteneur.
- Conteneurs : Dupliquer crée un second conteneur avec les mêmes réglages. La
  copie arrive à l'arrêt, et ses ports restent libres pour ne pas entrer en
  conflit avec l'original.
- Conteneurs : un écran Réglages renomme un conteneur, plafonne sa mémoire et
  décide s'il redémarre tout seul.
- Conteneurs : un onglet Statistiques donne la mémoire utilisée et les octets
  reçus et envoyés. Un conteneur qui vient de démarrer annonce que sa part de
  processeur n'est pas encore mesurable, plutôt que d'afficher zéro.
- Conteneurs : l'arrêt forcé tue un conteneur qui refuse de s'arrêter, et
  Réinitialiser le reconstruit à partir de ses réglages. Les deux disent ce qui
  est perdu avant d'agir.
- Conteneurs : les réglages d'un conteneur peuvent être écrits dans un dossier
  du NAS.

### Changements

- Neuf listes de plus sont devenues des tableaux triables, avec une colonne par
  valeur : les favoris, les tâches, les dossiers virtuels et les transferts de
  File Station, les paquets installés, le catalogue de paquets, les dossiers
  partagés, le journal USB Copy et l'explorateur d'archives. Lire une ligne
  colonne par colonne ne veut plus dire l'entendre d'un bloc.
- Les boutons de chaque ligne sont passés dans le menu contextuel du tableau,
  partout. La colonne Actions disparaît : elle élargissait chaque ligne et
  s'intercalait entre vous et la ligne suivante.
- Les dossiers partagés indiquent si la corbeille est active. Le NAS le
  rapportait depuis toujours sans que l'app le dise.
- Les transferts nomment le sens en toutes lettres. C'était une icône, donc ce
  n'était dit nulle part.
- L'explorateur d'archives indique si une entrée est un dossier ou un fichier.
- Les paquets signalent qu'une opération est en cours, et qu'une désinstallation
  demande l'assistant de DSM. Les deux n'étaient que suggérés.

### Corrections

- VoiceOver : les formulaires, les listes et les zones de défilement de toute
  l'app disent maintenant ce qu'ils contiennent. La plupart n'annonçaient qu'une
  « zone de défilement ».
- Deux libellés affichaient leur clé interne au lieu de leur texte.

### Téléchargement

[dsmaccess-1.1-beta.21.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.21/dsmaccess-1.1-beta.21.zip)

## v1.1-beta.20 (build 21) — 31 juillet 2026

### Nouveautés

- Mises à jour : vous choisissez désormais de recevoir ou non les versions
  bêta, dans Réglages > Mises à jour. Jusqu'ici le canal découlait de la
  version installée : avoir essayé une bêta une fois, c'était y rester. Le
  désactiver ne revient pas sur la bêta déjà installée : l'app y reste jusqu'à
  ce qu'une version stable la dépasse.
- Fichiers : un envoi ou un téléchargement affiche le même bandeau qu'une
  copie — ce qui est en cours, la part effectuée, la vitesse, le temps restant,
  et un bouton d'annulation qui l'arrête vraiment. Jusqu'ici un envoi
  volumineux n'affichait qu'un indicateur dans un coin, et le détail restait
  dans une fenêtre qu'il fallait songer à ouvrir.
- Utilisateurs et groupes : la création d'un groupe propose « Créer et définir
  les permissions… », comme celle d'un utilisateur le faisait déjà. Un groupe
  neuf n'avait accès à rien, et rien à l'écran n'indiquait où lui en donner.

### Corrections

- Fichiers : glisser un dossier vers le Finder produit une archive zip
  fabriquée par le NAS, et le télécharger fait de même. C'est maintenant
  annoncé, avec le nom de l'archive, au lieu d'un .zip qui apparaît sans
  prévenir.
- Fichiers : pendant que le NAS compresse un dossier, rien ne circule encore.
  Cette attente porte désormais un nom, au lieu d'une barre de progression
  figée à zéro sans explication.
- Utilisateurs et groupes : créer un groupe dont le nom est déjà pris laisse la
  fenêtre ouverte et le dit, au lieu de se fermer en emportant la saisie.

### Téléchargement

[dsmaccess-1.1-beta.20.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.20/dsmaccess-1.1-beta.20.zip)

## v1.1-beta.19 (build 20) — 31 juillet 2026

### Corrections

- Fichiers : envoyer un fichier vers le NAS, ou en rapatrier un, joue enfin le
  son à la fin. Il ne se déclenchait que pour les opérations qui restent sur le
  NAS — copier, déplacer, supprimer — ce qui laissait de côté justement les
  transferts assez longs pour qu'on aille faire autre chose. La notification
  manquait aussi sur ceux-là.
- Fichiers : coller ou envoyer n'ouvre plus un formulaire au préalable. L'app
  compare les noms avec la destination et ne pose la question que si quelque
  chose serait remplacé, en le nommant : « budget.xlsx existe déjà dans ce
  dossier ». Le formulaire d'envoi et ses trois sélecteurs de date ont disparu ;
  DSM ne les demande pas non plus.
- Cinq messages parlés étaient en français pour tout le monde : modification
  d'un lien de partage, recherche avancée, détails d'un paquet, création d'une
  archive, et un dernier. Ils avaient échappé au travail de traduction.

### Téléchargement

[dsmaccess-1.1-beta.19.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.19/dsmaccess-1.1-beta.19.zip)

## v1.1-beta.18 (build 19) — 30 juillet 2026

### Corrections

- Fichiers : le collage dans un dossier vide fonctionne. Le raccourci clavier
  n'y faisait rien, alors que c'est le seul endroit où coller est la seule chose
  qui reste à faire. Le dossier est toujours annoncé comme vide à l'arrivée.
- Utilisateurs et groupes : la création d'un compte n'annonce plus un échec
  d'ajout aux groupes qui n'a pas eu lieu. Le NAS place lui-même tout compte
  dans le groupe « users » et refuse qu'on y touche : l'app ne le propose donc
  plus, et l'écran indique à la place que tout compte lui appartient.
- Utilisateurs et groupes : quand le NAS refuse réellement un groupe, l'app le
  nomme et conserve ceux qu'il a acceptés. Jusqu'ici, le premier refus
  abandonnait en silence tous les groupes listés après lui.

### Téléchargement

[dsmaccess-1.1-beta.18.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.18/dsmaccess-1.1-beta.18.zip)

## v1.1-beta.17 (build 18) — 30 juillet 2026

### En bref

- Journaux et sécurité a été refait. L'app ne lisait qu'un journal sur quatre —
  sept mille entrées là où le NAS en garde plus de cent mille — et deux de ses
  colonnes étaient vides depuis toujours.
- Le Moniteur de ressources est complet : les fichiers ouverts, les alertes que
  le NAS a enregistrées, et les seuils qui les déclenchent.

### Signalez-moi les formulations qui clochent

Tout le texte de l'app a changé de système cette semaine, pour qu'elle puisse un
jour être traduite dans d'autres langues. Rien ne devrait avoir bougé à
l'écran — mais si vous tombez sur un libellé qui ressemble à du code, sur une
phrase restée en anglais ou sur un mot manquant, dites-le-moi. L'erreur est de
mon côté, pas du vôtre, et elle se corrige vite.

### Nouveautés

- Journaux et sécurité : les quatre journaux tenus par le NAS sont désormais
  accessibles, et plus seulement celui du système. Les transferts de fichiers y
  sont, avec l'adresse, l'opération et la taille ; les connexions ont le leur.
- Journaux et sécurité : un journal peut être exporté dans un fichier, en
  tableur ou en page web. C'est le NAS qui écrit le fichier, vous obtenez donc
  exactement ce qu'il contient.
- Journaux et sécurité : ce que le Conseiller de sécurité a relevé sur les
  connexions a maintenant son onglet — tentatives échouées, provenances
  inhabituelles, comptes à surveiller.
- Journaux et sécurité : deux écrans de réglages. L'un décide des transferts que
  le NAS consigne ; l'autre, du nombre de connexions manquées avant qu'une
  adresse soit bloquée, et pour combien de temps.
- Journaux et sécurité : le champ de recherche est dans la barre d'outils, comme
  partout ailleurs, et les entrées plus anciennes se chargent au fil du
  défilement au lieu de s'arrêter à la première page.
- Moniteur de ressources : un onglet Fichiers ouverts, qui liste ce que le NAS
  tient ouvert en ce moment, et pour qui.
- Moniteur de ressources : un onglet Historique, avec les alertes que le NAS a
  enregistrées quand ses propres seuils ont été franchis.
- Moniteur de ressources : un onglet Alarme des performances. Vous y ajoutez,
  modifiez et supprimez les seuils que le NAS surveille — sur le système, sur un
  service ou sur un volume.
- Moniteur de ressources : une session connectée peut être coupée depuis
  l'onglet Connexions.
- Fichiers : une copie ou un déplacement joue un court son en se terminant, et
  un autre s'il échoue. Le son se fait entendre quand l'app est au premier plan ;
  sinon, c'est la notification qui porte le résultat, comme avant, et jamais les
  deux. Les Réglages permettent de le couper.

### Corrections

- Journaux et sécurité : la liste de blocage revenait avec une erreur 103, et
  cela pour tout le monde. L'app interrogeait le NAS de la mauvaise façon. C'est
  réparé.
- Journaux et sécurité : les colonnes Heure et Utilisateur étaient vides dans
  tous les journaux. L'app lisait des champs que le NAS n'envoie pas.
- Moniteur de ressources : la part de processeur d'un service s'affichait cent
  fois trop petite.
- Moniteur de ressources : un processus peut légitimement dépasser 100 % — cela
  signifie qu'il occupe plus d'un cœur. L'écran le dit maintenant, au lieu de
  vous laisser deviner.
- Cinq libellés du Moniteur de ressources s'affichaient en anglais.

### Téléchargement

[dsmaccess-1.1-beta.17.zip](https://github.com/math65/dsmaccess/releases/download/v1.1-beta.17/dsmaccess-1.1-beta.17.zip)

## v1.1-beta.16 (build 17) — 29 juillet 2026

### En bref

- Connexion : l'app rouvre sur la session qu'elle avait déjà. Cochez « Rester
  connecté » une fois, et le lancement suivant entre directement — sans mot de
  passe à rejouer, et sans approbation à donner sur votre téléphone.
- Un Moniteur de ressources à part entière : processeur, mémoire, réseau,
  disques et volumes, les services et processus en cours, et qui est connecté
  au NAS.

### Nouveautés

- Connexion : la session est conservée d'un lancement à l'autre. Seul un refus
  du NAS vous ramène à l'écran de connexion, et il vous dit pourquoi. La session
  enregistrée dort dans le Trousseau à côté de votre mot de passe, et disparaît
  à la déconnexion.
- Connexion : le menu nomme désormais Secure SignIn au lieu de le décrire comme
  « sans mot de passe », et retient la méthode que vous avez choisie.
- Moniteur de ressources : une nouvelle entrée dans la barre latérale, sur
  Commande Majuscule 5, avec trois onglets. Performances ajoute chaque disque et
  chaque volume, avec leur activité, ainsi que les charges moyennes. Tâches
  liste les services et les processus les plus actifs. Connexions montre qui est
  connecté, depuis où et depuis quand.
- Moniteur de ressources : les tâches et les connexions sont des tableaux
  triables — cliquez un en-tête de colonne pour ordonner dessus.
- Fichiers : une copie en cours affiche sa vitesse et le temps restant, ou
  « moins d'une minute » quand la fin approche. Ni l'une ni l'autre n'est
  annoncée à voix haute : elles restent dans le bandeau, à lire quand vous le
  voulez.
- Fichiers : quand une opération longue se termine alors que l'app est en
  arrière-plan, une notification vous en porte le résultat. macOS demande votre
  autorisation la première fois, et un réglage permet de la couper.

### Corrections

- La mémoire se contredisait d'une ligne à l'autre : 17 % d'utilisation, puis
  3,54 Go sur 3,68 Go juste en dessous. DSM met le cache disque à part, et ce
  NAS en gardait 2,89 Go.
- Le menu du NAS, dans la barre d'outils, annonçait le nom de son icône —
  « externaldrive.connected.to.line.below » — au lieu de ce qu'il fait.

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
