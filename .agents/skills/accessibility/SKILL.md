---
name: accessibility
description: Audit d'accessibilité de DSM Access — passe le code au crible des exigences VoiceOver du projet (zones et tableaux sans nom, annonces non localisées, libellés mal formés, couleurs sous le seuil de contraste, littéraux non traduits) puis guide la revue manuelle des états qu'aucun script ne voit. À utiliser avant de livrer un écran, quand on demande « vérifie l'accessibilité », « est-ce que c'est bon en VoiceOver », « audit a11y », « passe d'accessibilité », après avoir écrit ou modifié une vue SwiftUI, et chaque fois qu'un défaut d'accessibilité est signalé à l'oreille — le réflexe doit être de lancer cette skill plutôt que de chercher à la main.
---

# Audit d'accessibilité de DSM Access

DSM Access existe parce que l'interface web de DSM est inutilisable avec VoiceOver. Ici
l'accessibilité n'est pas une finition : **un écran qui compile mais laisse un contrôle sans
nom est un écran qui ne marche pas.** C'est la priorité n°1 de `CLAUDE.md`, avant même la
justesse du comportement DSM.

Cette skill fait deux choses, et la seconde compte autant que la première :

1. Un script trouve les défauts mécaniques, ceux qui se repèrent dans le texte du code.
2. Une revue guidée couvre ce qu'aucun script ne peut voir : le focus, l'ordre de lecture,
   les états transitoires, ce qui est réellement dit à voix haute.

## 1. Passer le script

Depuis la racine du dépôt :

```sh
python3 .agents/skills/accessibility/scripts/audit.py            # tout le projet
python3 .agents/skills/accessibility/scripts/audit.py --diff     # ce qui est en cours
python3 .agents/skills/accessibility/scripts/audit.py --files dsmaccess/Views/MonEcran.swift
python3 .agents/skills/accessibility/scripts/audit.py --only regions,tables
python3 .agents/skills/accessibility/scripts/audit.py --list-rules
```

Sur un travail en cours, `--diff` est le bon réflexe : il ne montre que les fichiers touchés,
donc le bruit historique du projet ne noie pas ce qui vient d'être écrit.

Le script sort en code 1 s'il reste des constats. Il ne modifie rien.

### Ce que chaque règle cherche, et pourquoi

- **regions** — un `Form`, un `ScrollView` ou une `List` sans `accessibilityLabel`. VoiceOver
  annonce alors « zone de défilement » et rien d'autre : l'utilisateur sait qu'il est entré
  quelque part sans savoir où. Le patron du projet est `.accessibilityLabel(...)` posé juste
  après `.formStyle(.grouped)`, comme dans `FileInfoSheet.swift`.
- **tables** — un `Table` sans nom. La consigne du projet est explicite : un tableau porte son
  `accessibilityLabel`, sinon VoiceOver annonce un tableau anonyme et l'audit XCUITest le
  signale comme sans description.
- **announces** — `VoiceOver.announce("…")` avec un littéral. Ça compile, ça part en
  production, et c'est prononcé dans la langue où c'était tapé : le compilateur n'extrait rien,
  donc ni le catalogue ni ses tests ne peuvent voir la clé manquante. Passer par
  `String(localized:)`.
- **hints** — une clé posée en `accessibilityHint` dont la valeur ne finit pas par un point.
  Le point final n'est pas de la cosmétique : c'est lui qui donne à VoiceOver son intonation
  de fin de phrase. Un hint s'écrit à la troisième personne et décrit le résultat
  (« Ouvre ce dossier. »), jamais l'action (« Ouvrir »).
- **labels** — un libellé qui prend un point final, commence en minuscule, ou nomme le type du
  contrôle. Le trait d'accessibilité dit déjà « bouton » ; le répéter fait entendre
  « Supprimer bouton, bouton ».
- **contrast** — `.secondary`, `.red`, `.green`, `.orange` en `foregroundStyle` dans une vue.
  Aux tailles utilisées ici, les couleurs système passent sous le seuil AA. Les styles
  contrastés vivent dans `Views/Components/ReadableStyles.swift`.
- **untranslated** — un ternaire qui affiche deux littéraux (`? "Oui" : "Non"`). Il compile et
  montre le mot français à un système anglais.
- **combine** — `accessibilityElement(children: .combine)`. Ce n'est pas un défaut en soi,
  c'est un point à regarder : combiner un conteneur enterre les boutons et les valeurs qu'il
  contient. Vérifier ce qui se trouve dedans.
- **icon-buttons** — un bouton qui semble ne porter qu'un symbole. Le repérage est
  approximatif : confirmer en lisant le code.

### Interpréter les constats sans les subir

Le script signale, il ne juge pas. Trois pièges à connaître :

- **Le compte global est un état des lieux, pas une liste de corrections à faire séance
  tenante.** Le projet traîne un passif ; corriger l'écran en cours et signaler le reste vaut
  mieux qu'une passe massive non demandée, qui contreviendrait à la règle du diff minimal.
- **Une zone dans une feuille modale porte déjà un titre de fenêtre.** Lui coller un nom
  identique fait entendre le titre deux fois. Nommer la zone reste utile quand le nom apporte
  autre chose que le titre — l'arbitrage revient à l'utilisateur, qui est le seul à l'entendre.
- **`.help` n'est pas `accessibilityHint`.** L'infobulle suit une autre convention et le script
  ne la contrôle pas volontairement : arbitrage de Mathieu, une infobulle peut être une phrase
  complète du moment qu'elle est utile. Ne pas lui appliquer la règle du point final.

## 2. Ce que le script ne verra jamais

C'est là que se trouvent les vrais défauts d'usage. Pour chaque écran modifié, parcourir
**tous ses états** — initial, chargement, contenu, vide, erreur de validation, opération en
cours, échec — et vérifier :

- **Le focus.** `@AccessibilityFocusState` doit déplacer VoiceOver vers l'élément utile après
  une navigation, l'ouverture d'une feuille, le remplacement d'un chargement par du contenu, et
  après un refus de validation. Mais jamais pendant un rafraîchissement de fond ni pendant que
  l'utilisateur tape ailleurs.
- **Les états muets.** Un spinner sans libellé, une erreur affichée sans être annoncée, une
  mutation réussie sans résultat dit : chacun est un écran incomplet. Utiliser
  `VoiceOver.announce` avec la bonne `AnnouncementCategory`.
- **Les annonces perdues.** Une annonce émise alors que l'app est en arrière-plan, ou depuis
  une vue en train d'être démontée, n'est jamais entendue. Si le message compte, il faut un
  état persistant ou une alerte.
- **La couleur seule.** Un statut porté par une couleur, une icône, une animation ou un état
  désactivé est invisible à l'écoute. Le mot est toujours écrit ; la couleur ne fait que le
  doubler.
- **Le clavier.** Traversée complète à la tabulation, action par défaut et action d'annulation
  présentes, aucun piège au clavier.
- **`Table` plutôt que `List`** pour toute donnée : une `List` macOS se parcourt mal aux
  flèches et effondre souvent une ligne en un seul élément, ce qui enterre les valeurs. La
  seule dérogation est le clavier façon Finder, et son patron est `Views/FileTableView.swift`.

## 3. L'audit XCUITest, en complément

Un audit automatique existe et parcourt les écrans d'une session connectée. Il demande le
profil NAS enregistré de la machine et ne doit pas tourner sans surveillance :

```sh
TEST_RUNNER_AUDIT_LIVE_NAS=1 xcodebuild -project dsmaccess.xcodeproj \
  -scheme 'dsmaccess UI Tests' -destination 'platform=macOS' \
  test -only-testing:dsmaccessUITests/AccessibilityAuditTests
```

Deux réserves apprises à l'usage : ses constats de **contraste ne sont pas fiables**, et un
échec « Parent/Child mismatch » dont l'élément est nul vient d'une machine occupée — relancer
au calme avant d'y voir une régression.

## 4. Rendre compte

L'audit se termine par une conversation, pas par un fichier. Présenter :

- ce qui a été corrigé dans l'écran en cours ;
- ce que le script signale ailleurs, avec le compte par règle, en distinguant clairement le
  passif du projet de ce que le travail en cours aurait introduit ;
- ce qui reste à écouter, formulé comme une liste de choses à essayer — Mathieu utilise
  VoiceOver, il entend en trente secondes ce qu'aucun script ne mesure. Lui indiquer quoi
  ouvrir et quoi guetter vaut mieux que lui affirmer que tout va bien.

Ne jamais écrire qu'un écran est accessible sans l'avoir fait vérifier à l'oreille : la
compilation et le script prouvent l'absence de certains défauts, jamais la présence de l'usage.
