//
//  FanControl.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Contrôle ventilateur (écriture SMC en root)

enum FanControl {
    static let daemonPath = "/Library/LaunchDaemons/com.mactuner.fan.plist"

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
            // lieu d'échouer en silence — puis on répare la règle pour ce binaire.
            let r = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(binaryPath)' \(args)"])
            if r.ok { return }
            installAuth()   // un seul mot de passe : la règle vise désormais ce binaire
            let retry = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(binaryPath)' \(args)"])
            if retry.ok { return }
        }
        Shell.admin("'\(binaryPath)' \(args)")
    }

    static func setAuto(index: Int) { apply(index: index, mode: 0, rpm: 0) }

    static var startupEnabled: Bool { FileManager.default.fileExists(atPath: daemonPath) }

    /// Installe un LaunchDaemon (root, RunAtLoad) qui réapplique la vitesse au démarrage.
    static func enableStartup(index: Int, rpm: Float) {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>com.mactuner.fan</string>
        <key>ProgramArguments</key><array>
        <string>\(binaryPath)</string><string>--smc-fan</string>
        <string>\(index)</string><string>1</string><string>\(Int(rpm))</string>
        </array>
        <key>RunAtLoad</key><true/>
        </dict></plist>
        """
        let tmp = NSTemporaryDirectory() + "com.mactuner.fan.plist"
        try? plist.write(toFile: tmp, atomically: true, encoding: .utf8)
        Shell.admin("mkdir -p /Library/LaunchDaemons && cp '\(tmp)' \(daemonPath) && chown root:wheel \(daemonPath) && chmod 644 \(daemonPath)")
    }

    static func disableStartup() {
        Shell.admin("rm -f \(daemonPath)")
    }
}

