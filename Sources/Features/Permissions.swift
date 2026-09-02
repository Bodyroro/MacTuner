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
        // 1. Restauration exhaustive : même routine que la réinitialisation, pour
        // qu'aucun cas ne soit couvert d'un côté et oublié de l'autre. Elle remet
        // agents, démons système, clés `defaults` et commandes admin dans leur état
        // d'origine, retire les LaunchAgents de MacTuner et rend la main au
        // gestionnaire thermique.
        if restoreFeatures {
            Restore.toDefaults(removeAuthorizations: false)
        } else {
            // Sans restauration des réglages, on retire tout de même ce qui ne
            // survivrait à l'app que sous forme de processus orphelins.
            DesiredState.clear()
            ReapplyAgent.remove()
            KeepAwakeAgent.remove()
            Scheduler.disable()
            if SMC.fanCount() > 0 { FanControl.setAuto(index: 0) }
        }

        // 2. Règles sudoers, LaunchDaemon du ventilateur et sauvegardes : en dernier,
        // pour que les restaurations privilégiées ci-dessus aient encore leur
        // passe-droit. Une seule invite administrateur.
        Restore.revokeAuthorizations()

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
    ///  • la règle des modes helper de MacTuner, restreinte aux formes d'arguments
    ///    autorisées (voir `helperCommandForms`).
    /// Chaque fichier est validé par visudo avant d'être mis en place, un fichier
    /// invalide n'est jamais installé. Refuse si l'emplacement du binaire ne se
    /// prête pas à une autorisation root durable (voir `binaryTrustIssue`).
    static func installPersistentAdmin() -> Bool {
        guard binaryTrustIssue() == nil else { return false }
        let user = NSUserName()
        let cmdLine = "\(user) ALL=(root) NOPASSWD: \(sudoersCommands)"
        let cleanLine = "\(user) ALL=(root) NOPASSWD: \(helperCommandForms)"
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

    /// Échappe un chemin pour sudoers. Un espace, une virgule, un `:`, un `=`, un `\`
    /// ou un `#` non échappés font rejeter le fichier par visudo : la règle n'est alors
    /// jamais installée et l'app redemande le mot de passe sans jamais dire pourquoi.
    /// Le cas est réel dès que l'app vit dans un dossier contenant un espace.
    static func sudoersEscaped(_ path: String) -> String {
        var out = ""
        for ch in path {
            if " ,:=\\#".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func hasCleanAuth() -> Bool { FileManager.default.fileExists(atPath: cleanAuthPath) }

    /// Formes de commande autorisées sans mot de passe, argument de tête compris.
    ///
    /// La règle visait auparavant le binaire NU : `sudo <MacTuner>` acceptait alors
    /// n'importe quel argument — présent ou futur — et même aucun, c'est-à-dire
    /// l'application entière lancée en root. Chaque mode helper est désormais
    /// énuméré ; tout ce qui n'est pas listé ici repasse par l'invite de mot de passe.
    static var helperCommandForms: String {
        let b = sudoersEscaped(cleanBinaryPath)
        return ["\(b) --clean-system *",
                "\(b) --launchd-system *"].joined(separator: ", ")
    }

    /// Pourquoi ce binaire ne doit PAS recevoir d'autorisation root sans mot de passe.
    /// Renvoie nil quand tout va bien.
    ///
    /// Une règle NOPASSWD sur un exécutable que l'utilisateur peut réécrire équivaut
    /// à donner root à tout ce qui tourne sous son compte : il suffit de remplacer le
    /// binaire. C'est le cas de tout ce qui vit dans le dossier personnel —
    /// Téléchargements en particulier. On refuse alors la règle plutôt que de la
    /// poser en silence ; l'app continue de fonctionner, avec une invite de mot de
    /// passe pour les actions privilégiées.
    static func binaryTrustIssue() -> String? {
        let path = cleanBinaryPath
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/") {
            return T("set.auth.trust.home")
        }
        // Écriture ouverte au groupe ou à tous : même conclusion.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let perms = attrs[.posixPermissions] as? NSNumber,
           perms.uint16Value & 0o022 != 0 {
            return T("set.auth.trust.perms")
        }
        return nil
    }

    /// Installe la règle (une seule invite), validée par visudo avant mise en place.
    @discardableResult
    static func installCleanAuth() -> Bool {
        guard binaryTrustIssue() == nil else { return false }
        let user = NSUserName()
        let line = "\(user) ALL=(root) NOPASSWD: \(helperCommandForms)"
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
    /// Raison d'un refus d'autorisation durable (emplacement du binaire), sinon nil.
    @Published var trustIssue: String?

    init() {
        fda = Permissions.hasFullDiskAccess()
        adminPersistent = Permissions.hasPersistentAdmin()
        trustIssue = Permissions.binaryTrustIssue()
        showSheet = !UserDefaults.standard.bool(forKey: "onboardingDone")
    }

    func recheckFDA() {
        fda = Permissions.hasFullDiskAccess()
        adminPersistent = Permissions.hasPersistentAdmin()
        trustIssue = Permissions.binaryTrustIssue()
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
