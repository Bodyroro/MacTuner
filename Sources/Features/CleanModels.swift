//
//  CleanModels.swift — MacTuner
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
                "~/Library/Caches/Microsoft Edge", "~/Library/Caches/BraveSoftware"]),

    CleanCategory(id: "xcode", name: LStr("Fichiers de build Xcode", "Xcode build files"), icon: "hammer.fill",
        what: LStr("DerivedData, caches du Simulateur et supports d'anciennes versions d'iOS : le grand classique des dizaines de Go perdus chez les développeurs.",
                   "DerivedData, Simulator caches and old iOS device-support files: the classic tens of GB lost by developers."),
        warn: LStr("Aucun risque pour vos projets ou archives : Xcode recompilera tout à la prochaine build (plus long une fois). Sans effet si vous n'utilisez pas Xcode.",
                   "No risk to your projects or archives: Xcode recompiles everything at the next build (slower once). No effect if you don't use Xcode."),
        risk: .faible,
        paths: ["~/Library/Developer/Xcode/DerivedData", "~/Library/Developer/CoreSimulator/Caches",
                "~/Library/Developer/Xcode/iOS DeviceSupport"]),

    CleanCategory(id: "devcaches", name: LStr("Caches de développement", "Development caches"), icon: "shippingbox.fill",
        what: LStr("Les caches des gestionnaires de paquets : Homebrew, npm, Yarn, pip, CocoaPods, Go, Cargo et Gradle. Des copies de dépendances déjà installées.",
                   "Package-manager caches: Homebrew, npm, Yarn, pip, CocoaPods, Go, Cargo and Gradle. Copies of already-installed dependencies."),
        warn: LStr("Sans danger : les dépendances seront simplement retéléchargées à la prochaine installation ou build (nécessite le réseau).",
                   "Safe: dependencies are simply re-downloaded at the next install or build (needs the network)."),
        risk: .faible,
        paths: ["~/Library/Caches/Homebrew", "~/.npm", "~/Library/Caches/Yarn",
                "~/Library/Caches/pip", "~/Library/Caches/CocoaPods",
                "~/Library/Caches/go-build", "~/.cargo/registry/cache", "~/.gradle/caches"]),

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
                "~/Library/Application Support/discord/Cache",
                "~/Library/Application Support/Microsoft/Teams/Cache",
                "~/Library/Caches/com.spotify.client"]),

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
]

struct PathStat: Identifiable {
    let id: String        // chemin affiché (avec ~)
    let fullPath: String  // chemin absolu
    let bytes: Int64
    let exists: Bool
}
