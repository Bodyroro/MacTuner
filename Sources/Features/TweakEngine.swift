//
//  TweakEngine.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Moteur : fonctionnalités

enum Engine {

    static func defaultsIsDisabled(domain: String, key: String, disabledValue: DefaultsKind) -> Bool {
        let raw = Shell.run("/usr/bin/defaults", ["read", domain, key])
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
    /// sous SIP, avant ≈ après (rien n'est tué), donc gain nul — la vérité.
    static func liveUsage(ofTweak tweak: Tweak) -> (rss: Int64, procs: Int) {
        var pids = [Int32]()
        for mech in tweak.mechanisms {
            if case .agents(let labels) = mech {
                for l in labels { if let p = runningPID(l) { pids.append(p) } }
            }
        }
        let info = psUsage(pids: pids)
        return (info.values.reduce(0) { $0 + $1.rss }, info.count)
    }

    static func mechanismItems(_ mech: Mechanism, disabledAgents: Set<String>,
                               procUsage: [String: ProcUsage]) -> [DetailItem] {
        switch mech {
        case .agents(let labels):
            return labels.map { label in
                let info = procUsage[label].map {
                    "\(humanBytes($0.rssBytes)) · CPU \(humanCPU($0.cpuSeconds))"
                }
                return DetailItem(id: label, disabled: disabledAgents.contains(label),
                                  info: info, agentLabel: label)
            }
        case .defaultsKey(let domain, let key, let disabledValue, _, _):
            let off = defaultsIsDisabled(domain: domain, key: key, disabledValue: disabledValue)
            return [DetailItem(id: "\(domain) → \(key)", disabled: off, info: nil, agentLabel: nil)]
        case .admin(let label, _, _, let checkCmd, let marker):
            let off = Shell.sh(checkCmd).contains(marker)
            return [DetailItem(id: label, disabled: off, info: nil, agentLabel: nil)]
        }
    }

    static func computeStates() -> (disabled: [String: Bool], items: [String: [DetailItem]],
                                    usage: [String: TweakUsage]) {
        let disabledAgents = LaunchCtl.disabledServices()

        // Mesure RAM/CPU : PID de chaque agent non désactivé, puis un seul appel ps.
        var labelPID = [String: Int32]()
        for tweak in allTweaks {
            for mech in tweak.mechanisms {
                if case .agents(let labels) = mech {
                    for label in labels where !disabledAgents.contains(label) {
                        if let pid = runningPID(label) { labelPID[label] = pid }
                    }
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
                                                        procUsage: procUsage))
                if case .agents(let labels) = mech {
                    for label in labels {
                        if let u = procUsage[label] {
                            procs += 1
                            rss += u.rssBytes
                            cpu += u.cpuSeconds
                        }
                    }
                }
            }
            itemsMap[tweak.id] = items
            disabledMap[tweak.id] = !items.isEmpty && items.allSatisfy(\.disabled)
            usageMap[tweak.id] = TweakUsage(procs: procs, rssBytes: rss, cpuSeconds: cpu)
        }
        return (disabledMap, itemsMap, usageMap)
    }

    static func apply(_ tweak: Tweak, disable: Bool) {
        var killalls = Set<String>()
        for mech in tweak.mechanisms {
            switch mech {
            case .agents(let labels):
                for l in labels { if disable { LaunchCtl.disable(l) } else { LaunchCtl.enable(l) } }
            case .defaultsKey(let domain, let key, let disabledValue, let enabledValue, let killall):
                if disable {
                    Shell.run("/usr/bin/defaults", ["write", domain, key] + disabledValue.writeArgs)
                } else if let v = enabledValue {
                    Shell.run("/usr/bin/defaults", ["write", domain, key] + v.writeArgs)
                } else {
                    Shell.run("/usr/bin/defaults", ["delete", domain, key])
                }
                if let k = killall { killalls.insert(k) }
            case .admin(_, let disableCmd, let enableCmd, _, _):
                Shell.adminRun(disable ? disableCmd : enableCmd)
            }
        }
        for k in killalls { Shell.run("/usr/bin/killall", [k]) }
        DesiredState.setTweak(tweak.id, disabled: disable)
    }
}

