<div align="center">

<img src="logo.png" width="120" alt="MacTuner"/>

# MacTuner

**Le centre de contrôle, de réglage et d'entretien de votre Mac Apple Silicon.**
*The all-in-one control, tuning and maintenance center for your Apple Silicon Mac.*

![Version](https://img.shields.io/badge/version-1.0.1-blue)
![Platform](https://img.shields.io/badge/macOS-26_·_27-black?logo=apple)
![Chip](https://img.shields.io/badge/Apple_Silicon-only-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)
![Langues](https://img.shields.io/badge/langues-FR_·_EN-lightgrey)

**🇫🇷 Français · 🇬🇧 English** — *Libre et open source · Free and open source*

<br/>

<img src="dashboard.png" width="880" alt="Tableau de bord MacTuner : CPU par cœur, mémoire, disque, réseau et ventilation en temps réel"/>

</div>

---

## 🇫🇷 Présentation

MacTuner rassemble en une seule application native (SwiftUI) tout ce qu'il faut pour maîtriser son Mac : **surveiller** le matériel en temps réel, **désactiver** les fonctionnalités système superflues, **nettoyer** l'espace disque, **désinstaller** sans résidu, **entretenir** le système et **piloter la ventilation**.

Un principe constant : *rien n'est fait dans votre dos, tout est réversible, et un garde-fou central rend impossible la suppression de fichiers critiques.* MacTuner n'utilise que des mécanismes documentés d'Apple (`launchctl`, `defaults`, IOKit SMC) — aucun fichier système n'est jamais modifié.

## 🇬🇧 Overview

MacTuner brings together, in a single native SwiftUI app, everything needed to master your Mac: **monitor** the hardware live, **disable** unneeded system features, **clean** disk space, **uninstall** with zero leftovers, **maintain** the system and **control the fan**. Nothing happens behind your back, everything is reversible, and a central guard makes deleting critical files impossible.

## Fonctionnalités · Features

| | |
|---|---|
| 📊 **Tableau de bord** | CPU (global + par cœur), mémoire, disque, réseau, température, **batterie** (portables), ventilation — temps réel, sans mot de passe. |
| 🌀 **Ventilation** | Contrôle manuel borné au min/max constructeur (zéro surchauffe), presets, réapplication au démarrage. Un seul mot de passe grâce à l'autorisation persistante. |
| ⚙️ **Fonctionnalités** | 34 réglages système désactivables/réactivables (Siri, Apple Intelligence, télémétrie, iCloud…), par catégorie ou par sous-processus. 100% réversible. |
| 🧹 **Nettoyage** | 18 catégories de fichiers régénérables : caches, journaux, builds Xcode, navigateurs, messageries, conteneurs orphelins. |
| 🗑️ **Désinstaller** | Apps, outils CLI (alias regroupés, données résolues via symlinks) et fichiers cachés `~/.xxx`, sans aucune trace. |
| 🔧 **Maintenance** | Cache DNS, mémoire, réindex Spotlight, snapshots Time Machine, cache d'icônes, Launch Services, Dock/Finder. |
| 📈 **Gains** | Mesures réelles : RAM, temps CPU, espace disque libéré. |

## SIP · System Integrity Protection

Sur macOS 26/27, **SIP** (activé par défaut) refuse d'arrêter les agents Apple : `launchctl bootout` renvoie l'erreur 150. MacTuner ne le cache pas — l'onglet **Fonctionnalités** classe chaque réglage en **deux catégories claires** :

- ✅ **Effet immédiat (compatibles SIP)** — réglages de préférences (`defaults`) et commandes système (Spotlight, Power Nap, son de démarrage…). Ils s'appliquent tout de suite, que SIP soit activé ou non.
- ⚠️ **Nécessite SIP désactivé** — réglages qui reposent sur l'**arrêt d'un agent Apple** (Siri, Apple Intelligence, télémétrie, iCloud…). Avec SIP activé, ces réglages sont **grisés et non modifiables** dans l'app (leur effet n'arriverait qu'après `csrutil disable` depuis la Recovery). Ils redeviennent actifs automatiquement une fois SIP désactivé.

MacTuner mesure l'état réel (RAM/processus réellement arrêtés) : aucun « gain » fictif n'est affiché quand SIP bloque l'arrêt. Quand SIP est désactivé, un LaunchAgent utilisateur ré-applique vos choix à chaque ouverture de session, car macOS 26/27 réactive de lui-même certains agents au démarrage.

*🇬🇧 On macOS 26/27, SIP refuses to stop Apple agents (`bootout` fails with error 150). The **Features** tab splits every setting into two categories: **Immediate effect (SIP-compatible)** — preference and system commands that apply right away — and **Requires SIP disabled** — settings that rely on stopping an Apple agent, which only take effect after `csrutil disable` from Recovery. MacTuner measures the real state and never shows fictitious gains.*

## Sécurité

Toute suppression passe par une **liste blanche stricte** (`SafetyGuard`) : `/System`, `/usr`, apps Apple, Documents/Photos/Bureau, trousseaux, iCloud Drive, Mail, Messages, clés SSH et fichiers shell sont refusés d'office. Les droits administrateur se limitent à des commandes précises via des règles `sudoers` **révocables**. Seuls des mécanismes documentés d'Apple sont utilisés (`launchctl`, `defaults`, IOKit SMC) — aucun fichier système n'est jamais modifié.

## Langues · Languages

Interface entièrement **française et anglaise**, choix au premier lancement et dans les Réglages, changement à chaud. Aucune chaîne en dur : tout passe par `L10n.t("clé")` (`Sources/Strings.swift`).

## Installation

**Prêt à l'emploi, aucun outil de développement requis.**

1. Téléchargez `MacTuner-1.0.1.zip` depuis la page [**Releases**](https://github.com/Bodyroro/MacTuner/releases/latest).
2. Décompressez l'archive, puis glissez **MacTuner.app** dans votre dossier **Applications**.
3. Au premier lancement, faites un **clic droit sur l'app → Ouvrir**. L'app est signée en ad-hoc (non notarisée) : macOS demande une confirmation, une seule fois.

> Si Gatekeeper bloque encore l'ouverture, levez la mise en quarantaine :
> ```bash
> xattr -dr com.apple.quarantine /Applications/MacTuner.app
> ```

*English — download `MacTuner-1.0.1.zip` from [Releases](https://github.com/Bodyroro/MacTuner/releases/latest), move **MacTuner.app** to **Applications**, then right-click → Open on first launch.*

Prérequis : **macOS 26 ou 27**, Mac **Apple Silicon** (M1 à M4).

## Compilation à partir des sources

Prérequis : **macOS 26 ou 27**, Apple Silicon, les *Command Line Tools* (Swift 6+). Aucune dépendance externe, pas de Xcode requis.

```bash
git clone https://github.com/Bodyroro/MacTuner.git
cd MacTuner
./build.sh
```

`build.sh` compile toutes les sources avec l'en-tête C `smc_bridge.h` (disposition mémoire exacte pour le SMC), cible **macOS 26.0** (garantit la compatibilité 26 **et** 27), génère l'icône, signe le bundle en ad-hoc et lance l'app.

Compilation manuelle équivalente :

```bash
swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
  -import-objc-header smc_bridge.h \
  Sources/**/*.swift Sources/*.swift \
  -o MacTuner.app/Contents/MacOS/MacTuner
codesign --force --sign - MacTuner.app
open MacTuner.app
```

## Architecture

```
mactuner/
├── build.sh                  Compilation + signature + lancement
├── smc_bridge.h              En-tête C pour l'accès SMC (IOKit)
├── logo.png                  Icône source
├── dashboard.png             Capture du tableau de bord (README)
├── CHANGELOG.md              Historique des versions
├── Sources/
│   ├── Localization.swift    Moteur L10n + enum Lang
│   ├── Strings.swift         Table de traduction FR / EN
│   ├── Core/                 Shell, LaunchCtl, SafetyGuard, SysInfo, SysCompat, Helpers
│   ├── Sensors/              SMC, statistiques système, batterie
│   ├── Features/             Fonctionnalités, nettoyage, désinstallation, maintenance,
│   │                         ventilateur, autorisations, modèles
│   ├── UI/                   Composants réutilisables (cartes, jauges, sélecteurs)
│   ├── Views/                Une vue SwiftUI par onglet
│   └── App/                  Point d'entrée, TabView racine
```

## Licence

**MIT** — totalement libre à l'utilisation, à la modification et à la redistribution, sources comprises. Voir [`LICENSE`](LICENSE).

## Avertissement

MacTuner modifie des réglages système. Toutes les actions sont réversibles et protégées par des garde-fous, mais utilisez-le en connaissance de cause. Fourni sans garantie.

---

<div align="center">

Créé par **Rodolphe Vandaele** · [bodyroro.github.io](https://bodyroro.github.io) · [github.com/Bodyroro/MacTuner](https://github.com/Bodyroro/MacTuner)

*Conçu pour macOS 26–27 · Apple Silicon*

</div>
