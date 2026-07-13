# Changelog

Toutes les évolutions notables de MacTuner sont consignées ici.
Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le
[versionnage sémantique](https://semver.org/lang/fr/).

## [1.0.1] — 2026-07-13

Transparence sur SIP, interface unifiée et corrections du ventilateur. Cette
version dit la vérité sur ce qui est réellement faisable quand System Integrity
Protection est activé, remet toute l'interface au propre (thème sombre cohérent,
cartes identiques partout) et fiabilise le contrôle de la ventilation.

### Transparence SIP

- **Deux catégories claires dans Fonctionnalités** : « Effet immédiat (compatibles SIP) » — réglages `defaults` et commandes système qui s'appliquent tout de suite — et « Nécessite SIP désactivé » — réglages qui reposent sur l'arrêt d'un agent Apple. Sections colorées (vert / ambre), compteur de réglages, fonds teintés et bordures, plus un indicateur bouclier ambre sur chaque carte bloquée par SIP.
- **Réglages non modifiables grisés** : quand SIP est activé, les cartes de la catégorie « Nécessite SIP désactivé » sont grisées et leur interrupteur désactivé (carte comme fiche détail), avec la mention « SIP requis » et un encart explicatif. La détection est dynamique : tout redevient actif si SIP est désactivé.
- **Détection de SIP** (`csrutil status`) et bandeau explicatif : avec SIP activé, `launchctl bootout` sur un agent Apple est refusé (erreur 150) et l'agent est relancé au démarrage ; l'effet réel n'arrive qu'après `csrutil disable`.
- **Fin des échecs silencieux** : `Shell.run` capture désormais le code de sortie et `stderr`. `LaunchCtl.disable` renvoie si l'agent a *réellement* été arrêté.
- **Gains réels au lieu de fictifs** : la RAM/les processus « libérés » sont mesurés avant/après (écart réel). Sous SIP, où rien n'est arrêté, le gain affiché est zéro — plus de « 602 Mo libérés » imaginaires.
- **Ré-application corrigée** : le script `reapply.sh` ne prend plus le drapeau « disabled » pour une preuve d'arrêt et tente le bootout dès qu'un processus tourne.

### Interface unifiée

- **Thème sombre assaini** : le matériau translucide des cartes (qui virait au gris-marron sur le fond bleu nuit) est remplacé par un fond solide ; tous les accents orange deviennent un ambre franc (`#ffc75c`), sauf les dégradés de jauge.
- **Gabarit commun à tous les onglets** : même en-tête (`TabHeader`), même largeur et marge de contenu (`tabContent`), mêmes cartes (coin 14, bordure, fond solide), même grille 4 colonnes. Fonctionnalités sert de référence.
- **Maintenance, Nettoyage, Réglages, Guide** refondus pour correspondre exactement à Fonctionnalités (grilles de cartes compactes, titres de section homogènes).
- **Boutons unifiés** (`DarkButton`) : fond sombre cohérent dans tous les états, désactivé compris (fini le bouton grisé qui virait au brun). Accent rouge conservé pour les actions destructives.
- **Bande d'onglets et barre de fenêtre** sur fond encre de nuit ; listes de Désinstaller rendues transparentes pour laisser passer le fond.
- Correction d'affichage : `humanBytes` n'affiche plus « Zero KB » en toutes lettres pour une valeur nulle.

### Ventilateur

- **Retour au mode automatique fiabilisé** : en repassant en auto, on relâche le SMC (`F0Md=0`), on ramène la cible au minimum constructeur en filet de sécurité, et on retire l'override de démarrage — le ventilateur revient réellement à l'état d'origine.
- **Bouton Valider fiabilisé** : si la règle sudoers vise un autre exemplaire du binaire, l'app le détecte (au lieu d'échouer en silence), répare la règle et réessaie.

### Réinitialisation

- **« Paramètres par défaut » = premier lancement** : réactive toutes les fonctionnalités désactivées, remet le ventilateur en automatique, retire l'agent de ré-application, efface toutes les préférences (onboarding compris) puis relance l'app.

---

*Les évolutions ci-dessous étaient préparées entre 1.0.0 et 1.0.1 (jamais publiées séparément) et sont incluses dans cette version.*

### Ajouté

- **État voulu persisté** : MacTuner mémorise désormais ce que vous avez désactivé (fiches entières et sous-processus individuels).
- **Détection d'écart** : au lancement, une bannière signale « N désactivation(s) ont été réactivées par macOS » avec un bouton **Réappliquer**.
- **Ré-application automatique** : un LaunchAgent utilisateur (`local.rodolphe.mactuner.reapply`) ré-applique vos désactivations à chaque ouverture de session **et dès que macOS réécrit sa base d'overrides launchd** (`WatchPaths` sur `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist`) — y compris en cours de session. Le script est idempotent (il ne touche qu'à ce qui a réellement été réactivé, donc pas de boucle), chargé immédiatement à sa création, retiré dès que plus rien n'est désactivé, et par la désinstallation.
- **Siri coupé à la source** : la fiche Siri désactive aussi les réglages maîtres (`com.apple.assistant.support → Assistant Enabled` et `com.apple.Siri → VoiceTriggerUserEnabled`), ceux que macOS consulte au démarrage pour relancer les agents.

### Nettoyage & Journal

- **Fenêtre de progression animée** pendant le nettoyage : icône scintillante, barre de progression réelle, chemin en cours et pourcentage, puis bilan « X libérés » avec coche animée.
- **Onglet Journal** : chaque fichier réellement supprimé (nettoyage et désinstallations) est consigné — chemin, taille, origine, date — avec filtre, total cumulé et bouton pour vider l'historique (5 000 entrées max, stocké dans Application Support).

### Refonte visuelle (identité du site)

- **Thème sombre permanent** « encre de nuit » repris du site (fond #0a0e1a, surfaces translucides, signature tricolore discrète), appliqué à tous les onglets.
- **Fonctionnalités et Nettoyage en grilles de cartes** (3 colonnes) : interrupteur, pastilles de risque, résumé et consommation sur chaque carte ; la fiche complète (rôle, impacts, sous-processus, chemins analysés) s'ouvre via Détails.
- **Gains refait au propre** : bilan réalisé, encore récupérable et services actifs avec barres alignées.
- **Ventilateur** : bouton Valider (la vitesse n'est plus envoyée pendant le glissement), vitesse personnalisée mémorisée et restaurée au lancement, cible initialisée à la vitesse réelle ; seule l'hélice du centre est animée, proportionnellement au régime.
- **Test de débit** dans la carte Réseau : mesure réelle en Mbit/s (téléchargement de 25 Mo via Cloudflare).
- Textes revus sans tirets cadratins, survols et icônes animées retirés (sobriété d'app de bureau).

### Interface animée

- **Débits disque en temps réel** (lecture/écriture via IOKit) affichés dans la carte Disque, avec icônes qui pulsent pendant les transferts.
- **Icônes thématiques dessinées sur mesure**, dans l'esprit de l'hélice : puce processeur dont les 4 cœurs clignotent à la cadence de la charge, barrette de RAM avec cellules remplies selon l'usage et balayage lumineux, plateau de disque qui tourne selon l'activité E/S, égaliseur réseau agité par le débit (escalier de signal au repos), corbeille où des documents tombent en boucle dans la section Nettoyage et sa fenêtre de progression ; batterie pulsante pendant la charge.

- **Ventilateur vivant** : hélice qui tourne réellement dans la jauge et l'en-tête de la carte Ventilation, à une vitesse proportionnelle au régime réel (à l'arrêt à 0 tr/min).
- **Entrées en cascade** façon site web : les cartes du tableau de bord, tuiles de gains et actions de maintenance apparaissent en fondu + glissement échelonnés.
- **Compteurs animés** : RPM, débits réseau, jauges, tailles détectées et gains défilent chiffre à chiffre (`numericText`).
- **Pastilles « respirantes »** sur les sous-processus actifs (halo pulsant, comme les points de statut du site), pastille rouge statique quand c'est coupé.
- **Micro-interactions** : icônes qui rebondissent au changement d'état, chevrons rotatifs, badge « DÉSACTIVÉ » qui surgit en ressort, cartes et tuiles qui se soulèvent au survol, icône réseau pulsante quand ça transfère, scintillement pendant le scan de nettoyage, alerte de dérive pulsante.
- La version affichée est désormais lue depuis Info.plist (fini le « v1.0.0 » codé en dur).

### Modifié

- **Apple Intelligence, vérifié** : macOS 27 n'expose aucun réglage maître public (le domaine d'opt-in n'existe pas) ; la fiche l'explique désormais honnêtement et précise que MacTuner re-coupe ces daemons automatiquement dès que macOS les réactive.
- **« Tout restaurer » plus respectueux** : ne réactive que ce qui est effectivement désactivé, au lieu de réécrire tous les réglages (il ne force plus, par exemple, la publicité personnalisée chez qui l'avait coupée en dehors de MacTuner).
- Au lancement, l'app réaligne le LaunchAgent sur l'état voulu (migration de format, fichiers supprimés à la main).
- Texte du bandeau « Redémarrage requis » mis à jour pour refléter le comportement réel de macOS 26/27 (self-healing des agents au boot).
- La désinstallation intégrée retire aussi le LaunchAgent de ré-application et `~/Library/Application Support/MacTuner`.

### Notes

- macOS affichera une notification « Éléments d'arrière-plan ajoutés » la première fois que le LaunchAgent de ré-application est créé : c'est le script visible dans Réglages > Général > Ouverture et extensions.

## [1.0.0] — 2026-07-10

Première version publique. Centre de contrôle, de réglage et d'entretien pour Mac Apple Silicon (macOS 26–27), 100 % natif SwiftUI, libre et open source.

### Ajouté

- **Tableau de bord** temps réel : CPU (global et par cœur), mémoire (câblée, compressée, apps), disque, réseau, température et ventilation — sans mot de passe, rafraîchi toutes les 1,5 s.
- **Ventilation** : contrôle manuel borné au min/max constructeur, presets et réapplication au démarrage. Un seul mot de passe grâce à l'autorisation persistante.
- **Fonctionnalités** : 34 réglages système désactivables et réactivables (Siri, Apple Intelligence, télémétrie, iCloud…), par catégorie ou par sous-processus. 100 % réversible.
- **Nettoyage** : 18 catégories de fichiers régénérables (caches, journaux, builds Xcode, navigateurs, messageries, conteneurs orphelins).
- **Désinstaller** : suppression sans résidu des apps, des outils en ligne de commande (alias regroupés, données résolues via symlinks) et des fichiers cachés `~/.xxx`.
- **Maintenance** : cache DNS, mémoire, réindexation Spotlight, snapshots Time Machine, cache d'icônes, Launch Services, Dock et Finder.
- **Gains** : mesures réelles de RAM, de temps CPU et d'espace disque libéré.
- **Garde-fou central** (`SafetyGuard`) : liste blanche stricte qui rend impossible la suppression de `/System`, `/usr`, des apps Apple, de Documents/Photos/Bureau, des trousseaux, d'iCloud Drive, de Mail, Messages, des clés SSH et des fichiers shell.
- **Sécurité** : droits administrateur limités à des commandes précises via des règles `sudoers` **révocables**. Seuls des mécanismes documentés d'Apple sont utilisés (`launchctl`, `defaults`, IOKit SMC) ; aucun fichier système n'est jamais modifié.
- **Bilingue** français / anglais, choix au premier lancement et dans les Réglages, changement à chaud. Aucune chaîne codée en dur.
- **Compilation** en une commande via `build.sh` (aucune dépendance externe, pas de Xcode requis) et bundle signé en ad-hoc.

### Notes

- Compatible **macOS 26 et 27** sur **Apple Silicon** uniquement (Intel non pris en charge).
- Application signée en ad-hoc et non notarisée : au premier lancement, faites un clic droit → Ouvrir.
- Sur Apple Silicon avec SIP, certaines désactivations deviennent pleinement effectives après un redémarrage.

[1.0.1]: https://github.com/Bodyroro/MacTuner/releases/tag/v1.0.1
[1.0.0]: https://github.com/Bodyroro/MacTuner/releases/tag/v1.0.0
