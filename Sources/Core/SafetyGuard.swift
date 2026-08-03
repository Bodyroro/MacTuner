//
//  SafetyGuard.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Garde-fou central

/// TOUTE suppression de MacTuner (nettoyage comme désinstallation) passe par ce filtre.
/// Liste blanche stricte : ce qui n'est pas explicitement autorisé est refusé.
enum SafetyGuard {

    /// Drapeau système `SF_RESTRICTED` : posé par macOS sur tout ce que protège SIP
    /// (volume scellé, cryptexes, apps intégrées). C'est le seul critère fiable pour
    /// distinguer une app Apple INTÉGRÉE (Safari, Musique…) d'une app Apple
    /// TÉLÉCHARGÉE et parfaitement désinstallable (Xcode, Xcode Beta, Configurator…).
    private static let sfRestricted: UInt32 = 0x0008_0000

    /// true si le chemin est protégé par SIP. `lstat` (et non `stat`) : Safari.app
    /// est un lien symbolique vers un cryptexe, c'est le lien qui porte le drapeau.
    static func isSIPProtected(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_flags & sfRestricted) != 0
    }

    /// Dossiers d'artefacts de build : régénérés par un simple `build` / `install`,
    /// jamais du code source. Liste blanche stricte (nom exact du dossier).
    static let buildArtifactNames: Set<String> = [
        "node_modules", ".build", "build", "dist", "target", "out",
        "venv", ".venv", "env", "__pycache__", ".pytest_cache", ".mypy_cache",
        ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".angular",
        "Pods", "Carthage", "DerivedData", ".gradle", ".terraform", "vendor",
    ]

    /// Extensions d'installeurs supprimables (jamais une archive de données).
    static let installerExtensions: Set<String> = ["dmg", "pkg", "xip", "iso", "cdr"]

    /// Dossiers de /Library qui structurent macOS : jamais supprimables, même si le
    /// nom d'une app semble correspondre. Tout autre dossier de /Library est considéré
    /// comme un dossier d'éditeur (/Library/Parallels, /Library/Google…).
    static let librarySystemFolders: Set<String> = [
        "Apple", "Application Support", "Audio", "Bluetooth", "Caches", "ColorPickers",
        "ColorSync", "Components", "Compositions", "CoreAnalytics", "CoreMediaIO",
        "Developer", "Documentation", "DriverExtensions", "Extensions", "Filesystems",
        "Fonts", "Frameworks", "GPUBundles", "Graphics", "Image Capture",
        "Input Methods", "InstallerSandboxes", "Internet Plug-Ins", "Java",
        "KernelCollections", "Keyboard Layouts", "Keychains", "LaunchAgents",
        "LaunchDaemons", "Logs", "Managed Preferences", "Modem Scripts", "OpenDirectory",
        "PDF Services", "Perl", "Preferences", "PreferencePanes", "Printers",
        "PrivilegedHelperTools", "Python", "QuickLook", "QuickTime", "Ruby", "Sandbox",
        "Screen Savers", "ScriptingAdditions", "Security", "Speech", "Spotlight",
        "StagedExtensions", "StartupItems", "SystemExtensions", "SystemProfiler",
        "SystemMigration", "TeX", "Updates", "User Pictures", "User Template",
        "Video", "WebServer", "Widgets", "AppStore", "AutoBugCapture",
        "Contextual Menu Items",
    ]

    /// Autorise la suppression d'un dossier d'artefacts de build. Conditions cumulées :
    /// nom exactement dans la liste blanche, à l'intérieur du dossier personnel, jamais
    /// dans ~/Library ni ~/.Trash, et jamais à la racine du dossier personnel (il faut
    /// être dans un projet). Suppression vers la Corbeille, donc récupérable.
    static func isBuildArtifactDeletable(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("..") else { return false }
        let std = (path as NSString).standardizingPath
        let home = NSHomeDirectory()
        guard std.hasPrefix(home + "/") else { return false }
        let rel = String(std.dropFirst(home.count + 1))
        let comps = rel.split(separator: "/").map(String.init)
        // Au moins « <projet>/<artefact> » : jamais un dossier posé à la racine du home.
        guard comps.count >= 2 else { return false }
        guard !["Library", ".Trash", ".ssh", ".gnupg"].contains(comps[0]) else { return false }
        return buildArtifactNames.contains(comps[comps.count - 1])
    }

    /// Autorise la suppression d'un fichier d'installeur : extension connue, fichier
    /// posé DIRECTEMENT dans Téléchargements ou Bureau (jamais dans un sous-dossier,
    /// où il ferait sans doute partie d'un projet). Vers la Corbeille.
    static func isInstallerDeletable(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("..") else { return false }
        let std = (path as NSString).standardizingPath
        let home = NSHomeDirectory()
        let dir = (std as NSString).deletingLastPathComponent
        guard dir == home + "/Downloads" || dir == home + "/Desktop" else { return false }
        return installerExtensions.contains((std as NSString).pathExtension.lowercased())
    }

    /// Autorise la mise à la Corbeille d'un fichier CHOISI UN PAR UN dans l'onglet
    /// Espace (fichier volumineux, doublon, installeur). Contrairement au nettoyage
    /// par catégorie, l'utilisateur voit et coche chaque fichier : les dossiers
    /// personnels sont donc admis, mais uniquement pour des FICHIERS (jamais un
    /// dossier), hors ~/Library, ~/.Trash et zones sensibles.
    static func isSelectedFileDeletable(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("..") else { return false }
        let std = (path as NSString).standardizingPath
        let home = NSHomeDirectory()
        guard std.hasPrefix(home + "/") else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: std, isDirectory: &isDir),
              !isDir.boolValue else { return false }
        let rel = String(std.dropFirst(home.count + 1))
        let top = rel.split(separator: "/").first.map(String.init) ?? rel
        let denied: Set<String> = ["Library", ".Trash", ".ssh", ".gnupg", "Applications"]
        return !denied.contains(top)
    }

    static func isDeletable(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("..") else { return false }
        let std = (path as NSString).standardizingPath
        let home = NSHomeDirectory()

        // Zones système absolument interdites (le volume scellé les protège déjà,
        // mais on refuse même d'essayer).
        let denied = ["/System", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec",
                      "/usr/share", "/usr/standalone", "/bin", "/sbin", "/etc", "/var",
                      "/private", "/dev", "/Volumes", "/Library/Apple", "/Library/Developer/CommandLineTools"]
        for d in denied where std == d || std.hasPrefix(d + "/") { return false }

        // Racines jamais supprimables elles-mêmes (seul leur contenu ciblé peut l'être).
        let roots: Set<String> = ["/", "/Applications", "/Applications/Utilities", "/Library",
                                  "/usr", "/usr/local", "/usr/local/bin", "/opt", "/opt/homebrew",
                                  "/opt/homebrew/bin", home, home + "/Library", home + "/Applications",
                                  home + "/.local", home + "/.local/bin", home + "/.local/share",
                                  home + "/.local/state", home + "/.config", home + "/.cache"]
        if roots.contains(std) { return false }

        // Une app protégée par SIP n'est jamais supprimable (Safari, apps intégrées).
        // Les apps Apple simplement TÉLÉCHARGÉES (Xcode, Xcode Beta, Configurator…)
        // ne portent pas ce drapeau : elles se désinstallent comme n'importe quelle app.
        if std.hasSuffix(".app"), isSIPProtected(std) { return false }

        // Artefacts de build et installeurs : autorisés même dans les dossiers
        // personnels protégés ci-dessous (liste blanche stricte, vers la Corbeille).
        if isBuildArtifactDeletable(std) || isInstallerDeletable(std) { return true }

        if std.hasPrefix(home + "/") {
            let rel = String(std.dropFirst(home.count + 1))
            let top = rel.split(separator: "/").first.map(String.init) ?? rel
            // Dossiers personnels et fichiers vitaux : intouchables.
            let protectedTop: Set<String> = ["Documents", "Desktop", "Downloads", "Pictures",
                                             "Movies", "Music", "Public", ".ssh", ".gnupg", ".Trash"]
            if protectedTop.contains(top) { return false }
            let protectedFiles: Set<String> = [".zshrc", ".zprofile", ".zshenv", ".zsh_history",
                                               ".bashrc", ".bash_profile", ".bash_history", ".profile",
                                               ".gitconfig", ".CFUserTextEncoding"]
            if protectedFiles.contains(rel) { return false }
            // Données irremplaçables dans ~/Library.
            let protectedLibrary = ["Library/Keychains", "Library/Mobile Documents",
                                    "Library/CloudStorage", "Library/Photos Library.photoslibrary",
                                    "Library/Mail", "Library/Messages", "Library/Safari",
                                    "Library/Accounts", "Library/Calendars", "Library/Contacts",
                                    "Library/Reminders", "Library/Notes"]
            for p in protectedLibrary where rel == p || rel.hasPrefix(p + "/") { return false }
            return true
        }

        // Hors du dossier personnel : uniquement les zones d'installation connues.
        let allowedSystem = ["/Applications/", "/Library/Application Support/", "/Library/Caches/",
                             "/Library/Preferences/", "/Library/LaunchAgents/", "/Library/LaunchDaemons/",
                             "/Library/PrivilegedHelperTools/", "/Library/Logs/",
                             "/usr/local/", "/opt/homebrew/", "/opt/"]
        for a in allowedSystem where std.hasPrefix(a) && std.count > a.count { return true }

        // Dossier d'éditeur posé directement dans /Library (/Library/Parallels…) :
        // admis, sauf les dossiers structurants de macOS listés ci-dessous. Un seul
        // niveau : /Library/<dossier>, jamais plus profond par cette voie.
        if std.hasPrefix("/Library/") {
            let rel = String(std.dropFirst("/Library/".count))
            if !rel.isEmpty, !rel.contains("/"), !librarySystemFolders.contains(rel) { return true }
        }
        return false
    }

    /// Racines système dont le CONTENU (jamais la racine elle-même) peut être
    /// supprimé par le helper privilégié `--clean-system`. Liste blanche stricte,
    /// compilée dans le binaire : même exécuté en root via sudo, `--clean-system`
    /// ne peut toucher QUE ce qui est ci-dessous. Toute autre cible est refusée.
    /// Chaque zone est listée sous ses deux orthographes : la forme `/private/…`
    /// et la forme firmlink `/var`·`/tmp`. `standardizingPath` (utilisé plus bas)
    /// retire le préfixe `/private` quand le chemin existe, donc les deux doivent
    /// figurer pour que la correspondance tienne dans tous les cas.
    static let systemCleanRoots: [String] = [
        "/Library/Caches", "/Library/Logs/DiagnosticReports", "/Library/Updates",
        "/private/var/log", "/var/log",
        "/private/var/db/diagnostics", "/var/db/diagnostics",
        "/private/var/db/DiagnosticPipeline", "/var/db/DiagnosticPipeline",
        "/private/var/db/powerlog", "/var/db/powerlog",
        "/private/tmp", "/tmp",
        "/private/var/tmp", "/var/tmp",
    ]

    /// Langues toujours conservées lors du nettoyage des .lproj (jamais supprimées) :
    /// français, anglais et Base sous toutes leurs variantes courantes.
    static let keptLanguages: Set<String> = ["base", "en", "en_us", "en_gb", "english",
                                             "fr", "fr_fr", "fr_ca", "french"]

    /// Autorise la suppression d'un dossier de langue `.lproj` : uniquement à
    /// l'intérieur de Contents/Resources d'un bundle .app installé dans Applications,
    /// jamais MacTuner, et jamais une langue conservée. Liste blanche stricte.
    static func isLanguageDeletable(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("..") else { return false }
        let std = (path as NSString).standardizingPath
        guard std.hasSuffix(".lproj"), std.contains(".app/Contents/Resources/") else { return false }
        let home = NSHomeDirectory()
        guard std.hasPrefix("/Applications/") || std.hasPrefix(home + "/Applications/") else { return false }
        if std.contains("/MacTuner.app/") { return false }
        let name = ((std as NSString).lastPathComponent as NSString)
            .deletingPathExtension.lowercased()
        return !keptLanguages.contains(name)
    }

    /// Autorise la suppression système d'un chemin : il doit être STRICTEMENT à
    /// l'intérieur d'une racine autorisée (jamais la racine elle-même). Les
    /// corbeilles de volumes externes (/Volumes/<x>/.Trashes) sont admises à part.
    static func isSystemDeletable(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("..") else { return false }
        let std = (path as NSString).standardizingPath
        // Zones absolument interdites, même en root.
        for d in ["/System", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec",
                  "/bin", "/sbin", "/etc"] where std == d || std.hasPrefix(d + "/") { return false }
        for root in systemCleanRoots where std.hasPrefix(root + "/") && std.count > root.count + 1 {
            return true
        }
        // Corbeilles de volumes externes montés.
        if std.hasPrefix("/Volumes/"), std.contains("/.Trashes/") { return true }
        return false
    }
}
