//
//  Persistence.swift — MacTuner
//
import Foundation
import Darwin

// MARK: - État voulu par l'utilisateur (persisté)

/// Mémorise ce que l'utilisateur a désactivé, indépendamment de l'état réel du
/// système. macOS ré-affirme certains agents Apple au démarrage (Siri,
/// suggestions, Astuces…) tant que la fonctionnalité reste « activée » à ses
/// yeux : cet état permet de détecter l'écart au lancement et de ré-appliquer.
enum DesiredState {
    private static let tweaksKey = "desiredDisabledTweaks"
    private static let agentsKey = "desiredDisabledAgents"

    static var disabledTweakIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: tweaksKey) ?? [])
    }

    /// Agents désactivés individuellement (sous-interrupteurs), hors fiche entière.
    static var disabledAgentLabels: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: agentsKey) ?? [])
    }

    static func setTweak(_ id: String, disabled: Bool) {
        var ids = disabledTweakIDs
        var labels = disabledAgentLabels
        if disabled { ids.insert(id) } else { ids.remove(id) }
        // La fiche couvre (ou libère) tous ses agents : plus d'entrées individuelles.
        for l in agentLabels(ofTweak: id) { labels.remove(l) }
        save(ids: ids, labels: labels)
    }

    static func setAgent(_ label: String, disabled: Bool) {
        var ids = disabledTweakIDs
        var labels = disabledAgentLabels
        if disabled {
            // Inutile de dupliquer si la fiche entière est déjà mémorisée.
            if tweak(containing: label).map({ ids.contains($0.id) }) != true {
                labels.insert(label)
            }
        } else {
            labels.remove(label)
            // Réactiver un sous-agent d'une fiche mémorisée : la fiche n'est plus
            // « toute désactivée » — on bascule sur des entrées individuelles.
            if let t = tweak(containing: label), ids.contains(t.id) {
                ids.remove(t.id)
                for l in agentLabels(ofTweak: t.id) where l != label { labels.insert(l) }
            }
        }
        save(ids: ids, labels: labels)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: tweaksKey)
        UserDefaults.standard.removeObject(forKey: agentsKey)
        ReapplyAgent.sync()
    }

    private static func save(ids: Set<String>, labels: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: tweaksKey)
        UserDefaults.standard.set(Array(labels).sorted(), forKey: agentsKey)
        ReapplyAgent.sync()
    }

    static func agentLabels(ofTweak id: String) -> [String] {
        guard let t = allTweaks.first(where: { $0.id == id }) else { return [] }
        return t.mechanisms.flatMap { mech -> [String] in
            if case .agents(let l) = mech { return l } else { return [] }
        }
    }

    static func tweak(containing label: String) -> Tweak? {
        allTweaks.first { t in
            t.mechanisms.contains { mech in
                if case .agents(let l) = mech { return l.contains(label) } else { return false }
            }
        }
    }
}

// MARK: - Remise à l'état d'usine

/// Ramène MacTuner exactement à un tout premier lancement : réactive tout ce qui
/// a été désactivé, remet le ventilateur en contrôle automatique, retire l'agent
/// de ré-application et efface toutes les préférences (onboarding compris).
enum AppReset {
    static func toFactoryDefaults() {
        // 1. Réactiver chaque fonctionnalité désactivée (agents, defaults, admin).
        for id in DesiredState.disabledTweakIDs {
            if let t = allTweaks.first(where: { $0.id == id }) {
                Engine.apply(t, disable: false)
            }
        }
        for label in DesiredState.disabledAgentLabels { LaunchCtl.enable(label) }
        DesiredState.clear()      // vide l'état voulu et resynchronise l'agent
        ReapplyAgent.remove()     // retire le LaunchAgent + script de ré-application

        // 2. Ventilateur : retour au contrôle système, sans override de démarrage.
        FanControl.setAuto(index: 0)
        if FanControl.startupEnabled { FanControl.disableStartup() }

        // 3. Effacer TOUTES les préférences (onboarding, gains, langue, fan…).
        if let dom = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: dom)
        }
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Ré-application au login

/// LaunchAgent utilisateur qui ré-applique les désactivations à chaque ouverture
/// de session, puisque macOS peut réactiver des agents Apple au démarrage.
/// Entièrement réversible : retiré dès que plus rien n'est désactivé.
enum ReapplyAgent {
    static let label = "local.rodolphe.mactuner.reapply"
    static var plistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }
    static var supportDir: String { NSHomeDirectory() + "/Library/Application Support/MacTuner" }
    static var scriptPath: String { supportDir + "/reapply.sh" }

    /// Base d'overrides launchd de l'utilisateur : macOS la réécrit quand il
    /// réactive des agents — c'est le signal qui déclenche la ré-application.
    static var overridesPath: String {
        "/private/var/db/com.apple.xpc.launchd/disabled.\(getuid()).plist"
    }

    /// Regénère (ou retire) le script et le LaunchAgent selon l'état voulu,
    /// puis le (re)charge pour que la protection vaille dès la session en cours.
    /// Idempotent : ne réécrit et ne recharge rien si le contenu n'a pas changé.
    static func sync() {
        let lines = scriptLines()
        if lines.isEmpty {
            remove()
            return
        }
        // Le script ne touche à rien qui soit déjà dans l'état voulu : sans ça,
        // chaque passage réécrirait la base d'overrides, que WatchPaths surveille,
        // et l'agent tournerait en boucle.
        let script = """
        #!/bin/sh
        # Généré par MacTuner — ré-applique les désactivations choisies.
        # Lancé au login et dès que macOS réécrit sa base d'overrides launchd.
        U=$(id -u)
        DISABLED=$(/bin/launchctl print-disabled "gui/$U")
        D() {
            # Poser le drapeau seulement s'il manque : le réécrire alors qu'il est
            # déjà là toucherait la base d'overrides que WatchPaths surveille → boucle.
            case "$DISABLED" in
                *"\\"$1\\" => disabled"*) ;;
                *) /bin/launchctl disable "gui/$U/$1" ;;
            esac
            # Le drapeau « disabled » n'implique pas que le processus soit arrêté :
            # macOS relance des agents malgré lui. On tente donc systématiquement le
            # bootout. Sous SIP il est refusé (code 150) et sans effet — inoffensif.
            /bin/launchctl bootout "gui/$U/$1" 2>/dev/null
        }
        \(lines.joined(separator: "\n"))
        """
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array><string>/bin/sh</string><string>\(scriptPath)</string></array>
            <key>RunAtLoad</key><true/>
            <key>WatchPaths</key>
            <array><string>\(overridesPath)</string></array>
        </dict>
        </plist>
        """
        let fm = FileManager.default
        if (try? String(contentsOfFile: scriptPath, encoding: .utf8)) == script,
           (try? String(contentsOfFile: plistPath, encoding: .utf8)) == plist {
            return
        }
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        Shell.run("/bin/launchctl", ["bootout", "\(LaunchCtl.domain)/\(label)"])
        Shell.run("/bin/launchctl", ["bootstrap", LaunchCtl.domain, plistPath])
    }

    static func remove() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistPath) || fm.fileExists(atPath: scriptPath) else { return }
        Shell.run("/bin/launchctl", ["bootout", "\(LaunchCtl.domain)/\(label)"])
        try? fm.removeItem(atPath: plistPath)
        try? fm.removeItem(atPath: scriptPath)
    }

    private static func scriptLines() -> [String] {
        var lines = [String]()
        var seen = Set<String>()
        func addAgent(_ l: String) {
            guard seen.insert(l).inserted else { return }
            lines.append("D \(l)")
        }
        for id in DesiredState.disabledTweakIDs.sorted() {
            guard let t = allTweaks.first(where: { $0.id == id }) else { continue }
            for mech in t.mechanisms {
                switch mech {
                case .agents(let labels):
                    labels.forEach(addAgent)
                case .defaultsKey(let domain, let key, let disabledValue, _, _):
                    let write = ([domain, key] + disabledValue.writeArgs)
                        .map { "'\($0)'" }.joined(separator: " ")
                    lines.append("[ \"$(/usr/bin/defaults read '\(domain)' '\(key)' 2>/dev/null)\" = "
                        + "'\(disabledValue.readForm)' ] || /usr/bin/defaults write \(write)")
                case .admin:
                    break   // persiste par lui-même, et pas d'invite admin au login
                }
            }
        }
        for l in DesiredState.disabledAgentLabels.sorted() { addAgent(l) }
        return lines
    }
}
