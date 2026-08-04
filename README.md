<div align="center">

<img src="logo.png" width="120" alt="MacTuner"/>

# MacTuner

**Le centre de contrôle, de réglage et d'entretien de votre Mac Apple Silicon.**

*The all-in-one control, tuning and maintenance centre for your Apple Silicon Mac.*

![Version](https://img.shields.io/badge/version-1.2.0-blue)
![Platform](https://img.shields.io/badge/macOS-26_·_27-black?logo=apple)
![Chip](https://img.shields.io/badge/Apple_Silicon-only-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)
![Langues](https://img.shields.io/badge/langues-FR_·_EN-lightgrey)

<br/>

<img src="dashboard.png" width="900" alt="Tableau de bord MacTuner : processeur par cœur, mémoire, disque, réseau et contrôle de ventilation en temps réel"/>

<br/><br/>

### 🇫🇷 [Version française](#-français) &nbsp;&nbsp;·&nbsp;&nbsp; 🇬🇧 [English version](#-english)

</div>

<br/>

---

# 🇫🇷 Français

## Présentation

MacTuner réunit dans une seule application native, écrite en SwiftUI, tout ce qui
permet de garder la maîtrise de son Mac : la surveillance du matériel en temps
réel, la désactivation des fonctions système superflues, le nettoyage des caches,
la libération d'espace disque, la désinstallation sans résidu, l'entretien
courant, les réglages fins du Finder et du Dock, et le pilotage de la ventilation.

Trois principes gouvernent l'application. Rien ne se fait à votre insu : chaque
action est nommée, expliquée et journalisée. Tout est réversible : aucun réglage
n'engage définitivement la machine. Un garde-fou central rend la suppression de
fichiers critiques impossible, quel que soit le chemin emprunté dans l'interface.

MacTuner n'emploie que des mécanismes documentés par Apple (`launchctl`,
`defaults`, IOKit SMC). Aucun fichier système n'est jamais modifié.

## Fonctionnalités

### Surveillance et matériel

| Module | Ce qu'il apporte |
|---|---|
| **Tableau de bord** | Charge processeur globale et par cœur, activité GPU en temps réel, mémoire détaillée (câblée, compressée, applications), lecture et écriture disque, débit réseau, température, autonomie sur les portables. Aucune saisie de mot de passe. |
| **Ventilation** | Contrôle manuel de la vitesse, borné aux valeurs minimale et maximale du constructeur, ce qui exclut tout risque de surchauffe. Trois préréglages (silencieux, moyen, maximum) et une consigne réellement persistante, réappliquée au lancement de l'app, au réveil et au démarrage du Mac. Une seule demande de mot de passe grâce à l'autorisation persistante. |
| **Système** | Caractéristiques complètes de la machine (puce, GPU, mémoire, batterie, résolution), accès direct aux volets des Réglages et aux utilitaires macOS, gestion des agents de démarrage. |

### Nettoyage et espace disque

| Module | Ce qu'il apporte |
|---|---|
| **Nettoyage** | Plus de trente catégories de fichiers régénérables : caches utilisateur et caches système (droits administrateur), produits de compilation Xcode et Xcode Beta, navigateurs, messageries Electron, conteneurs orphelins, artefacts de projets (`node_modules`, `.build`, `Pods`), installeurs oubliés, résidus d'applications disparues. S'y ajoutent la suppression des langues d'interface inutilisées et le journal complet des suppressions. |
| **Espace** | Repérage des fichiers volumineux, détection des doublons, anciens installeurs, et répartition du disque dossier par dossier. Tout part à la Corbeille, donc reste récupérable. |
| **Désinstaller** | Suppression d'une application et de ses résidus, traqués dans `~/`, `~/Library`, `/Library` et jusqu'aux commandes de `/usr/local/bin` liées au bundle. Fonctionne sur les applications classiques, sur Xcode et Xcode Beta avec leurs dizaines de gigaoctets sous `~/Library/Developer`, sur les outils en ligne de commande (alias regroupés, données résolues à travers les liens symboliques) et sur les fichiers cachés `~/.xxx`. Tri par taille et icône distincte par type de résidu. |

### Réglages et entretien

| Module | Ce qu'il apporte |
|---|---|
| **Fonctionnalités** | Trente-quatre réglages système activables et désactivables (Siri, Apple Intelligence, télémétrie, iCloud et d'autres), présentés par catégorie ou par sous-processus. Réversibles à cent pour cent. |
| **Tweaks** | Interrupteurs pour le Finder (fichiers cachés, extensions, barre de chemin), pour le Dock, pour le format et l'emplacement des captures d'écran, et pour l'anti-veille, lui aussi persistant. |
| **Maintenance** | Vidage du cache DNS et de la mémoire, réindexation Spotlight, gestion des instantanés Time Machine, cache d'icônes, base Launch Services, redémarrage du Dock et du Finder, compactage des bases SQLite, historique Gatekeeper, caches de polices, suppression des simulateurs iOS devenus indisponibles. |
| **Réglages** | Choix de la langue, compatibilité, autorisations persistantes, nettoyage hebdomadaire planifié, réinitialisation complète, et désinstallation de MacTuner lui-même. |

## Sécurité et confidentialité

Toute suppression passe par une liste blanche stricte, implémentée dans
`SafetyGuard`. Sont refusés sans exception : `/System`, `/usr`, les applications
protégées par SIP (Safari et les applications intégrées), les dossiers Documents,
Photos et Bureau, les trousseaux, iCloud Drive, Mail, Messages, les clés SSH et
les fichiers de configuration du shell.

Les applications Apple simplement téléchargées, comme Xcode ou Xcode Beta, ne
portent pas ce drapeau de protection : elles restent désinstallables comme
n'importe quelle autre application.

Les droits administrateur se limitent à des commandes précises, accordées par des
règles `sudoers` révocables à tout moment. MacTuner ne communique avec aucun
serveur, ne collecte aucune donnée et ne contient aucun traceur.

## SIP, la protection de l'intégrité du système

Sur macOS 26 et 27, SIP est actif par défaut et refuse l'arrêt des agents Apple :
`launchctl bootout` échoue alors avec l'erreur 150. MacTuner ne masque pas cette
limite. L'onglet **Fonctionnalités** range chaque réglage dans l'une de deux
catégories explicites.

**Effet immédiat, compatible SIP.** Réglages de préférences (`defaults`) et
commandes système telles que Spotlight, Power Nap ou le son de démarrage. Ils
s'appliquent aussitôt, que SIP soit actif ou non.

**Nécessite SIP désactivé.** Réglages qui reposent sur l'arrêt d'un agent Apple
(Siri, Apple Intelligence, télémétrie, iCloud). Tant que SIP est actif, ils
apparaissent grisés et ne sont pas modifiables, car leur effet ne surviendrait
qu'après un `csrutil disable` lancé depuis la Recovery. Ils redeviennent
disponibles automatiquement dès que SIP est désactivé.

MacTuner lit l'état réel du système : un réglage bloqué par SIP est signalé comme
tel, jamais présenté comme appliqué. Lorsque SIP est désactivé, un agent
utilisateur réapplique vos choix à chaque ouverture de session, car macOS 26 et 27
réactivent d'eux-mêmes certains agents au démarrage.

## Installation

MacTuner se compile depuis les sources. Il n'existe pas d'archive à télécharger :
le code est ici, et vous produisez vous-même le binaire que vous exécutez. C'est
le seul moyen d'avoir la certitude que l'application fait exactement ce que le
code décrit.

**Prérequis :** macOS 26 ou 27, un Mac Apple Silicon (M1 à M4), et les *Command
Line Tools* d'Apple. Aucune dépendance externe. Xcode n'est pas nécessaire.

```bash
xcode-select --install                              # une seule fois
git clone https://github.com/Bodyroro/MacTuner.git
cd MacTuner
./build.sh
```

`build.sh` compile l'ensemble des sources avec l'en-tête C `smc_bridge.h`, qui
décrit la disposition mémoire exacte attendue par le SMC. La cible est macOS 26.0,
ce qui garantit la compatibilité avec macOS 26 comme avec macOS 27. Le script
génère ensuite l'icône, signe le bundle en ad hoc, puis lance l'application.

Pour installer MacTuner durablement, glissez **MacTuner.app** dans votre dossier
**Applications**.

> Le bundle est signé en ad hoc et n'est pas notarisé. Il reste parfaitement
> valide sur votre machine puisque vous venez de le produire. Aucune manipulation
> de Gatekeeper n'est requise : cette contrainte ne concerne que les archives
> téléchargées depuis Internet.

### Compilation manuelle

Si vous préférez dérouler chaque étape vous-même :

```bash
swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
  -import-objc-header smc_bridge.h \
  Sources/**/*.swift Sources/*.swift \
  -o MacTuner.app/Contents/MacOS/MacTuner
codesign --force --sign - MacTuner.app
open MacTuner.app
```

## Architecture du projet

```
MacTuner/
├── build.sh                Compilation, signature et lancement
├── smc_bridge.h            En-tête C pour l'accès SMC via IOKit
├── logo.png                Icône source
├── dashboard.png           Capture du tableau de bord
├── LICENSE                 Licence MIT
└── Sources/
    ├── App/                Point d'entrée et TabView racine
    ├── Core/               Shell, LaunchCtl, SafetyGuard, SysInfo, SysCompat
    ├── Sensors/            SMC, statistiques processeur, GPU, mémoire, réseau, batterie
    ├── Features/           Moteurs métier : nettoyage, espace, tweaks, désinstallation,
    │                       maintenance, agents de démarrage, ventilation, planification
    ├── UI/                 Composants réutilisables : cartes, jauges, sélecteurs
    ├── Views/              Une vue SwiftUI par onglet
    ├── Localization.swift  Moteur L10n et énumération des langues
    └── Strings.swift       Table de traduction française et anglaise
```

## Langues

L'interface existe intégralement en français et en anglais. La langue se choisit
au premier lancement puis dans les Réglages, et le changement s'applique
immédiatement, sans redémarrage. Aucune chaîne n'est écrite en dur dans les vues :
tout passe par `L10n.t("clé")`, dont la table vit dans `Sources/Strings.swift`.

## Licence

Distribué sous licence **MIT**. L'utilisation, la modification et la
redistribution sont libres, sources comprises. Le texte complet se trouve dans
[`LICENSE`](LICENSE).

## Avertissement

MacTuner modifie des réglages du système. Chaque action est réversible et
protégée par des garde-fous, mais l'application s'utilise en connaissance de
cause. Elle est fournie sans garantie d'aucune sorte.

<br/>

---

# 🇬🇧 English

## Overview

MacTuner brings together, in a single native SwiftUI application, everything you
need to stay in control of your Mac: live hardware monitoring, the ability to turn
off unnecessary system features, cache cleaning, disk space recovery, residue free
uninstallation, routine maintenance, fine grained Finder and Dock settings, and
fan control.

Three principles govern the application. Nothing happens behind your back: every
action is named, explained and logged. Everything is reversible: no setting
commits your machine permanently. A central guard makes deleting critical files
impossible, whichever path you take through the interface.

MacTuner uses only mechanisms documented by Apple (`launchctl`, `defaults`, IOKit
SMC). No system file is ever modified.

## Features

### Monitoring and hardware

| Module | What it provides |
|---|---|
| **Dashboard** | Overall and per core processor load, live GPU activity, detailed memory breakdown (wired, compressed, applications), disk reads and writes, network throughput, temperature, and battery life on portables. No password required. |
| **Fan control** | Manual speed control, bounded by the manufacturer minimum and maximum, which rules out any risk of overheating. Three presets (quiet, medium, maximum) and a genuinely persistent target speed, reapplied when the app launches, when the Mac wakes and when it restarts. A single password prompt thanks to persistent authorisation. |
| **System** | Full machine specifications (chip, GPU, memory, battery, resolution), direct access to System Settings panes and macOS utilities, and management of launch agents. |

### Cleaning and disk space

| Module | What it provides |
|---|---|
| **Cleanup** | More than thirty categories of regenerable files: user and system caches (administrator rights), Xcode and Xcode Beta build products, browsers, Electron messaging apps, orphaned containers, project artefacts (`node_modules`, `.build`, `Pods`), forgotten installers, and leftovers from deleted applications. Unused interface languages and a complete deletion log are included as well. |
| **Storage** | Large file discovery, duplicate detection, old installers, and a folder by folder breakdown of the disk. Everything goes to the Trash and remains recoverable. |
| **Uninstall** | Removes an application together with its leftovers, tracked through `~/`, `~/Library`, `/Library` and even the `/usr/local/bin` commands tied to the bundle. Works on regular applications, on Xcode and Xcode Beta with their tens of gigabytes under `~/Library/Developer`, on command line tools (grouped aliases, data resolved through symbolic links) and on hidden `~/.xxx` files. Sorted by size, with a distinct icon per leftover type. |

### Settings and maintenance

| Module | What it provides |
|---|---|
| **Features** | Thirty four system settings you can enable or disable (Siri, Apple Intelligence, telemetry, iCloud and others), presented by category or by subprocess. Fully reversible. |
| **Tweaks** | Switches for the Finder (hidden files, extensions, path bar), for the Dock, for screenshot format and location, and for keeping the Mac awake, which is persistent too. |
| **Maintenance** | DNS and memory cache flushing, Spotlight reindexing, Time Machine snapshot management, icon cache, Launch Services database, Dock and Finder restart, SQLite database compaction, Gatekeeper history, font caches, and removal of iOS simulators that are no longer available. |
| **Settings** | Language selection, compatibility, persistent authorisations, scheduled weekly cleanup, full reset, and uninstallation of MacTuner itself. |

## Security and privacy

Every deletion goes through a strict allow list implemented in `SafetyGuard`. The
following are refused without exception: `/System`, `/usr`, SIP protected
applications (Safari and built in apps), the Documents, Photos and Desktop
folders, keychains, iCloud Drive, Mail, Messages, SSH keys and shell
configuration files.

Apple applications that were simply downloaded, such as Xcode or Xcode Beta, do
not carry that protection flag and remain uninstallable like any other
application.

Administrator rights are limited to specific commands, granted through `sudoers`
rules that can be revoked at any time. MacTuner talks to no server, collects no
data and contains no tracker.

## SIP, System Integrity Protection

On macOS 26 and 27, SIP is enabled by default and refuses to stop Apple agents:
`launchctl bootout` then fails with error 150. MacTuner does not hide this limit.
The **Features** tab sorts every setting into one of two explicit categories.

**Immediate effect, SIP compatible.** Preference settings (`defaults`) and system
commands such as Spotlight, Power Nap or the startup chime. They apply right away,
whether SIP is enabled or not.

**Requires SIP disabled.** Settings that rely on stopping an Apple agent (Siri,
Apple Intelligence, telemetry, iCloud). While SIP is enabled they appear greyed
out and cannot be changed, because they would only take effect after running
`csrutil disable` from Recovery. They become available again automatically once
SIP is disabled.

MacTuner reads the real system state: a setting blocked by SIP is reported as
such and never presented as applied. When SIP is disabled, a user agent reapplies
your choices at every login, because macOS 26 and 27 reactivate some agents on
their own at startup.

## Installation

MacTuner is built from source. There is no archive to download: the code is here,
and you produce the binary you run yourself. That is the only way to be certain
the application does exactly what the code describes.

**Requirements:** macOS 26 or 27, an Apple Silicon Mac (M1 to M4), and Apple's
Command Line Tools. No external dependency. Xcode is not required.

```bash
xcode-select --install                              # once only
git clone https://github.com/Bodyroro/MacTuner.git
cd MacTuner
./build.sh
```

`build.sh` compiles every source file with the C header `smc_bridge.h`, which
describes the exact memory layout the SMC expects. The target is macOS 26.0, which
guarantees compatibility with both macOS 26 and macOS 27. The script then
generates the icon, signs the bundle ad hoc, and launches the application.

To install MacTuner permanently, drag **MacTuner.app** into your **Applications**
folder.

> The bundle is signed ad hoc and is not notarised. It remains perfectly valid on
> your machine since you have just produced it. No Gatekeeper workaround is
> needed: that constraint only applies to archives downloaded from the internet.

### Manual build

If you prefer to run each step yourself:

```bash
swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
  -import-objc-header smc_bridge.h \
  Sources/**/*.swift Sources/*.swift \
  -o MacTuner.app/Contents/MacOS/MacTuner
codesign --force --sign - MacTuner.app
open MacTuner.app
```

## Project layout

```
MacTuner/
├── build.sh                Build, signing and launch
├── smc_bridge.h            C header for SMC access through IOKit
├── logo.png                Source icon
├── dashboard.png           Dashboard screenshot
├── LICENSE                 MIT licence
└── Sources/
    ├── App/                Entry point and root TabView
    ├── Core/               Shell, LaunchCtl, SafetyGuard, SysInfo, SysCompat
    ├── Sensors/            SMC, processor, GPU, memory, network and battery statistics
    ├── Features/           Business engines: cleanup, storage, tweaks, uninstall,
    │                       maintenance, launch agents, fan control, scheduling
    ├── UI/                 Reusable components: cards, gauges, pickers
    ├── Views/              One SwiftUI view per tab
    ├── Localization.swift  L10n engine and language enumeration
    └── Strings.swift       French and English translation table
```

## Languages

The interface is available in full in French and English. The language is chosen
on first launch and later in Settings, and the change applies immediately without
restarting. No string is hard coded in the views: everything goes through
`L10n.t("key")`, whose table lives in `Sources/Strings.swift`.

## Licence

Distributed under the **MIT** licence. Use, modification and redistribution are
free, sources included. The full text is available in [`LICENSE`](LICENSE).

## Disclaimer

MacTuner changes system settings. Every action is reversible and protected by
guards, but the application should be used with a clear understanding of what it
does. It is provided without warranty of any kind.

<br/>

---

<div align="center">

Créé par **Rodolphe Vandaele** &nbsp;·&nbsp; [bodyroro.github.io](https://bodyroro.github.io) &nbsp;·&nbsp; [github.com/Bodyroro/MacTuner](https://github.com/Bodyroro/MacTuner)

*Conçu pour macOS 26 et 27 sur Apple Silicon &nbsp;·&nbsp; Built for macOS 26 and 27 on Apple Silicon*

</div>
