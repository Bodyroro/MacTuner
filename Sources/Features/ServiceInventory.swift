//
//  ServiceInventory.swift · MacTuner
//
import SwiftUI
import Darwin

// MARK: - Inventaire des services launchd

enum ServiceDomain: String {
    case agent, daemon

    var badge: LStr {
        switch self {
        case .agent:  return LStr("session", "session")
        case .daemon: return LStr("système", "system")
        }
    }
    var color: Color { self == .agent ? MTColor.bleu : .purple }
    /// Domaine launchd correspondant, tel qu'attendu par `launchctl`.
    var launchdDomain: String {
        self == .agent ? LaunchCtl.domain : LaunchCtl.systemDomain
    }
}

/// Une ligne d'inventaire : ce que launchd sait d'un service, plus ce que
/// MacTuner en sait. Volontairement inerte — la vue n'agit sur rien.
struct ServiceRow: Identifiable {
    let label: String
    let domain: ServiceDomain
    /// Fiche du catalogue qui couvre ce service, nil s'il n'est couvert par aucune.
    let tweakID: String?
    let tweakName: String
    let role: LStr?
    let pid: Int32?
    let rssBytes: Int64
    /// Le drapeau « disabled » est posé dans la base launchd : permanent.
    let disabled: Bool

    var id: String { "\(domain.rawValue)/\(label)" }
    var running: Bool { pid != nil }

    /// Drapeau « disabled » posé ET service quand même en mémoire. Ce n'est pas
    /// un reliquat d'avant la désactivation : macOS réveille ces agents à la
    /// demande (XPC/Mach) en ignorant le drapeau, y compris après un boot à froid.
    var runningDespiteFlag: Bool { disabled && running }
    /// Désactivé et plus rien en mémoire : le résultat visé.
    var fullyOff: Bool { disabled && !running }

    /// Trois états, un seul coup d'œil.
    var state: State {
        if runningDespiteFlag { return .runningDespiteFlag }
        if disabled { return .off }
        return running ? .running : .idle
    }

    enum State {
        /// Actif, en mémoire.
        case running
        /// Non désactivé, mais pas lancé actuellement (service à la demande).
        case idle
        /// Drapeau posé, mais relancé à la demande : SIP doit être désactivé.
        case runningDespiteFlag
        /// Désactivé et arrêté.
        case off

        var color: Color {
            switch self {
            case .running:       return .green
            case .idle:          return .secondary
            case .runningDespiteFlag: return MTColor.ambre
            case .off:           return MTColor.rouge
            }
        }
        var key: String {
            switch self {
            case .running:       return "svc.state.running"
            case .idle:          return "svc.state.idle"
            case .runningDespiteFlag: return "svc.state.pending"
            case .off:           return "svc.state.off"
            }
        }
    }
}

enum ServiceInventory {

    /// Services connus de launchd dans un domaine, avec leur PID s'ils tournent.
    /// Un seul appel `launchctl print` par domaine : la sortie liste tout, alors
    /// qu'interroger service par service coûterait des centaines de processus.
    ///
    /// Format d'une ligne du bloc `services` : `\t\t<pid>\t<état>\t<label>`,
    /// le PID valant 0 (ou `-`) quand le service n'est pas lancé.
    static func loaded(in domain: ServiceDomain) -> [String: Int32] {
        let out = Shell.run("/bin/launchctl", ["print", domain.launchdDomain])
        var result = [String: Int32]()
        var inBlock = false
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            if !inBlock {
                if line.contains("services = {") { inBlock = true }
                continue
            }
            if line.hasPrefix("\t}") { break }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let label = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
            let head = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            let pid = head.split(separator: " ").first.flatMap { Int32($0) } ?? 0
            result[label] = pid
        }
        return result
    }

    /// Inventaire complet.
    /// - Parameter catalogOnly: ne garder que les services référencés par une fiche.
    static func scan(catalogOnly: Bool) -> [ServiceRow] {
        // Ce que le catalogue couvre : label + domaine -> fiche.
        var covered = [String: (id: String, name: String)]()
        for tweak in allTweaks {
            for mech in tweak.mechanisms {
                switch mech {
                case .agents(let labels):
                    for l in labels {
                        covered["\(ServiceDomain.agent.rawValue)/\(l)"] = (tweak.id, tweak.name.current)
                    }
                case .systemDaemons(let labels):
                    for l in labels {
                        covered["\(ServiceDomain.daemon.rawValue)/\(l)"] = (tweak.id, tweak.name.current)
                    }
                default:
                    break
                }
            }
        }

        var rows = [ServiceRow]()
        var pids = [Int32]()
        var pending = [(String, ServiceDomain, Int32?, Bool)]()

        for domain in [ServiceDomain.agent, .daemon] {
            let loadedMap = loaded(in: domain)
            let disabledSet = LaunchCtl.disabledServices(in: domain.launchdDomain)
            // Un service désactivé disparaît de la liste `services` de launchd :
            // sans l'union avec print-disabled, il serait absent de l'inventaire,
            // et c'est justement celui qu'on veut vérifier.
            var labels = Set(loadedMap.keys).union(disabledSet)
            if catalogOnly {
                labels = labels.union(covered.keys.compactMap { key -> String? in
                    let parts = key.split(separator: "/", maxSplits: 1)
                    guard parts.count == 2, String(parts[0]) == domain.rawValue else { return nil }
                    return String(parts[1])
                })
            }
            for label in labels {
                let key = "\(domain.rawValue)/\(label)"
                if catalogOnly && covered[key] == nil { continue }
                let pid = loadedMap[label].flatMap { $0 > 0 ? $0 : nil }
                if let p = pid { pids.append(p) }
                pending.append((label, domain, pid, disabledSet.contains(label)))
            }
        }

        // RSS de tous les processus en un seul appel ps.
        let usage = Engine.psUsage(pids: pids)
        for (label, domain, pid, disabled) in pending {
            let key = "\(domain.rawValue)/\(label)"
            let tweak = covered[key]
            rows.append(ServiceRow(label: label, domain: domain,
                                   tweakID: tweak?.id,
                                   tweakName: tweak?.name ?? "",
                                   role: serviceRoles[label],
                                   pid: pid,
                                   rssBytes: pid.flatMap { usage[$0]?.rss } ?? 0,
                                   disabled: disabled))
        }
        return rows
    }
}

@MainActor
final class ServicesModel: ObservableObject {
    /// 0 = catalogue MacTuner · 1 = tout ce que launchd connaît.
    @Published var scope = 0
    @Published var rows: [ServiceRow] = []
    @Published var search = ""
    @Published var runningOnly = false
    @Published var busy = false
    @Published var scanned = false

    func load() {
        busy = true
        let catalogOnly = scope == 0
        Task.detached(priority: .userInitiated) {
            let r = ServiceInventory.scan(catalogOnly: catalogOnly)
            await MainActor.run {
                self.rows = r
                self.busy = false
                self.scanned = true
            }
        }
    }

    var filtered: [ServiceRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { row in
            if runningOnly && !row.running { return false }
            guard !q.isEmpty else { return true }
            return row.label.lowercased().contains(q)
                || row.tweakName.lowercased().contains(q)
                || (row.role.map { ($0.fr + " " + $0.en).lowercased().contains(q) } ?? false)
        }
        // Les plus gourmands d'abord : c'est l'information la plus actionnable.
        .sorted {
            if $0.rssBytes != $1.rssBytes { return $0.rssBytes > $1.rssBytes }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    var runningCount: Int { rows.filter(\.running).count }
    var disabledCount: Int { rows.filter(\.disabled).count }
    var runningDespiteFlagCount: Int { rows.filter(\.runningDespiteFlag).count }
    var totalRSS: Int64 { rows.reduce(0) { $0 + $1.rssBytes } }
}
