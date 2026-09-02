//
//  TweakEngine.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Moteur : fonctionnalités

enum Engine {

    static func defaultsIsDisabled(domain: String, key: String, disabledValue: DefaultsKind,
                                   byHost: Bool = false) -> Bool {
        let raw = Shell.run("/usr/bin/defaults", (byHost ? ["-currentHost"] : []) + ["read", domain, key])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        if let a = Double(raw), let b = Double(disabledValue.readForm) {
            return abs(a - b) < 0.0001
        }
        return raw == disabledValue.readForm
    }

    /// PID d'un agent s'il tourne actuellement (ligne "pid = N" de launchctl print).
    static func runningPID(_ label: String) -> Int32? {
        let out = Shell.run("/bin/launchctl", ["print", "\(LaunchCtl.domain)/\(label)"])
        for line in out.split(separator: "\n") where line.contains("pid = ") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = Int32(trimmed.replacingOccurrences(of: "pid = ", with: "")) {
                return pid
            }
        }
        return nil
    }

    static func parseCPUTime(_ s: String) -> Double {
        var days = 0.0
        var rest = s
        if let dash = s.firstIndex(of: "-") {
            days = Double(s[..<dash]) ?? 0
            rest = String(s[s.index(after: dash)...])
        }
        var secs = 0.0
        for part in rest.split(separator: ":") {
            secs = secs * 60 + (Double(part) ?? 0)
        }
        return days * 86400 + secs
    }

    /// RAM (RSS) et temps CPU de plusieurs PID en un seul appel ps.
    static func psUsage(pids: [Int32]) -> [Int32: (rss: Int64, cpu: Double)] {
        guard !pids.isEmpty else { return [:] }
        let out = Shell.run("/bin/ps", ["-o", "pid=,rss=,time=",
                                        "-p", pids.map(String.init).joined(separator: ",")])
        var result = [Int32: (rss: Int64, cpu: Double)]()
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 3, let pid = Int32(cols[0]), let rssKB = Int64(cols[1]) else { continue }
            result[pid] = (rss: rssKB * 1024, cpu: parseCPUTime(String(cols[2])))
        }
        return result
    }

    /// RAM (RSS) et nombre de processus des agents d'un tweak *actuellement en
    /// cours*. Mesuré avant/après une désactivation, l'écart donne le gain réel :
    /// sous SIP, avant ≈ après (rien n'est tué), donc gain nul, la vérité.
    static func liveUsage(ofTweak tweak: Tweak) -> (rss: Int64, procs: Int) {
        var pids = [Int32]()
        for mech in tweak.mechanisms {
            if case .agents(let labels) = mech {
                for l in labels { if let p = runningPID(l) { pids.append(p) } }
            }
            if case .systemDaemons(let labels) = mech {
                for l in labels { if let p = LaunchCtl.systemRunningPID(l) { pids.append(p) } }
            }
        }
        let info = psUsage(pids: pids)
        return (info.values.reduce(0) { $0 + $1.rss }, info.count)
    }

    /// Identifiant d'affichage d'un démon système. Centralisé : la restauration
    /// retrouve les items par cet identifiant, pas par leur position.
    static func daemonItemID(_ label: String) -> String { "\(label) (système)" }

    static func mechanismItems(_ mech: Mechanism, disabledAgents: Set<String>,
                               disabledDaemons: Set<String>,
                               procUsage: [String: ProcUsage]) -> [DetailItem] {
        switch mech {
        case .systemDaemons(let labels):
            return labels.map { label in
                let off = disabledDaemons.contains(label)
                let info = procUsage[label].map {
                    "\(humanBytes($0.rssBytes)) · CPU \(humanCPU($0.cpuSeconds))"
                }
                return DetailItem(id: Engine.daemonItemID(label), disabled: off,
                                  stillRunning: off && procUsage[label] != nil,
                                  info: info, agentLabel: nil)
            }
        case .agents(let labels):
            return labels.map { label in
                let info = procUsage[label].map {
                    "\(humanBytes($0.rssBytes)) · CPU \(humanCPU($0.cpuSeconds))"
                }
                let off = disabledAgents.contains(label)
                // Drapeau posé mais processus toujours vivant = cas SIP : la
                // désactivation est enregistrée, elle prendra effet au redémarrage.
                return DetailItem(id: label, disabled: off,
                                  stillRunning: off && procUsage[label] != nil,
                                  info: info, agentLabel: label)
            }
        case .defaultsKey(let domain, let key, let disabledValue, _, _):
            let off = defaultsIsDisabled(domain: domain, key: key, disabledValue: disabledValue)
            return [DetailItem(id: "\(domain) → \(key)", disabled: off)]
        case .defaultsHostKey(let domain, let key, let disabledValue, _, _):
            let off = defaultsIsDisabled(domain: domain, key: key,
                                         disabledValue: disabledValue, byHost: true)
            return [DetailItem(id: "\(domain) → \(key)", disabled: off)]
        case .admin(let label, _, _, let checkCmd, let marker):
            let off = Shell.sh(checkCmd).contains(marker)
            return [DetailItem(id: label, disabled: off)]
        }
    }

    static func computeStates() -> (disabled: [String: Bool], items: [String: [DetailItem]],
                                    usage: [String: TweakUsage]) {
        let disabledAgents = LaunchCtl.disabledServices()
        let disabledDaemons = LaunchCtl.disabledSystemServices()

        // Mesure RAM/CPU : PID de CHAQUE service du catalogue, désactivé ou non.
        // Inclure les services désactivés est indispensable : sous SIP, `bootout` est
        // refusé, ils tournent encore et l'interface doit le dire.
        var labelPID = [String: Int32]()
        for tweak in allTweaks {
            for mech in tweak.mechanisms {
                switch mech {
                case .agents(let labels):
                    for label in labels {
                        if let pid = runningPID(label) { labelPID[label] = pid }
                    }
                case .systemDaemons(let labels):
                    for label in labels {
                        if let pid = LaunchCtl.systemRunningPID(label) { labelPID[label] = pid }
                    }
                default:
                    break
                }
            }
        }
        let psInfo = psUsage(pids: Array(labelPID.values))
        var procUsage = [String: ProcUsage]()
        for (label, pid) in labelPID {
            if let u = psInfo[pid] {
                procUsage[label] = ProcUsage(pid: pid, rssBytes: u.rss, cpuSeconds: u.cpu)
            }
        }

        var disabledMap = [String: Bool]()
        var itemsMap = [String: [DetailItem]]()
        var usageMap = [String: TweakUsage]()
        for tweak in allTweaks {
            var items = [DetailItem]()
            var procs = 0
            var rss: Int64 = 0
            var cpu = 0.0
            for mech in tweak.mechanisms {
                items.append(contentsOf: mechanismItems(mech, disabledAgents: disabledAgents,
                                                        disabledDaemons: disabledDaemons,
                                                        procUsage: procUsage))
                var measured = [String]()
                if case .agents(let labels) = mech { measured = labels }
                if case .systemDaemons(let labels) = mech { measured = labels }
                for label in measured {
                    if let u = procUsage[label] {
                        procs += 1
                        rss += u.rssBytes
                        cpu += u.cpuSeconds
                    }
                }
            }
            itemsMap[tweak.id] = items
            disabledMap[tweak.id] = !items.isEmpty && items.allSatisfy(\.disabled)
            usageMap[tweak.id] = TweakUsage(procs: procs, rssBytes: rss, cpuSeconds: cpu)
        }
        return (disabledMap, itemsMap, usageMap)
    }

    /// Ce qu'une application de réglage a réellement produit.
    struct ApplyOutcome {
        /// Tous les drapeaux/clés sont posés : le réglage est enregistré et permanent.
        var persisted = true
        /// Au moins un agent tourne encore : effet complet au prochain redémarrage.
        var pendingReboot = false
    }

    @discardableResult
    static func apply(_ tweak: Tweak, disable: Bool) -> ApplyOutcome {
        var outcome = ApplyOutcome()
        var killalls = Set<String>()
        for mech in tweak.mechanisms {
            switch mech {
            case .agents(let labels):
                for l in labels {
                    if disable {
                        let r = LaunchCtl.disable(l)
                        if !r.flagged { outcome.persisted = false }
                        if !r.stopped { outcome.pendingReboot = true }
                    } else {
                        LaunchCtl.enable(l)
                    }
                }
            case .systemDaemons(let labels):
                // Un seul appel privilégié pour tout le lot : une invite, pas dix.
                let r = LaunchCtl.setSystemDaemons(labels, disabled: disable)
                if disable {
                    if !r.flagged { outcome.persisted = false }
                    if !r.stopped { outcome.pendingReboot = true }
                }
            case .defaultsKey(let domain, let key, let disabledValue, let enabledValue, let killall):
                if disable {
                    Shell.run("/usr/bin/defaults", ["write", domain, key] + disabledValue.writeArgs)
                } else if let v = enabledValue {
                    Shell.run("/usr/bin/defaults", ["write", domain, key] + v.writeArgs)
                } else {
                    Shell.run("/usr/bin/defaults", ["delete", domain, key])
                }
                if let k = killall { killalls.insert(k) }
            case .defaultsHostKey(let domain, let key, let disabledValue, let enabledValue, let killall):
                let host = ["-currentHost"]
                if disable {
                    Shell.run("/usr/bin/defaults", host + ["write", domain, key] + disabledValue.writeArgs)
                } else if let v = enabledValue {
                    Shell.run("/usr/bin/defaults", host + ["write", domain, key] + v.writeArgs)
                } else {
                    Shell.run("/usr/bin/defaults", host + ["delete", domain, key])
                }
                if let k = killall { killalls.insert(k) }
            case .admin(_, let disableCmd, let enableCmd, _, _):
                Shell.adminRun(disable ? disableCmd : enableCmd)
            }
        }
        for k in killalls { Shell.run("/usr/bin/killall", [k]) }
        DesiredState.setTweak(tweak.id, disabled: disable)
        return outcome
    }
}
