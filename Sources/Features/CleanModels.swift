//
//  CleanModels.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Modèle : nettoyage

struct CleanCategory: Identifiable {
    let id: String
    let name: LStr
    let icon: String
    let what: LStr
    let warn: LStr
    let risk: Risk
    /// Chemins relatifs au dossier personnel (ou absolus). Seul leur CONTENU est supprimé.
    let paths: [String]
    /// Source dynamique de chemins (calculée au moment de l'analyse).
    var dynamicSource: String? = nil
    /// true = les éléments listés sont supprimés eux-mêmes (mis à la Corbeille).
    var removeItems: Bool = false
    /// true = nettoyage hors du dossier personnel (zones système). Exige les droits
    /// administrateur : la suppression passe par le helper privilégié `--clean-system`,
    /// jamais par le moteur utilisateur. Voir SystemClean / SafetyGuard.isSystemDeletable.
    var needsAdmin: Bool = false
}

let cleanCategories: [CleanCategory] = [
    CleanCategory(id: "trash", name: LStr("Corbeille", "Trash"), icon: "trash.fill",
        what: LStr("Vide la Corbeille de votre session.", "Empties your session's Trash."),
        warn: LStr("Suppression DÉFINITIVE : les fichiers ne pourront plus être récupérés, même par un utilitaire.",
                   "PERMANENT deletion: files can no longer be recovered, even by a utility."),
        risk: .moyen,
        paths: ["~/.Trash"]),

    CleanCategory(id: "usercaches", name: LStr("Caches des applications", "Application caches"), icon: "archivebox.fill",
        what: LStr("Le dossier ~/Library/Caches : données temporaires que chaque app reconstruit automatiquement (vignettes, données téléchargées, index temporaires).",
                   "The ~/Library/Caches folder: temporary data each app rebuilds automatically (thumbnails, downloaded data, temporary indexes)."),
        warn: LStr("Sans danger pour vos données, mais fermez vos apps avant : premier lancement plus lent ensuite, et certaines apps peuvent redemander une connexion.",
                   "Safe for your data, but close your apps first: the next launch is slower, and some apps may ask you to sign in again."),
        risk: .faible,
        paths: ["~/Library/Caches"]),

    CleanCategory(id: "logs", name: LStr("Journaux (logs)", "Logs"), icon: "doc.text.fill",
        what: LStr("Le dossier ~/Library/Logs : journaux d'activité des apps, qui s'accumulent sans limite.",
                   "The ~/Library/Logs folder: app activity logs that pile up without limit."),
        warn: LStr("Vous perdez l'historique de logs, parfois utile pour diagnostiquer un problème récent avec une app.",
                   "You lose the log history, sometimes useful to diagnose a recent app issue."),
        risk: .faible,
        paths: ["~/Library/Logs"]),

    CleanCategory(id: "savedstate", name: LStr("États de fenêtres enregistrés", "Saved window states"), icon: "macwindow.on.rectangle",
        what: LStr("~/Library/Saved Application State : la mémoire de « rouvrir les fenêtres à la réouverture » de chaque app.",
                   "~/Library/Saved Application State: each app's “reopen windows on relaunch” memory."),
        warn: LStr("Au prochain lancement, chaque app s'ouvrira « à neuf » sans restaurer ses fenêtres et onglets précédents (une seule fois).",
                   "At the next launch, each app opens “fresh” without restoring its previous windows and tabs (once)."),
        risk: .faible,
        paths: ["~/Library/Saved Application State"]),

    CleanCategory(id: "browsers", name: LStr("Caches des navigateurs", "Browser caches"), icon: "globe",
        what: LStr("Les caches de Safari, Chrome, Firefox, Arc, Edge et Brave : copies locales des pages et images visitées.",
                   "The caches of Safari, Chrome, Firefox, Arc, Edge and Brave: local copies of visited pages and images."),
        warn: LStr("Fermez les navigateurs avant. Les pages se rechargeront plus lentement la première fois. Ni mots de passe, ni historique, ni cookies ne sont touchés. Le cache Safari peut nécessiter l'Accès complet au disque.",
                   "Close the browsers first. Pages reload more slowly the first time. Passwords, history and cookies are untouched. The Safari cache may require Full Disk Access."),
        risk: .faible,
        paths: ["~/Library/Caches/com.apple.Safari", "~/Library/Caches/Google/Chrome",
                "~/Library/Caches/Firefox", "~/Library/Caches/company.thebrowser.Browser",
                "~/Library/Caches/Microsoft Edge", "~/Library/Caches/com.microsoft.edgemac",
                "~/Library/Caches/BraveSoftware", "~/Library/Caches/Vivaldi",
                "~/Library/Caches/com.operasoftware.Opera"]),

    CleanCategory(id: "xcode", name: LStr("Fichiers de build Xcode", "Xcode build files"), icon: "hammer.fill",
        what: LStr("DerivedData, caches du Simulateur et supports d'anciennes versions d'iOS : le grand classique des dizaines de Go perdus chez les développeurs.",
                   "DerivedData, Simulator caches and old iOS device-support files: the classic tens of GB lost by developers."),
        warn: LStr("Aucun risque pour vos projets ou archives : Xcode recompilera tout à la prochaine build (plus long une fois). Sans effet si vous n'utilisez pas Xcode.",
                   "No risk to your projects or archives: Xcode recompiles everything at the next build (slower once). No effect if you don't use Xcode."),
        risk: .faible,
        paths: ["~/Library/Developer/Xcode/DerivedData", "~/Library/Developer/CoreSimulator/Caches",
                "~/Library/Developer/Xcode/iOS DeviceSupport",
                "~/Library/Developer/Xcode/watchOS DeviceSupport",
                "~/Library/Developer/Xcode/tvOS DeviceSupport",
                "~/Library/Developer/XCTestDevices",
                // Caches d'Xcode et d'Xcode Beta (même identifiant, mêmes dossiers),
                // documentation téléchargée, produits de build et paquets Swift.
                "~/Library/Developer/Xcode/DocumentationCache",
                "~/Library/Developer/Xcode/Products",
                "~/Library/Developer/Xcode/iOS Device Logs",
                "~/Library/Developer/DVTDownloads",
                "~/Library/Developer/CoreSimulator/Temp",
                "~/Library/Caches/com.apple.dt.Xcode",
                "~/Library/Caches/com.apple.dt.instruments",
                "~/Library/Caches/org.swift.swiftpm",
                "~/Library/org.swift.swiftpm/cache"]),

    CleanCategory(id: "devcaches", name: LStr("Caches de développement", "Development caches"), icon: "shippingbox.fill",
        what: LStr("Les caches des gestionnaires de paquets : Homebrew, npm, pnpm, Yarn, Bun, pip, uv, CocoaPods, Go, Cargo, Gradle, Maven, mise et Conda. Des copies de dépendances déjà installées.",
                   "Package-manager caches: Homebrew, npm, pnpm, Yarn, Bun, pip, uv, CocoaPods, Go, Cargo, Gradle, Maven, mise and Conda. Copies of already-installed dependencies."),
        warn: LStr("Sans danger : les dépendances seront simplement retéléchargées à la prochaine installation ou build (nécessite le réseau).",
                   "Safe: dependencies are simply re-downloaded at the next install or build (needs the network)."),
        risk: .faible,
        paths: ["~/Library/Caches/Homebrew", "~/.npm", "~/Library/Caches/Yarn",
                "~/Library/Caches/pip", "~/Library/Caches/CocoaPods",
                "~/Library/Caches/go-build", "~/.cargo/registry/cache", "~/.gradle/caches",
                "~/Library/pnpm/store", "~/.bun/install/cache", "~/.cache/uv",
                "~/Library/Caches/mise", "~/.cache/node/corepack", "~/.m2/repository",
                "~/go/pkg/mod", "~/.conda/pkgs", "~/miniconda3/pkgs", "~/anaconda3/pkgs",
                "~/miniforge3/pkgs", "~/mambaforge/pkgs",
                // Caches d'outils courants (build, lint, tests, ML), tous régénérables.
                "~/.npm/_cacache", "~/.cache/pip", "~/.cache/pre-commit", "~/.pytest_cache",
                "~/.mypy_cache", "~/.cache/ruff", "~/.cache/eslint", "~/.cache/typescript",
                "~/.cache/webpack", "~/.parcel-cache", "~/.cache/puppeteer", "~/.cache/ms-playwright",
                "~/.ivy2/cache", "~/.pub-cache/hosted", "~/.cache/bazel",
                "~/.cache/huggingface", "~/.cache/torch", "~/.cache/wandb",
                "~/.android/build-cache", "~/.android/cache", "~/.aws/cli/cache"]),

    CleanCategory(id: "maildl", name: LStr("Pièces jointes Mail temporaires", "Temporary Mail attachments"), icon: "paperclip",
        what: LStr("Le dossier Mail Downloads : copies temporaires des pièces jointes ouvertes ou prévisualisées depuis Mail.",
                   "The Mail Downloads folder: temporary copies of attachments opened or previewed from Mail."),
        warn: LStr("Les originaux restent dans vos e-mails, seules les copies temporaires sont supprimées. L'accès peut nécessiter l'Accès complet au disque.",
                   "The originals stay in your emails, only the temporary copies are removed. Access may require Full Disk Access."),
        risk: .faible,
        paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]),

    CleanCategory(id: "diagreports", name: LStr("Rapports de diagnostic locaux", "Local diagnostic reports"), icon: "waveform.path.ecg",
        what: LStr("Les fichiers .ips/.crash de plantages et de spins accumulés dans DiagnosticReports, ainsi que les journaux de diagnostic.",
                   "The .ips/.crash files from crashes and spins piled up in DiagnosticReports, plus diagnostic logs."),
        warn: LStr("Vous perdez l'historique local des plantages, parfois utile pour comprendre un crash récent. Sans danger pour vos données.",
                   "You lose the local crash history, sometimes useful to understand a recent crash. Safe for your data."),
        risk: .faible,
        paths: ["~/Library/Logs/DiagnosticReports"]),

    CleanCategory(id: "appstore", name: LStr("Cache App Store & achats", "App Store & purchases cache"), icon: "bag.fill",
        what: LStr("Les caches de l'App Store, du framework Commerce et de StoreKit : vignettes, métadonnées et fichiers de téléchargement partiels.",
                   "The App Store, Commerce framework and StoreKit caches: thumbnails, metadata and partial download files."),
        warn: LStr("Sans danger : l'App Store reconstruit ces caches. Un téléchargement en cours pourrait devoir reprendre.",
                   "Safe: the App Store rebuilds these caches. A download in progress may need to restart."),
        risk: .faible,
        paths: ["~/Library/Caches/com.apple.appstore", "~/Library/Caches/com.apple.commerce",
                "~/Library/Caches/com.apple.storeagent"]),

    CleanCategory(id: "iosupdates", name: LStr("Anciennes mises à jour iOS", "Old iOS updates"), icon: "arrow.down.circle.fill",
        what: LStr("Les fichiers .ipsw de mise à jour d'iPhone/iPad téléchargés par le Finder/iTunes : plusieurs Go par version, jamais nettoyés automatiquement.",
                   "iPhone/iPad update .ipsw files downloaded by Finder/iTunes: several GB per version, never cleaned automatically."),
        warn: LStr("Sans danger : ils seront retéléchargés si vous remettez à jour un appareil par câble.",
                   "Safe: they will be re-downloaded if you update a device over cable again."),
        risk: .faible,
        paths: ["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates"]),

    CleanCategory(id: "chatapps", name: LStr("Caches Slack, Discord, Teams…", "Slack, Discord, Teams caches"), icon: "bubble.left.and.bubble.right.fill",
        what: LStr("Les caches des messageries Electron (Slack, Discord, Microsoft Teams, Spotify) : images, pièces jointes et pages mises en cache.",
                   "Electron messaging caches (Slack, Discord, Microsoft Teams, Spotify): cached images, attachments and pages."),
        warn: LStr("Sans danger : ni vos messages, ni votre session ne sont touchés (seul le cache). Fermez ces apps avant. Recharge des médias plus lente la première fois.",
                   "Safe: neither your messages nor your session are touched (cache only). Close these apps first. Media reload is slower the first time."),
        risk: .faible,
        paths: ["~/Library/Application Support/Slack/Cache",
                "~/Library/Application Support/Slack/Service Worker/CacheStorage",
                "~/Library/Application Support/Slack/Code Cache",
                "~/Library/Application Support/discord/Cache",
                "~/Library/Application Support/discord/Code Cache",
                "~/Library/Application Support/discord/GPUCache",
                "~/Library/Application Support/Microsoft/Teams/Cache",
                "~/Library/Application Support/Microsoft/Teams/Code Cache",
                "~/Library/Application Support/Microsoft/Teams/GPUCache",
                "~/Library/Caches/com.spotify.client",
                "~/Library/Application Support/Spotify/PersistentCache/Storage"]),

    CleanCategory(id: "containercaches", name: LStr("Caches des apps sandboxées", "Sandboxed app caches"), icon: "cube.box.fill",
        what: LStr("Les caches situés à l'intérieur des conteneurs sandbox (~/Library/Containers/…/Data/Library/Caches). Les apps de l'App Store rangent leurs caches ici, hors de portée du nettoyage classique.",
                   "Caches inside sandbox containers (~/Library/Containers/…/Data/Library/Caches). App Store apps keep their caches here, out of reach of the classic cleanup."),
        warn: LStr("Sans danger : ces caches se régénèrent. Fermez les apps concernées avant. Ni réglages ni données ne sont touchés (seul le sous-dossier Caches).",
                   "Safe: these caches regenerate. Close the relevant apps first. Neither settings nor data are touched (Caches subfolder only)."),
        risk: .faible,
        paths: [], dynamicSource: "containercaches"),

    CleanCategory(id: "editorcaches", name: LStr("Caches d'éditeurs & IDE", "Editor & IDE caches"), icon: "chevron.left.forwardslash.chevron.right",
        what: LStr("Caches et données temporaires de VS Code, Cursor, JetBrains, Sublime Text et Zed : index de code, caches d'extensions, données de session.",
                   "Caches and temporary data of VS Code, Cursor, JetBrains, Sublime Text and Zed: code indexes, extension caches, session data."),
        warn: LStr("Sans danger : reconstruits à l'ouverture. Vos réglages, extensions installées et projets ne sont pas touchés. Fermez l'éditeur avant.",
                   "Safe: rebuilt on open. Your settings, installed extensions and projects are untouched. Close the editor first."),
        risk: .faible,
        paths: ["~/Library/Application Support/Code/Cache", "~/Library/Application Support/Code/CachedData",
                "~/Library/Application Support/Code/Cache/Cache_Data",
                "~/Library/Application Support/Cursor/Cache", "~/Library/Application Support/Cursor/CachedData",
                "~/Library/Caches/com.microsoft.VSCode", "~/Library/Caches/com.todesktop.230313mzl4w4u92",
                "~/Library/Caches/JetBrains", "~/Library/Caches/com.sublimetext.4",
                "~/Library/Caches/dev.zed.Zed"]),

    CleanCategory(id: "quicklook", name: LStr("Miniatures QuickLook", "QuickLook thumbnails"), icon: "eye.fill",
        what: LStr("Le cache des miniatures d'aperçu générées par le Finder et la barre d'espace (QuickLook).",
                   "The cache of preview thumbnails generated by the Finder and the space bar (QuickLook)."),
        warn: LStr("Sans danger : les miniatures se régénèrent à la volée. Le premier survol d'un dossier peut être légèrement plus lent.",
                   "Safe: thumbnails regenerate on the fly. The first browse of a folder may be slightly slower."),
        risk: .faible,
        paths: ["~/Library/Caches/com.apple.QuickLook.thumbnailcache"]),

    CleanCategory(id: "orphancontainers", name: LStr("Conteneurs orphelins (sandbox)", "Orphaned containers (sandbox)"), icon: "shippingbox",
        what: LStr("Chaque app sandboxée reçoit un « conteneur » privé dans ~/Library/Containers. Quand l'app est supprimée sans désinstallateur, son conteneur reste. Cette catégorie liste uniquement les conteneurs dont l'app n'existe plus, jamais ceux d'Apple.",
                   "Each sandboxed app gets a private “container” in ~/Library/Containers. When the app is deleted without an uninstaller, its container remains. This category only lists containers whose app no longer exists, never Apple's."),
        warn: LStr("Dépliez pour vérifier la liste : si vous comptez réinstaller une de ces apps, son conteneur (réglages, données) sera perdu. Envoyé à la Corbeille, donc récupérable.",
                   "Expand to check the list: if you plan to reinstall one of these apps, its container (settings, data) will be lost. Sent to the Trash, so recoverable."),
        risk: .moyen,
        paths: [], dynamicSource: "orphancontainers", removeItems: true),

    CleanCategory(id: "iosbackups", name: LStr("Sauvegardes iPhone/iPad locales", "Local iPhone/iPad backups"), icon: "iphone.gen3",
        what: LStr("Les sauvegardes complètes d'iPhone/iPad faites par câble via le Finder, stockées dans MobileSync. Souvent des dizaines de Go de vieux appareils.",
                   "Full iPhone/iPad backups made over cable via the Finder, stored in MobileSync. Often tens of GB from old devices."),
        warn: LStr("DÉFINITIF et risqué : vous perdez la possibilité de restaurer depuis ces sauvegardes. Vérifiez d'abord qu'une sauvegarde iCloud récente existe ou que ces appareils ne vous servent plus.",
                   "PERMANENT and risky: you lose the ability to restore from these backups. First check that a recent iCloud backup exists or that these devices are no longer needed."),
        risk: .eleve,
        paths: ["~/Library/Application Support/MobileSync/Backup"]),

    CleanCategory(id: "groupcaches", name: LStr("Caches des groupes d'apps", "App group caches"), icon: "square.grid.3x3.fill",
        what: LStr("Les caches à l'intérieur des « Group Containers » (~/Library/Group Containers/…/Library/Caches), partagés entre une app et ses extensions. Hors de portée du nettoyage classique de ~/Library/Caches.",
                   "Caches inside “Group Containers” (~/Library/Group Containers/…/Library/Caches), shared between an app and its extensions. Out of reach of the classic ~/Library/Caches cleanup."),
        warn: LStr("Sans danger : ces caches se régénèrent. Fermez les apps concernées avant. Ni réglages ni données partagées ne sont touchés (seul le sous-dossier Caches).",
                   "Safe: these caches regenerate. Close the relevant apps first. Neither settings nor shared data are touched (Caches subfolder only)."),
        risk: .faible,
        paths: [], dynamicSource: "groupcontainercaches"),

    CleanCategory(id: "crashreporter", name: LStr("Historique de plantages (CrashReporter)", "Crash history (CrashReporter)"), icon: "exclamationmark.octagon.fill",
        what: LStr("Le dossier ~/Library/Application Support/CrashReporter : métadonnées et journaux accumulés par le rapporteur de plantages de macOS.",
                   "The ~/Library/Application Support/CrashReporter folder: metadata and logs piled up by the macOS crash reporter."),
        warn: LStr("Vous perdez l'historique local de plantages, parfois utile pour diagnostiquer. Sans danger pour vos données.",
                   "You lose the local crash history, sometimes useful to diagnose. Safe for your data."),
        risk: .faible,
        paths: ["~/Library/Application Support/CrashReporter"]),

    CleanCategory(id: "idleassets", name: LStr("Fonds d'écran dynamiques téléchargés", "Downloaded dynamic wallpapers"), icon: "photo.on.rectangle.angled",
        what: LStr("Les économiseurs d'écran et fonds d'écran aériens/dynamiques téléchargés par macOS (com.apple.idleassetsd) : plusieurs Go de vidéos 4K.",
                   "The aerial/dynamic screensavers and wallpapers downloaded by macOS (com.apple.idleassetsd): several GB of 4K videos."),
        warn: LStr("Sans danger : macOS les retéléchargera à la demande si vous réactivez un fond aérien. Nécessite le réseau.",
                   "Safe: macOS re-downloads them on demand if you re-enable an aerial wallpaper. Needs the network."),
        risk: .faible,
        paths: ["~/Library/Application Support/com.apple.idleassetsd/Customer"]),

    CleanCategory(id: "electroncaches", name: LStr("Caches des apps Electron/Chromium", "Electron/Chromium app caches"), icon: "app.connected.to.app.below.fill",
        what: LStr("Les sous-dossiers de cache régénérables (Cache, Code Cache, GPUCache, Service Worker…) de toutes vos apps Electron : Notion, Obsidian, WhatsApp, Codex, Linear, Figma et bien d'autres, détectées automatiquement dans Application Support.",
                   "The regenerable cache subfolders (Cache, Code Cache, GPUCache, Service Worker…) of all your Electron apps: Notion, Obsidian, WhatsApp, Codex, Linear, Figma and many more, auto-detected in Application Support."),
        warn: LStr("Sans danger : ces caches se reconstruisent au lancement. Fermez les apps concernées avant ; ni comptes, ni messages, ni réglages ne sont touchés. Recharge des médias plus lente la première fois.",
                   "Safe: these caches rebuild on launch. Close the relevant apps first; accounts, messages and settings are untouched. Media reload is slower the first time."),
        risk: .faible,
        paths: [], dynamicSource: "electroncaches"),

    CleanCategory(id: "adobemedia", name: LStr("Cache média Adobe", "Adobe media cache"), icon: "film.stack.fill",
        what: LStr("Les fichiers de cache média de Premiere, After Effects et Media Encoder (Adobe/Common/Media Cache) : versions décodées et fichiers de pointe, souvent des dizaines de Go.",
                   "The media cache files of Premiere, After Effects and Media Encoder (Adobe/Common/Media Cache): decoded versions and peak files, often tens of GB."),
        warn: LStr("Sans danger : Adobe régénère ces caches à l'ouverture des projets (premier rendu plus lent). Fermez les apps Adobe avant.",
                   "Safe: Adobe regenerates these caches when projects open (first render is slower). Close Adobe apps first."),
        risk: .faible,
        paths: ["~/Library/Application Support/Adobe/Common/Media Cache Files",
                "~/Library/Application Support/Adobe/Common/Media Cache",
                "~/Library/Application Support/Adobe/Common/Peak Files"]),

    CleanCategory(id: "devartifacts", name: LStr("Artefacts de projets de dev", "Project build artifacts"), icon: "hammer.circle.fill",
        what: LStr("Les dossiers régénérés par un simple build dans vos projets : node_modules, .build, target, dist, venv, __pycache__, Pods, .next… Recherchés dans tout votre dossier personnel, jusqu'à quatre niveaux de profondeur (hors ~/Library et médiathèques).",
                   "The folders any build regenerates inside your projects: node_modules, .build, target, dist, venv, __pycache__, Pods, .next… Searched across your whole home folder, up to four levels deep (excluding ~/Library and media libraries)."),
        warn: LStr("Aucun code source n'est touché : seuls des dossiers de dépendances et de compilation, reconstruits par « npm install », « swift build », « pod install »… Prévoyez du réseau et un premier build plus long. Envoyés à la Corbeille, donc récupérables.",
                   "No source code is touched: only dependency and build folders, rebuilt by “npm install”, “swift build”, “pod install”… Expect network use and a slower first build. Sent to the Trash, so recoverable."),
        risk: .moyen,
        paths: [], dynamicSource: "devartifacts", removeItems: true),

    CleanCategory(id: "installers", name: LStr("Installeurs téléchargés", "Downloaded installers"), icon: "shippingbox.and.arrow.backward.fill",
        what: LStr("Les fichiers d'installation (.dmg, .pkg, .xip, .iso) qui traînent dans Téléchargements et sur le Bureau depuis plus de 30 jours. L'app est installée : l'installeur ne sert plus à rien.",
                   "The installer files (.dmg, .pkg, .xip, .iso) sitting in Downloads and on the Desktop for more than 30 days. The app is installed: the installer is dead weight."),
        warn: LStr("Vérifiez la liste dans les détails : il faudra retélécharger un installeur si vous vouliez conserver une version précise d'une app. Envoyés à la Corbeille, donc récupérables.",
                   "Check the list in the details: you would have to download an installer again if you wanted to keep a specific version of an app. Sent to the Trash, so recoverable."),
        risk: .moyen,
        paths: [], dynamicSource: "installers", removeItems: true),

    CleanCategory(id: "orphanleftovers", name: LStr("Résidus d'apps disparues", "Leftovers of removed apps"), icon: "questionmark.folder.fill",
        what: LStr("Les préférences, dossiers de support, caches et états de fenêtres portant l'identifiant d'une app qui n'est plus installée : ce que laisse derrière elle une app supprimée d'un simple glisser vers la Corbeille.",
                   "The preferences, support folders, caches and window states carrying the identifier of an app that is no longer installed: what an app leaves behind when it is simply dragged to the Trash."),
        warn: LStr("Dépliez pour vérifier la liste : si vous comptez réinstaller une de ces apps, ses réglages seront perdus. Jamais les identifiants Apple, ni ceux d'un éditeur dont une app reste installée. Envoyés à la Corbeille, donc récupérables.",
                   "Expand to check the list: if you plan to reinstall one of these apps, its settings will be lost. Never Apple identifiers, nor those of a vendor whose app is still installed. Sent to the Trash, so recoverable."),
        risk: .moyen,
        paths: [], dynamicSource: "orphanleftovers", removeItems: true),

    // MARK: Nettoyage niveau système (droits administrateur requis)

    CleanCategory(id: "syscrash", name: LStr("Rapports de plantage système", "System crash reports"), icon: "burst.fill",
        what: LStr("Les rapports de plantage à l'échelle de la machine (/Library/Logs/DiagnosticReports) : fichiers .ips/.crash de tous les utilisateurs et processus système.",
                   "The machine-wide crash reports (/Library/Logs/DiagnosticReports): .ips/.crash files from all users and system processes."),
        warn: LStr("Zone système : nécessite les droits administrateur. Vous perdez l'historique global des plantages. Sans danger pour vos données.",
                   "System area: requires administrator rights. You lose the global crash history. Safe for your data."),
        risk: .faible,
        paths: ["/Library/Logs/DiagnosticReports"], needsAdmin: true),

    CleanCategory(id: "syslogs", name: LStr("Journaux système", "System logs"), icon: "doc.text.below.ecg",
        what: LStr("Les journaux d'activité du système (/private/var/log) : logs applicatifs et système, archives .gz et .asl accumulées.",
                   "The system activity logs (/private/var/log): application and system logs, .gz and .asl archives piled up."),
        warn: LStr("Zone système : nécessite les droits administrateur. Certains fichiers en cours d'utilisation seront ignorés. Vous perdez l'historique système récent.",
                   "System area: requires administrator rights. Files in use are skipped. You lose the recent system history."),
        risk: .faible,
        paths: ["/private/var/log"], needsAdmin: true),

    CleanCategory(id: "sysdiag", name: LStr("Journaux de diagnostic système", "System diagnostic logs"), icon: "stethoscope",
        what: LStr("La base de diagnostic du système (/private/var/db/diagnostics et DiagnosticPipeline) : traces .tracev3 et données de diagnostic unifiées.",
                   "The system diagnostic database (/private/var/db/diagnostics and DiagnosticPipeline): .tracev3 traces and unified diagnostic data."),
        warn: LStr("Zone système : nécessite les droits administrateur. Vous perdez les traces de diagnostic récentes. Sans danger pour vos données.",
                   "System area: requires administrator rights. You lose the recent diagnostic traces. Safe for your data."),
        risk: .faible,
        paths: ["/private/var/db/diagnostics", "/private/var/db/DiagnosticPipeline"], needsAdmin: true),

    CleanCategory(id: "powerlogs", name: LStr("Journaux d'alimentation (Power logs)", "Power logs"), icon: "bolt.fill",
        what: LStr("La base des journaux d'énergie (/private/var/db/powerlog) : historique détaillé de consommation utilisé par les rapports de batterie.",
                   "The energy-log database (/private/var/db/powerlog): detailed consumption history used by battery reports."),
        warn: LStr("Zone système : nécessite les droits administrateur. Vous perdez l'historique d'énergie ; il se reconstruit ensuite. Sans danger pour vos données.",
                   "System area: requires administrator rights. You lose the energy history; it rebuilds afterwards. Safe for your data."),
        risk: .faible,
        paths: ["/private/var/db/powerlog"], needsAdmin: true),

    CleanCategory(id: "syscaches", name: LStr("Caches système", "System caches"), icon: "externaldrive.fill.badge.xmark",
        what: LStr("Le dossier /Library/Caches : caches partagés à l'échelle de la machine, régénérés automatiquement par le système et les apps installées pour tous les utilisateurs.",
                   "The /Library/Caches folder: machine-wide shared caches, automatically regenerated by the system and by apps installed for all users."),
        warn: LStr("Zone système : nécessite les droits administrateur. Sans danger, mais premier lancement plus lent ensuite. Fermez vos apps avant.",
                   "System area: requires administrator rights. Safe, but the next launch is slower. Close your apps first."),
        risk: .faible,
        paths: ["/Library/Caches"], needsAdmin: true),

    CleanCategory(id: "systemp", name: LStr("Fichiers temporaires système", "System temporary files"), icon: "clock.badge.xmark.fill",
        what: LStr("Les dossiers temporaires du système (/private/tmp et /private/var/tmp) : fichiers de travail laissés par les processus et installeurs.",
                   "The system temp folders (/private/tmp and /private/var/tmp): scratch files left behind by processes and installers."),
        warn: LStr("Zone système : nécessite les droits administrateur. Les fichiers en cours d'utilisation sont ignorés. Sans danger pour vos données.",
                   "System area: requires administrator rights. Files in use are skipped. Safe for your data."),
        risk: .faible,
        paths: ["/private/tmp", "/private/var/tmp"], needsAdmin: true),

    CleanCategory(id: "sysupdates", name: LStr("Mises à jour système téléchargées", "Downloaded system updates"), icon: "arrow.down.app.fill",
        what: LStr("Le dossier /Library/Updates : paquets de mise à jour macOS déjà téléchargés, conservés après installation.",
                   "The /Library/Updates folder: already-downloaded macOS update packages, kept after installation."),
        warn: LStr("Zone système : nécessite les droits administrateur. Sans danger : ils seront retéléchargés si nécessaire. Les éléments protégés par le système sont ignorés.",
                   "System area: requires administrator rights. Safe: they will be re-downloaded if needed. System-protected items are skipped."),
        risk: .faible,
        paths: ["/Library/Updates"], needsAdmin: true),

    CleanCategory(id: "languages", name: LStr("Fichiers de langue inutilisés", "Unused language files"), icon: "character.bubble.fill",
        what: LStr("Les traductions (.lproj) que vos applications embarquent pour des dizaines de langues que vous n'utilisez pas. MacTuner conserve toujours le français, l'anglais et Base.",
                   "The translations (.lproj) your apps bundle for dozens of languages you never use. MacTuner always keeps French, English and Base."),
        warn: LStr("⚠️ IRRÉVERSIBLE. Modifier le contenu d'une app invalide sa signature de code : la plupart continuent de fonctionner, mais certaines peuvent refuser de s'ouvrir ou se dire « endommagées ». La seule façon de récupérer une langue est de RÉINSTALLER l'app. Nécessite les droits administrateur.",
                   "⚠️ IRREVERSIBLE. Modifying an app's contents invalidates its code signature: most keep working, but some may refuse to open or report being “damaged”. The only way to get a language back is to REINSTALL the app. Requires administrator rights."),
        risk: .eleve,
        paths: [], dynamicSource: "languages", needsAdmin: true),

    CleanCategory(id: "externaltrash", name: LStr("Corbeilles des volumes externes", "External volumes' trash"), icon: "trash.slash.fill",
        what: LStr("Les corbeilles cachées (.Trashes) laissées sur vos disques externes et clés USB montés : fichiers supprimés depuis ces volumes mais jamais vidés.",
                   "The hidden trashes (.Trashes) left on your mounted external disks and USB keys: files deleted from those volumes but never emptied."),
        warn: LStr("Suppression DÉFINITIVE des fichiers mis à la corbeille sur ces volumes. Nécessite les droits administrateur. N'affecte que les volumes actuellement montés.",
                   "PERMANENT deletion of files trashed on those volumes. Requires administrator rights. Only affects currently mounted volumes."),
        risk: .moyen,
        paths: [], dynamicSource: "externaltrash", needsAdmin: true),
]

struct PathStat: Identifiable {
    let id: String        // chemin affiché (avec ~)
    let fullPath: String  // chemin absolu
    let bytes: Int64
    let exists: Bool
}
