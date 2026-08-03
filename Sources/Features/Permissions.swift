//
//  Permissions.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Auto-désinstallation de MacTuner

/// Retire toute trace de MacTuner : données locales, règles admin, démon, puis l'app.
enum SelfUninstall {
    private static let bundleID = "local.rodolphe.mactuner"

    static func run(restoreFeatures: Bool) {
        // 1. Réactiver éventuellement les fonctionnalités désactivées par l'utilisateur.
        if restoreFeatures {
            for tweak in allTweaks where !tweak.needsAdmin {
                Engine.apply(tweak, disable: false)
            }
        }
        // 2. Remettre le ventilateur en automatique.
        if SMC.fanCount() > 0 { FanControl.setAuto(index: 0) }

        // 2 bis. Retirer l'agent de ré-application au login, l'état voulu et le
        // nettoyage planifié.
        DesiredState.clear()
        ReapplyAgent.remove()
        Scheduler.disable()

        // 3. Retirer règles sudoers + démon (une seule invite admin).
        // Le démon est d'abord déchargé : retirer seulement son fichier le laisserait
        // tourner (et ré-affirmer la vitesse) jusqu'au prochain redémarrage.
        Shell.admin("(launchctl bootout system/\(FanControl.daemonLabel) 2>/dev/null; true); "
            + "rm -f /etc/sudoers.d/mactuner /etc/sudoers.d/mactuner-fan "
            + "/etc/sudoers.d/mactuner-clean \(FanControl.daemonPath) 2>/dev/null; true")

        // 4. Effacer toutes les données locales.
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        let h = NSHomeDirectory()
        let residues = [
            "\(h)/Library/Preferences/\(bundleID).plist",
            "\(h)/Library/Caches/\(bundleID)",
            "\(h)/Library/Saved Application State/\(bundleID).savedState",
            "\(h)/Library/HTTPStorages/\(bundleID)",
            "\(h)/Library/Application Support/MacTuner",
        ]
        for p in residues { try? FileManager.default.removeItem(atPath: p) }

        // 5. Envoyer l'app à la Corbeille, puis quitter.
        if let bundle = Bundle.main.bundleURL as URL? {
            try? FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Autorisations

enum Permissions {
    /// Détecte l'Accès complet au disque en tentant de lire un fichier protégé par TCC.
    static func hasFullDiskAccess() -> Bool {
        let candidates = [
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
        ]
        for path in candidates {
            if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    static func openFDASettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Déclenche l'invite de mot de passe admin ; true si l'utilisateur s'authentifie.
    static func testAdmin() -> Bool {
        let out = Shell.run("/usr/bin/osascript",
                            ["-e", "do shell script \"whoami\" with administrator privileges"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines) == "root"
    }

    static let sudoersPath = "/etc/sudoers.d/mactuner"
    static let sudoersCommands = "/usr/bin/mdutil, /usr/bin/pmset, /usr/sbin/nvram"

    /// True si l'autorisation admin durable de MacTuner est complètement en place :
    /// la règle des commandes système ET la règle du nettoyage système (helper).
    /// Les deux sont posées ensemble, donc l'état est cohérent.
    static func hasPersistentAdmin() -> Bool {
        hasCleanAuth() && Shell.run("/usr/bin/sudo", ["-n", "-l"]).contains("/usr/bin/mdutil")
    }

    /// Installe l'autorisation admin durable EN UNE SEULE invite de mot de passe :
    ///  • la règle limitée aux 3 commandes système (mdutil, pmset, nvram) ;
    ///  • la règle du nettoyage système (le binaire MacTuner en mode `--clean-system`).
    /// Chaque fichier est validé par visudo avant d'être mis en place, un fichier
    /// invalide n'est jamais installé. Résultat : plus aucune invite ensuite, ni pour
    /// les réglages système, ni pour le nettoyage des zones système.
    static func installPersistentAdmin() -> Bool {
        let user = NSUserName()
        let cmdLine = "\(user) ALL=(root) NOPASSWD: \(sudoersCommands)"
        let cleanLine = "\(user) ALL=(root) NOPASSWD: \(cleanBinaryPath)"
        let cmd = "t1=$(mktemp) && echo '\(cmdLine)' > $t1 && chmod 440 $t1"
            + " && /usr/sbin/visudo -c -f $t1 && mv $t1 \(sudoersPath) || rm -f $t1; "
            + "t2=$(mktemp) && echo '\(cleanLine)' > $t2 && chmod 440 $t2"
            + " && /usr/sbin/visudo -c -f $t2 && mv $t2 \(cleanAuthPath) || rm -f $t2"
        Shell.admin(cmd)
        return hasPersistentAdmin()
    }

    static func revokePersistentAdmin() -> Bool {
        Shell.admin("rm -f \(sudoersPath) \(cleanAuthPath)")
        return !hasPersistentAdmin()
    }

    // MARK: Autorisation du nettoyage système

    /// Règle sudoers dédiée au nettoyage système : autorise le binaire MacTuner à
    /// être relancé en root (mode `--clean-system`) sans redemander le mot de passe.
    /// La sécurité tient à la liste blanche compilée (SafetyGuard.isSystemDeletable),
    /// pas à la commande sudo : le binaire ne peut vider que les racines système
    /// autorisées, jamais un chemin arbitraire.
    static let cleanAuthPath = "/etc/sudoers.d/mactuner-clean"
    static var cleanBinaryPath: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    static func hasCleanAuth() -> Bool { FileManager.default.fileExists(atPath: cleanAuthPath) }

    /// Installe la règle (une seule invite), validée par visudo avant mise en place.
    @discardableResult
    static func installCleanAuth() -> Bool {
        let user = NSUserName()
        let line = "\(user) ALL=(root) NOPASSWD: \(cleanBinaryPath)"
        let cmd = "t=$(mktemp) && echo '\(line)' > $t && chmod 440 $t"
            + " && /usr/sbin/visudo -c -f $t && mv $t \(cleanAuthPath) || rm -f $t"
        Shell.admin(cmd)
        return hasCleanAuth()
    }

    static func revokeCleanAuth() -> Bool {
        Shell.admin("rm -f \(cleanAuthPath)")
        return !hasCleanAuth()
    }

    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

@MainActor
final class PermissionsModel: ObservableObject {
    @Published var showSheet: Bool
    @Published var fda: Bool
    @Published var adminOK = false
    @Published var adminPersistent: Bool
    @Published var testingAdmin = false

    init() {
        fda = Permissions.hasFullDiskAccess()
        adminPersistent = Permissions.hasPersistentAdmin()
        showSheet = !UserDefaults.standard.bool(forKey: "onboardingDone")
    }

    func recheckFDA() {
        fda = Permissions.hasFullDiskAccess()
        adminPersistent = Permissions.hasPersistentAdmin()
    }

    func testAdmin() {
        testingAdmin = true
        Task.detached(priority: .userInitiated) {
            let ok = Permissions.testAdmin()
            await MainActor.run {
                self.adminOK = ok
                self.testingAdmin = false
            }
        }
    }

    func installPersistent() {
        testingAdmin = true
        Task.detached(priority: .userInitiated) {
            let ok = Permissions.installPersistentAdmin()
            await MainActor.run {
                self.adminPersistent = ok
                if ok { self.adminOK = true }
                self.testingAdmin = false
            }
        }
    }

    func revokePersistent() {
        testingAdmin = true
        Task.detached(priority: .userInitiated) {
            let gone = Permissions.revokePersistentAdmin()
            await MainActor.run {
                self.adminPersistent = !gone
                self.testingAdmin = false
            }
        }
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        showSheet = false
    }
}
