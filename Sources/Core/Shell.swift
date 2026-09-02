//
//  Shell.swift · MacTuner
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
        // Les deux tuyaux sont vidés EN PARALLÈLE. Les lire l'un après l'autre bloque
        // dès qu'une commande bavarde remplit les 64 Ko du tuyau non lu (system_profiler,
        // launchctl print) : le processus attend qu'on lise, on attend qu'il finisse.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
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

    /// Échappe une chaîne destinée à être placée entre guillemets DOUBLES dans un
    /// script shell. Sans ça, un `$`, un backtick ou un guillemet dans le chemin de
    /// l'app se ferait interpréter au lieu d'être lu littéralement.
    static func shellDoubleQuoted(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch == "\\" || ch == "\"" || ch == "$" || ch == "`" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Échappe une chaîne pour l'insérer dans une chaîne AppleScript entre guillemets
    /// doubles. Sans ça, un chemin contenant `"` ou `\` casse le script (ou pire,
    /// injecte du code) : `do shell script "…"` est du texte AppleScript, pas du shell.
    static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func admin(_ cmd: String) {
        run("/usr/bin/osascript",
            ["-e", "do shell script \"\(appleScriptEscaped(cmd))\" with administrator privileges"])
    }

    /// Exécute une commande admin : sans mot de passe si la règle sudoers durable
    /// de MacTuner l'autorise, sinon via l'invite de mot de passe macOS.
    ///
    /// La règle NOPASSWD ne couvre que `mdutil`, `pmset` et `nvram`. Toute autre
    /// commande fait échouer `sudo -n` — silencieusement, puisque rien ne lisait le
    /// code de sortie : le réglage n'était pas appliqué et l'interface l'annonçait
    /// quand même. On vérifie donc le résultat et on retombe sur l'invite classique.
    @discardableResult
    static func adminRun(_ cmd: String) -> Bool {
        if Permissions.hasPersistentAdmin() {
            let r = runResult("/bin/sh", ["-c", "/usr/bin/sudo -n \(cmd)"])
            if r.ok { return true }
        }
        admin(cmd)
        return true
    }
}

/// État de System Integrity Protection.
///
/// Ce que SIP change RÉELLEMENT pour MacTuner (vérifié sur macOS 26 et 27) :
///  • `launchctl disable gui/<uid>/<label>` réussit (code 0) même SIP activé. Le
///    drapeau est écrit dans `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist`,
///    fichier appartenant à root : il SURVIT au redémarrage et launchd refuse de
///    charger l'agent aux sessions suivantes. La désactivation est donc permanente.
///  • `launchctl bootout gui/<uid>/<label>` est refusé (code 150) sur les agents
///    Apple tant que SIP est activé : le processus DÉJÀ LANCÉ continue de tourner
///    jusqu'à la fermeture de session ou au redémarrage.
///
/// Conclusion : SIP activé ne bloque pas la désactivation, il en retarde l'effet
/// au prochain redémarrage. SIP désactivé rend l'effet immédiat.
enum SIP {
    /// `csrutil status` répond « enabled », « disabled », ou
    /// « unknown (Custom Configuration) » quand certaines protections seulement sont
    /// levées. Par prudence, seul un « disabled » franc compte comme désactivé :
    /// une configuration personnalisée est traitée comme activée.
    static let enabled: Bool = {
        let s = Shell.run("/usr/bin/csrutil", ["status"]).lowercased()
        if s.contains("status: disabled") { return false }
        return true
    }()

    /// Vrai si SIP n'est que partiellement levé (configuration personnalisée) :
    /// `bootout` peut passer ou non, on le vérifie au cas par cas.
    static let custom: Bool = {
        Shell.run("/usr/bin/csrutil", ["status"]).lowercased().contains("custom configuration")
    }()
}

/// Liste blanche COMPILÉE des démons système que MacTuner accepte de désactiver.
///
/// Le mode helper `--launchd-system` tourne en root : sans cette liste, une règle
/// sudoers permettrait de désactiver n'importe quel démon de macOS, y compris ceux
/// dont dépend le démarrage. Le helper refuse tout label absent d'ici, quel que
/// soit l'appelant. N'y figurent que des démons de télémétrie et de rapport
/// d'incident, dont l'arrêt ne retire aucune fonction au Mac.
enum SystemDaemons {
    static let allowed: Set<String> = [
        // Siri : détection « Dis Siri » hors session (label à souligné).
        "com.apple.corespeechd_system",
        // Apple Intelligence : gestionnaire des modèles génératifs.
        "com.apple.modelmanagerd",
        // Suggestions proactives : moteur d'apprentissage CoreDuet.
        "com.apple.coreduetd",
        // Télémétrie : collecte, agrégation et envoi à Apple.
        "com.apple.analyticsd",
        "com.apple.osanalytics.osanalyticshelper",
        "com.apple.rtcreportingd",
        "com.apple.cloudtelemetryd",
        "com.apple.wifianalyticsd",
        "com.apple.audioanalyticsd",
        "com.apple.ecosystemanalyticsd",
        "com.apple.libsqlite3.dbtelemetryd",
        "com.apple.usbctelemetryd",
        "com.apple.memoryanalyticsd",
        // Rapports d'incident : écriture et transmission.
        "com.apple.SubmitDiagInfo",
        "com.apple.spindump",
        "com.apple.tailspind",
        "com.apple.ReportCrash.Root",
        "com.apple.diagnosticservicesd",
        "com.apple.CrashReporterSupportHelper",
        "com.apple.ReportMemoryException",
        "com.apple.diagnosticd",
        // Continuité : transport AirPlay et lien de proximité Rapport.
        "com.apple.AirPlayXPCHelper",
        "com.apple.rapportd",
    ]

    static func isAllowed(_ label: String) -> Bool { allowed.contains(label) }
}

enum LaunchCtl {
    static var domain: String { "gui/\(getuid())" }
    /// Domaine des démons : root, hors session, chargé avant l'ouverture de session.
    static let systemDomain = "system"

    /// Résultat d'une désactivation d'agent, en deux temps distincts.
    struct Outcome {
        /// Le drapeau « disabled » est posé : l'agent ne sera plus chargé, y compris
        /// après un redémarrage. C'est ça, la permanence.
        let flagged: Bool
        /// Le processus en cours a réellement été terminé (`bootout` accepté).
        /// Faux sous SIP : l'agent tourne jusqu'au prochain redémarrage.
        let stopped: Bool
        /// Tout est effectif tout de suite.
        var immediate: Bool { flagged && stopped }
    }

    /// Répertoires standard des LaunchAgents, dans l'ordre où launchd les consulte.
    private static let agentDirs = [
        NSHomeDirectory() + "/Library/LaunchAgents",
        "/Library/LaunchAgents",
        "/System/Library/LaunchAgents",
    ]

    /// Chemin du plist d'un agent. Le nom de fichier vaut presque toujours le label,
    /// mais pas toujours : on retombe sur une recherche par label si besoin, au lieu
    /// de supposer `/System/Library/LaunchAgents/<label>.plist` et d'échouer en silence.
    static func plistPath(for label: String) -> String? {
        let fm = FileManager.default
        for dir in agentDirs {
            let direct = "\(dir)/\(label).plist"
            if fm.fileExists(atPath: direct) { return direct }
        }
        for dir in agentDirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".plist") {
                let path = "\(dir)/\(f)"
                let lbl = Shell.run("/usr/libexec/PlistBuddy", ["-c", "print Label", path])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if lbl == label { return path }
            }
        }
        return nil
    }

    /// Services marqués « disabled » dans un domaine. `print-disabled` est lisible
    /// sans privilège, y compris pour le domaine `system`.
    static func disabledServices(in dom: String) -> Set<String> {
        let output = Shell.run("/bin/launchctl", ["print-disabled", dom])
        var result = Set<String>()
        for line in output.split(separator: "\n") where line.contains("=> disabled") {
            if let start = line.firstIndex(of: "\""),
               let end = line[line.index(after: start)...].firstIndex(of: "\"") {
                result.insert(String(line[line.index(after: start)..<end]))
            }
        }
        return result
    }

    static func disabledServices() -> Set<String> { disabledServices(in: domain) }
    static func disabledSystemServices() -> Set<String> { disabledServices(in: systemDomain) }

    /// PID d'un démon système s'il tourne (lecture seule, sans privilège).
    static func systemRunningPID(_ label: String) -> Int32? {
        let out = Shell.run("/bin/launchctl", ["print", "\(systemDomain)/\(label)"])
        for line in out.split(separator: "\n") where line.contains("pid = ") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = Int32(trimmed.replacingOccurrences(of: "pid = ", with: "")) { return pid }
        }
        return nil
    }

    /// EXÉCUTÉ EN ROOT (mode helper `--launchd-system`). Applique le drapeau dans le
    /// domaine `system`, puis tente le `bootout` — refusé sous SIP comme en `gui`.
    /// La liste blanche est revérifiée ici : c'est le dernier rempart, celui qui
    /// compte, puisque ce code tourne avec les privilèges root. Un label refusé
    /// n'interrompt pas les autres.
    static func applySystemDaemons(_ labels: [String], disable: Bool) {
        for label in labels where SystemDaemons.isAllowed(label) {
            if disable {
                Shell.runResult("/bin/launchctl", ["disable", "\(systemDomain)/\(label)"])
                Shell.runResult("/bin/launchctl", ["bootout", "\(systemDomain)/\(label)"])
            } else {
                Shell.runResult("/bin/launchctl", ["enable", "\(systemDomain)/\(label)"])
                // Le nom de fichier ne vaut pas le label (corespeechd_system vit dans
                // corespeechd.system.plist) : on cherche par label si besoin.
                if let plist = daemonPlistPath(for: label) {
                    Shell.runResult("/bin/launchctl", ["bootstrap", systemDomain, plist])
                }
            }
        }
    }

    /// Chemin du plist d'un démon système, par nom de fichier puis par label.
    static func daemonPlistPath(for label: String) -> String? {
        let dir = "/System/Library/LaunchDaemons"
        let direct = "\(dir)/\(label).plist"
        if FileManager.default.fileExists(atPath: direct) { return direct }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        for f in files where f.hasSuffix(".plist") {
            let path = "\(dir)/\(f)"
            let lbl = Shell.run("/usr/libexec/PlistBuddy", ["-c", "print Label", path])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if lbl == label { return path }
        }
        return nil
    }

    /// Côté interface : demande au helper root d'agir sur PLUSIEURS démons système
    /// EN UN SEUL appel. Le faire label par label déclenchait autant d'invites de
    /// mot de passe qu'il y a de démons — dix pour la seule télémétrie.
    /// Sans mot de passe si la règle sudoers restreinte est en place, invite sinon.
    @discardableResult
    static func setSystemDaemons(_ labels: [String], disabled: Bool) -> Outcome {
        let valid = labels.filter(SystemDaemons.isAllowed)
        guard !valid.isEmpty else { return Outcome(flagged: false, stopped: false) }
        let bin = Permissions.cleanBinaryPath
        let args = "--launchd-system \(disabled ? "disable" : "enable") "
            + valid.map { "'\($0)'" }.joined(separator: " ")
        var done = false
        if Permissions.hasCleanAuth() {
            done = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(bin)' \(args)"]).ok
        }
        if !done { Shell.admin("'\(bin)' \(args)") }
        let flags = disabledSystemServices()
        let allFlagged = valid.allSatisfy { disabled ? flags.contains($0) : !flags.contains($0) }
        let allStopped = valid.allSatisfy { systemRunningPID($0) == nil }
        return Outcome(flagged: allFlagged, stopped: allStopped)
    }

    /// Retire les entrées inertes de la base d'overrides launchd.
    ///
    /// EXÉCUTÉ EN ROOT (mode helper `--prune-overrides`). Une entrée valant `false`
    /// signifie « activé », c'est-à-dire exactement le comportement par défaut :
    /// la supprimer ne change donc STRICTEMENT rien au système, elle ne fait que
    /// nettoyer des résidus (souvent des noms qui ne sont même pas des services).
    /// Les entrées `true`, elles — vos désactivations — ne sont jamais touchées.
    /// Renvoie le nombre d'entrées retirées.
    @discardableResult
    static func pruneInertOverrides() -> Int {
        var removed = 0
        let dir = "/private/var/db/com.apple.xpc.launchd"
        for name in ["disabled.\(getuid()).plist", "disabled.plist"] {
            let path = "\(dir)/\(name)"
            guard let dict = NSMutableDictionary(contentsOfFile: path) else { continue }
            let inert = dict.compactMap { key, value -> String? in
                guard let k = key as? String, let b = value as? Bool, b == false else { return nil }
                return k
            }
            guard !inert.isEmpty else { continue }
            // Ce fichier est lu par launchd au démarrage : on garde une copie avant
            // d'y toucher, et on la remet si la relecture ne retrouve pas TOUTES les
            // désactivations d'origine. Un fichier tronqué réactiverait en silence
            // des services que l'utilisateur avait coupés.
            let kept = dict.compactMap { key, value -> String? in
                guard let k = key as? String, let b = value as? Bool, b else { return nil }
                return k
            }
            let backup = path + ".mactuner-backup"
            try? FileManager.default.removeItem(atPath: backup)
            try? FileManager.default.copyItem(atPath: path, toPath: backup)

            for k in inert { dict.removeObject(forKey: k) }
            guard dict.write(toFile: path, atomically: true) else { continue }
            // L'écriture atomique remplace le fichier : on lui rend son identité
            // d'origine (root:wheel 0644), sinon launchd pourrait l'ignorer au boot.
            try? FileManager.default.setAttributes(
                [.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o644],
                ofItemAtPath: path)

            let reread = NSDictionary(contentsOfFile: path) as? [String: Any]
            let survived = kept.allSatisfy { (reread?[$0] as? Bool) == true }
            if reread == nil || !survived {
                // Retour en arrière : l'original reprend sa place tel quel.
                try? FileManager.default.removeItem(atPath: path)
                try? FileManager.default.moveItem(atPath: backup, toPath: path)
                try? FileManager.default.setAttributes(
                    [.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o644],
                    ofItemAtPath: path)
                continue
            }
            try? FileManager.default.removeItem(atPath: backup)
            removed += inert.count
        }
        return removed
    }

    /// Désactive un agent, en distinguant les deux effets.
    ///
    /// `disable` pose le drapeau persistant : accepté même sous SIP, il suffit à
    /// empêcher tout chargement futur (redémarrage compris). `bootout` termine le
    /// processus en cours : refusé par SIP (code 150) sur les agents Apple.
    /// On renvoie les deux informations pour que l'interface dise la vérité au lieu
    /// d'annoncer « arrêté » alors que le processus tourne encore.
    @discardableResult
    static func disable(_ label: String) -> Outcome {
        let flag = Shell.runResult("/bin/launchctl", ["disable", "\(domain)/\(label)"])
        Shell.runResult("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        // Le drapeau est relu plutôt que déduit du code de sortie : c'est l'état réel
        // de la base d'overrides qui fait foi.
        let flagged = flag.ok || disabledServices().contains(label)
        return Outcome(flagged: flagged, stopped: Engine.runningPID(label) == nil)
    }

    @discardableResult
    static func enable(_ label: String) -> Bool {
        let r = Shell.runResult("/bin/launchctl", ["enable", "\(domain)/\(label)"])
        // Recharger tout de suite si on retrouve le plist ; sinon launchd le chargera
        // de toute façon à la prochaine ouverture de session, le drapeau étant levé.
        if let path = plistPath(for: label) {
            Shell.runResult("/bin/launchctl", ["bootstrap", domain, path])
        }
        return r.ok
    }
}
