//
//  Persistence.swift · MacTuner
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
            // « toute désactivée », on bascule sur des entrées individuelles.
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

/// Restauration exhaustive : tout ce que MacTuner a pu rendre persistant est
/// remis dans l'état d'origine, quelle qu'en soit la trace.
///
/// Une seule implémentation sert la réinitialisation ET la désinstallation, pour
/// qu'elles ne puissent pas diverger. Elle travaille sur l'état RÉEL du système,
/// pas sur la mémoire de l'app : un réglage désactivé par une version antérieure,
/// ou un seul sous-processus coupé à la main, était auparavant laissé en place —
/// la fiche entière n'étant pas « toute désactivée », rien n'était restauré.
enum Restore {

    /// Remet tout à l'état par défaut.
    /// - Parameter removeAuthorizations: retire aussi les règles sudoers, le
    ///   LaunchDaemon du ventilateur et les fichiers de sauvegarde. Fait en DERNIER,
    ///   sinon les restaurations privilégiées perdraient leur passe-droit en route.
    static func toDefaults(removeAuthorizations: Bool) {
        let states = Engine.computeStates()

        var daemonsToEnable = [String]()
        var adminCmds = [String]()

        for tweak in allTweaks {
            // Recherche par identifiant plutôt que par position : le moteur fabrique
            // ces identifiants, ils ne peuvent pas se désaligner si l'ordre change.
            var off = [String: Bool]()
            for item in states.items[tweak.id] ?? [] { off[item.id] = item.disabled }

            for mech in tweak.mechanisms {
                switch mech {
                case .agents(let labels):
                    for label in labels where off[label] == true {
                        LaunchCtl.enable(label)
                    }
                case .systemDaemons(let labels):
                    for label in labels where off[Engine.daemonItemID(label)] == true {
                        daemonsToEnable.append(label)
                    }
                case .defaultsKey(let domain, let key, _, let enabledValue, let killall):
                    guard off["\(domain) → \(key)"] == true else { continue }
                    if let v = enabledValue {
                        Shell.run("/usr/bin/defaults", ["write", domain, key] + v.writeArgs)
                    } else {
                        Shell.run("/usr/bin/defaults", ["delete", domain, key])
                    }
                    if let k = killall { Shell.run("/usr/bin/killall", [k]) }
                case .defaultsHostKey(let domain, let key, _, let enabledValue, let killall):
                    guard off["\(domain) → \(key)"] == true else { continue }
                    let host = ["-currentHost"]
                    if let v = enabledValue {
                        Shell.run("/usr/bin/defaults", host + ["write", domain, key] + v.writeArgs)
                    } else {
                        Shell.run("/usr/bin/defaults", host + ["delete", domain, key])
                    }
                    if let k = killall { Shell.run("/usr/bin/killall", [k]) }
                case .admin(let label, _, let enableCmd, _, _):
                    if off[label] == true { adminCmds.append(enableCmd) }
                }
            }
        }

        // Tous les démons système en UN seul appel privilégié, toutes les commandes
        // admin en une seule autre : deux invites au maximum, pas une par service.
        if !daemonsToEnable.isEmpty {
            LaunchCtl.setSystemDaemons(daemonsToEnable, disabled: false)
        }
        if !adminCmds.isEmpty {
            Shell.adminRun(adminCmds.joined(separator: "; ") + "; true")
        }

        // Agents individuels mémorisés qui ne relèvent d'aucune fiche du catalogue.
        for label in DesiredState.disabledAgentLabels where !label.isEmpty {
            LaunchCtl.enable(label)
        }

        // Traces posées par MacTuner lui-même, toutes réversibles sans privilège.
        DesiredState.clear()
        ReapplyAgent.remove()
        KeepAwakeAgent.remove()
        Scheduler.disable()

        // Ventilateur : retour au contrôle thermique du système.
        if SMC.fanCount() > 0 { FanControl.setAuto(index: 0) }
        if FanControl.startupEnabled { FanControl.disableStartup() }
        FanControl.forgetDesired()

        if removeAuthorizations { revokeAuthorizations() }
    }

    /// Retire les règles sudoers, le LaunchDaemon du ventilateur et les fichiers de
    /// sauvegarde laissés par le nettoyage de la base launchd. Une seule invite.
    static func revokeAuthorizations() {
        Shell.admin("(launchctl bootout system/\(FanControl.daemonLabel) 2>/dev/null; true); "
            + "rm -f /etc/sudoers.d/mactuner /etc/sudoers.d/mactuner-fan "
            + "/etc/sudoers.d/mactuner-clean \(FanControl.daemonPath) "
            + "/private/var/db/com.apple.xpc.launchd/*.mactuner-backup 2>/dev/null; true")
    }
}

/// Ramène MacTuner exactement à un tout premier lancement.
enum AppReset {
    static func toFactoryDefaults() {
        // Autorisations comprises : à un premier lancement, aucune règle sudoers
        // n'existe. Les laisser en place ne serait pas un retour à l'état d'usine.
        Restore.toDefaults(removeAuthorizations: true)

        // Effacer TOUTES les préférences (onboarding, langue, ventilateur…).
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
    /// réactive des agents, c'est le signal qui déclenche la ré-application.
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
        # Généré par MacTuner, ré-applique les désactivations choisies.
        # Lancé au login, à chaque heure, et dès que macOS réécrit sa base d'overrides.
        U=$(id -u)
        MT_BIN="\(Shell.shellDoubleQuoted(Permissions.cleanBinaryPath))"
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
            # bootout. Sous SIP il est refusé (code 150) et sans effet, inoffensif.
            /bin/launchctl bootout "gui/$U/$1" 2>/dev/null
        }
        # Réglages admin : ré-affirmés UNIQUEMENT si la règle sudoers durable est en
        # place (sudo -n ne demande jamais de mot de passe). Sans elle, on ne fait rien
        # plutôt que de faire surgir une invite au login. Utile après une mise à jour
        # de macOS, qui remet parfois powernap ou l'indexation à leur valeur d'usine.
        A() {
            /usr/bin/sudo -n "$@" >/dev/null 2>&1
        }
        # Démons du domaine `system` : root obligatoire. Comme pour les réglages
        # admin, on n'agit que si la règle sudoers restreinte est en place, jamais
        # au prix d'une invite de mot de passe au login.
        DSYS=$(/bin/launchctl print-disabled system)
        S() {
            case "$DSYS" in
                *"\\"$1\\" => disabled"*) ;;
                *) A "$MT_BIN" --launchd-system disable "$1" ;;
            esac
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
            <!-- Re-vérification horaire : une mise à jour de macOS peut réactiver des
                 agents sans toucher la base d'overrides, donc sans déclencher WatchPaths.
                 Le script est idempotent : sans dérive, il ne écrit rien. -->
            <key>StartInterval</key><integer>3600</integer>
            <!-- Anti-rebond : jamais deux exécutions à moins de 10 s d'intervalle. -->
            <key>ThrottleInterval</key><integer>10</integer>
            <key>ProcessType</key><string>Background</string>
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
                case .systemDaemons(let labels):
                    for l in labels where seen.insert("sys:" + l).inserted {
                        lines.append("S \(l)")
                    }
                case .defaultsKey(let domain, let key, let disabledValue, _, _):
                    let write = ([domain, key] + disabledValue.writeArgs)
                        .map { "'\($0)'" }.joined(separator: " ")
                    lines.append("[ \"$(/usr/bin/defaults read '\(domain)' '\(key)' 2>/dev/null)\" = "
                        + "'\(disabledValue.readForm)' ] || /usr/bin/defaults write \(write)")
                case .defaultsHostKey(let domain, let key, let disabledValue, _, _):
                    let write = ([domain, key] + disabledValue.writeArgs)
                        .map { "'\($0)'" }.joined(separator: " ")
                    lines.append("[ \"$(/usr/bin/defaults -currentHost read '\(domain)' '\(key)' 2>/dev/null)\" = "
                        + "'\(disabledValue.readForm)' ] || /usr/bin/defaults -currentHost write \(write)")
                case .admin(_, let disableCmd, _, let checkCmd, let marker):
                    // Ces réglages persistent d'eux-mêmes (mdutil, pmset, nvram), mais
                    // une mise à jour de macOS peut les remettre d'usine. On les
                    // re-vérifie, et on ne corrige que via sudo -n : jamais d'invite.
                    lines.append("/usr/bin/sudo -n -l >/dev/null 2>&1 && "
                        + "case \"$(\(checkCmd) 2>/dev/null)\" in *'\(marker)'*) ;; "
                        + "*) A \(disableCmd) ;; esac")
                }
            }
        }
        for l in DesiredState.disabledAgentLabels.sorted() { addAgent(l) }
        return lines
    }
}
