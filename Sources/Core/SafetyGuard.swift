//
//  SafetyGuard.swift — MacTuner
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

        // Une app Apple intégrée n'est jamais supprimable.
        if std.hasSuffix(".app"),
           UninstallEngine.bundleID(ofApp: std).hasPrefix("com.apple.") { return false }

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
        return false
    }
}

