//
//  Shell.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Exécution shell

enum Shell {
    /// Résultat complet d'une commande : sortie, erreur et code de sortie.
    /// Indispensable pour détecter les échecs silencieux (ex. `launchctl bootout`
    /// refusé par SIP avec le code 150), que `run` seul masquait.
    struct Result {
        let out: String
        let err: String
        let code: Int32
        var ok: Bool { code == 0 }
    }

    @discardableResult
    static func runResult(_ path: String, _ args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return Result(out: "", err: "\(error)", code: -1) }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(out: String(data: outData, encoding: .utf8) ?? "",
                      err: String(data: errData, encoding: .utf8) ?? "",
                      code: p.terminationStatus)
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        runResult(path, args).out
    }

    @discardableResult
    static func sh(_ cmd: String) -> String { run("/bin/sh", ["-c", cmd]) }

    static func admin(_ cmd: String) {
        run("/usr/bin/osascript", ["-e", "do shell script \"\(cmd)\" with administrator privileges"])
    }

    /// Exécute une commande admin : sans mot de passe si la règle sudoers durable
    /// de MacTuner est installée, sinon via l'invite de mot de passe macOS.
    static func adminRun(_ cmd: String) {
        if Permissions.hasPersistentAdmin() {
            sh("sudo -n \(cmd)")
        } else {
            admin(cmd)
        }
    }
}

/// État de System Integrity Protection. Décisif pour les fonctionnalités :
/// avec SIP activé, `launchctl bootout` sur un agent Apple est refusé (code 150),
/// donc les agents ne peuvent pas être réellement arrêtés — seuls les réglages
/// `defaults` et les commandes admin (mdutil, pmset, nvram) prennent effet.
/// L'état ne change qu'au redémarrage : on le mesure une seule fois.
enum SIP {
    static let enabled: Bool = {
        Shell.run("/usr/bin/csrutil", ["status"])
            .lowercased().contains("status: enabled")
    }()
}

enum LaunchCtl {
    static var domain: String { "gui/\(getuid())" }

    static func disabledServices() -> Set<String> {
        let output = Shell.run("/bin/launchctl", ["print-disabled", domain])
        var result = Set<String>()
        for line in output.split(separator: "\n") where line.contains("=> disabled") {
            if let start = line.firstIndex(of: "\""),
               let end = line[line.index(after: start)...].firstIndex(of: "\"") {
                result.insert(String(line[line.index(after: start)..<end]))
            }
        }
        return result
    }

    /// Désactive un agent et renvoie s'il est *réellement* arrêté.
    /// `disable` pose le drapeau (toujours accepté), mais `bootout` termine le
    /// processus — refusé par SIP sur les agents Apple. On ne se fie donc pas au
    /// drapeau : l'agent n'est « arrêté » que si bootout réussit ou qu'aucun
    /// processus ne tourne plus.
    @discardableResult
    static func disable(_ label: String) -> Bool {
        Shell.run("/bin/launchctl", ["disable", "\(domain)/\(label)"])
        Shell.runResult("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        return Engine.runningPID(label) == nil
    }

    static func enable(_ label: String) {
        Shell.run("/bin/launchctl", ["enable", "\(domain)/\(label)"])
        Shell.run("/bin/launchctl", ["bootstrap", domain, "/System/Library/LaunchAgents/\(label).plist"])
    }
}

