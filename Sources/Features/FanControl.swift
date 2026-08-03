//
//  FanControl.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Contrôle ventilateur (écriture SMC en root)

enum FanControl {
    static let daemonPath = "/Library/LaunchDaemons/com.mactuner.fan.plist"
    static let daemonLabel = "com.mactuner.fan"

    // MARK: État voulu par l'utilisateur (persisté)

    /// Le SMC ne conserve PAS le mode forcé : au redémarrage (et souvent au réveil),
    /// le gestionnaire thermique reprend la main. On mémorise donc l'intention de
    /// l'utilisateur pour la ré-appliquer, au lieu de lui demander de tout refaire.
    private static let manualKey = "fanManualDesired"
    private static let rpmKey = "fanCustomRPM"

    static var desiredManual: Bool {
        get { UserDefaults.standard.bool(forKey: manualKey) }
        set { UserDefaults.standard.set(newValue, forKey: manualKey) }
    }
    static var desiredRPM: Double {
        get { UserDefaults.standard.double(forKey: rpmKey) }
        set { UserDefaults.standard.set(newValue, forKey: rpmKey) }
    }
    static func forgetDesired() {
        UserDefaults.standard.removeObject(forKey: manualKey)
        UserDefaults.standard.removeObject(forKey: rpmKey)
    }

    /// Ré-applique le réglage voulu s'il ne l'est plus réellement (retour de veille,
    /// redémarrage, reprise du gestionnaire thermique). Silencieux : n'agit que si
    /// l'autorisation persistante est en place, pour ne jamais surgir une invite de
    /// mot de passe au lancement ou au réveil.
    /// Renvoie true si un réglage a effectivement été renvoyé au SMC.
    @discardableResult
    static func restoreDesiredIfNeeded() -> Bool {
        guard desiredManual, desiredRPM > 0, authInstalled,
              SysCompat.fanControlAllowed, SMC.fanCount() > 0 else { return false }
        // Déjà en mode forcé à la bonne consigne : rien à faire.
        if SMC.fanForced(0), let tg = SMC.fanTarget(0),
           abs(Double(tg) - desiredRPM) < 50 { return false }
        apply(index: 0, mode: 1, rpm: Float(desiredRPM))
        return true
    }

    private static var binaryPath: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    // Autorisation persistante : une règle sudoers limitée au binaire MacTuner,
    // pour ne PAS redemander le mot de passe à chaque changement de vitesse.
    static let authPath = "/etc/sudoers.d/mactuner-fan"
    static var authInstalled: Bool { FileManager.default.fileExists(atPath: authPath) }

    /// Installe l'autorisation persistante (un seul mot de passe), validée par visudo.
    static func installAuth() {
        let user = NSUserName()
        let line = "\(user) ALL=(root) NOPASSWD: \(binaryPath)"
        // Pas de guillemets doubles : la commande est déjà encapsulée dans une chaîne
        // AppleScript entre guillemets doubles par Shell.admin.
        let cmd = "t=$(mktemp) && echo '\(line)' > $t && chmod 440 $t"
            + " && /usr/sbin/visudo -c -f $t && mv $t \(authPath) || rm -f $t"
        Shell.admin(cmd)
    }
    static func removeAuth() { Shell.admin("rm -f \(authPath)") }

    /// Applique un réglage. Si l'autorisation persistante est en place, écrit sans
    /// mot de passe (sudo -n) ; sinon, invite classique.
    static func apply(index: Int, mode: UInt8, rpm: Float) {
        let args = "--smc-fan \(index) \(mode) \(Int(rpm))"
        if authInstalled {
            // La règle sudoers peut viser un AUTRE exemplaire du binaire (ex. une
            // copie dans /Applications alors que celle-ci tourne ailleurs) : dans ce
            // cas sudo -n échoue. On le détecte et on retombe sur l'invite admin au
            // lieu d'échouer en silence, puis on répare la règle pour ce binaire.
            let r = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(binaryPath)' \(args)"])
            if r.ok { return }
            installAuth()   // un seul mot de passe : la règle vise désormais ce binaire
            let retry = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(binaryPath)' \(args)"])
            if retry.ok { return }
        }
        Shell.admin("'\(binaryPath)' \(args)")
    }

    static func setAuto(index: Int) { apply(index: index, mode: 0, rpm: 0) }

    // MARK: Réglage rejoué au démarrage (LaunchDaemon)

    static var startupEnabled: Bool { FileManager.default.fileExists(atPath: daemonPath) }

    /// Contenu du LaunchDaemon. `RunAtLoad` seul ne suffisait pas : appliquée très
    /// tôt au boot, la consigne est reprise par le gestionnaire thermique dès que
    /// macOS finit de démarrer, et le ventilateur repassait en automatique.
    /// `StartInterval` la ré-affirme toutes les 5 minutes.
    private static func daemonPlist(index: Int, rpm: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(daemonLabel)</string>
        <key>ProgramArguments</key><array>
        <string>\(binaryPath)</string><string>--smc-fan</string>
        <string>\(index)</string><string>1</string><string>\(rpm)</string>
        </array>
        <key>RunAtLoad</key><true/>
        <key>StartInterval</key><integer>300</integer>
        </dict></plist>
        """
    }

    /// EXÉCUTÉ EN ROOT par le mode helper `--fan-daemon` : écrit (ou retire) le
    /// LaunchDaemon et le (re)charge, pour que le réglage vaille sans redémarrer.
    /// Passer par le helper permet de régénérer le démon à chaque changement de
    /// vitesse sans redemander le mot de passe (règle sudoers déjà en place).
    static func runDaemonHelper(index: Int, rpm: Int, install: Bool) {
        let fm = FileManager.default
        Shell.run("/bin/launchctl", ["bootout", "system/\(daemonLabel)"])
        guard install else {
            try? fm.removeItem(atPath: daemonPath)
            return
        }
        try? fm.createDirectory(atPath: "/Library/LaunchDaemons", withIntermediateDirectories: true)
        guard (try? daemonPlist(index: index, rpm: rpm)
            .write(toFile: daemonPath, atomically: true, encoding: .utf8)) != nil else { return }
        try? fm.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0,
                               .posixPermissions: 0o644], ofItemAtPath: daemonPath)
        Shell.run("/bin/launchctl", ["bootstrap", "system", daemonPath])
    }

    /// Côté interface : demande au helper root d'écrire ou retirer le démon.
    /// Sans mot de passe si la règle sudoers est en place, invite admin sinon.
    private static func invokeDaemonHelper(index: Int, rpm: Int, install: Bool) {
        let args = "--fan-daemon \(index) \(rpm) \(install ? 1 : 0)"
        if authInstalled {
            let r = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(binaryPath)' \(args)"])
            if r.ok { return }
        }
        Shell.admin("'\(binaryPath)' \(args)")
    }

    static func enableStartup(index: Int, rpm: Float) {
        invokeDaemonHelper(index: index, rpm: Int(rpm), install: true)
    }

    /// Régénère le démon avec une nouvelle vitesse. Sans effet (et sans invite) si le
    /// réglage de démarrage n'est pas actif : sinon, le démon continuerait d'appliquer
    /// l'ANCIENNE consigne au prochain redémarrage.
    static func refreshStartup(index: Int, rpm: Float) {
        guard startupEnabled else { return }
        enableStartup(index: index, rpm: rpm)
    }

    static func disableStartup() {
        invokeDaemonHelper(index: 0, rpm: 0, install: false)
    }
}
