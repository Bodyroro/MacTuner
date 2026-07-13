//
//  ViewModels.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - États observables

@MainActor
final class TunerModel: ObservableObject {
    @Published var tweakDisabled: [String: Bool] = [:]
    @Published var itemStates: [String: [DetailItem]] = [:]
    @Published var tweakUsage: [String: TweakUsage] = [:]
    @Published var busy = false
    @Published var pendingDisable: Tweak?
    @Published var detailTweak: Tweak?
    @Published var searchText = ""
    /// Gains persistés : RAM et processus mesurés au moment de chaque désactivation.
    @Published var freedMemBytes: Int64 = 0
    @Published var freedProcs = 0
    /// Écart entre l'état voulu (persisté) et l'état réel : ce que macOS a réactivé.
    @Published var driftTweakIDs: [String] = []
    @Published var driftAgentLabels: [String] = []

    init() { reloadFreedTotals() }

    var disabledCount: Int { tweakDisabled.values.filter { $0 }.count }

    var driftCount: Int { driftTweakIDs.count + driftAgentLabels.count }

    func isDisabled(_ tweak: Tweak) -> Bool { tweakDisabled[tweak.id] ?? false }

    private func reloadFreedTotals() {
        let mem = (UserDefaults.standard.dictionary(forKey: "freedMem") ?? [:])
            .compactMapValues { $0 as? Int }
        let procs = (UserDefaults.standard.dictionary(forKey: "freedProcs") ?? [:])
            .compactMapValues { $0 as? Int }
        freedMemBytes = Int64(mem.values.reduce(0, +))
        freedProcs = procs.values.reduce(0, +)
    }

    /// Enregistre le gain *réellement* obtenu : l'écart de RAM/processus mesuré
    /// autour de la désactivation. Si rien n'a été arrêté (cas SIP), le gain est
    /// nul et aucune valeur fictive n'est stockée.
    private func recordFreed(_ tweak: Tweak, disabled: Bool,
                             before: (rss: Int64, procs: Int) = (0, 0),
                             after: (rss: Int64, procs: Int) = (0, 0)) {
        var mem = (UserDefaults.standard.dictionary(forKey: "freedMem") ?? [:])
            .compactMapValues { $0 as? Int }
        var procs = (UserDefaults.standard.dictionary(forKey: "freedProcs") ?? [:])
            .compactMapValues { $0 as? Int }
        let freedProcs = max(0, before.procs - after.procs)
        if disabled && freedProcs > 0 {
            mem[tweak.id] = Int(max(0, before.rss - after.rss))
            procs[tweak.id] = freedProcs
        } else {
            // Réactivation, ou désactivation sans arrêt effectif (SIP) : pas de gain.
            mem.removeValue(forKey: tweak.id)
            procs.removeValue(forKey: tweak.id)
        }
        UserDefaults.standard.set(mem, forKey: "freedMem")
        UserDefaults.standard.set(procs, forKey: "freedProcs")
        reloadFreedTotals()
    }

    private func applyStates(_ states: (disabled: [String: Bool], items: [String: [DetailItem]],
                                        usage: [String: TweakUsage])) {
        tweakDisabled = states.disabled
        itemStates = states.items
        tweakUsage = states.usage
        busy = false
        computeDrift()
    }

    /// Compare l'état voulu par l'utilisateur à l'état réel du système :
    /// tout ce que macOS a réactivé (typiquement au redémarrage) est signalé.
    private func computeDrift() {
        let desired = DesiredState.disabledTweakIDs
        driftTweakIDs = allTweaks
            .filter { desired.contains($0.id) && !$0.needsAdmin && !(tweakDisabled[$0.id] ?? false) }
            .map(\.id)
        let disabledNow = Set(itemStates.values.flatMap { $0 }
            .filter(\.disabled).compactMap(\.agentLabel))
        driftAgentLabels = DesiredState.disabledAgentLabels
            .filter { !disabledNow.contains($0) }.sorted()
    }

    /// Ré-applique tout ce que macOS a réactivé.
    func reapplyDrift() {
        busy = true
        let ids = driftTweakIDs
        let labels = driftAgentLabels
        Task.detached(priority: .userInitiated) {
            for id in ids {
                if let tweak = allTweaks.first(where: { $0.id == id }) {
                    Engine.apply(tweak, disable: true)
                }
            }
            for l in labels { LaunchCtl.disable(l) }
            let states = Engine.computeStates()
            await MainActor.run { self.applyStates(states) }
        }
    }

    func refresh() {
        busy = true
        Task.detached(priority: .userInitiated) {
            let states = Engine.computeStates()
            await MainActor.run { self.applyStates(states) }
        }
    }

    func setTweak(_ tweak: Tweak, disabled: Bool) {
        busy = true
        Task.detached(priority: .userInitiated) {
            // Mesure avant/après pour ne créditer que le gain réel (voir recordFreed).
            let before = disabled ? Engine.liveUsage(ofTweak: tweak) : (rss: Int64(0), procs: 0)
            Engine.apply(tweak, disable: disabled)
            let after = disabled ? Engine.liveUsage(ofTweak: tweak) : (rss: Int64(0), procs: 0)
            let states = Engine.computeStates()
            await MainActor.run {
                self.applyStates(states)
                self.recordFreed(tweak, disabled: disabled, before: before, after: after)
            }
        }
    }

    /// Active/désactive un seul sous-processus (agent launchd) d'une catégorie.
    func setAgent(_ label: String, disabled: Bool) {
        busy = true
        Task.detached(priority: .userInitiated) {
            if disabled { LaunchCtl.disable(label) } else { LaunchCtl.enable(label) }
            DesiredState.setAgent(label, disabled: disabled)
            let states = Engine.computeStates()
            await MainActor.run { self.applyStates(states) }
        }
    }

    func restoreAll() {
        busy = true
        // Ne réactive que ce qui est effectivement désactivé (entièrement ou en
        // partie) : un réglage jamais touché n'est pas réécrit — on ne force pas,
        // par exemple, la pub personnalisée chez qui l'avait coupée ailleurs.
        let touched = Set(itemStates.filter { $0.value.contains(where: \.disabled) }.map(\.key))
        UserDefaults.standard.removeObject(forKey: "freedMem")
        UserDefaults.standard.removeObject(forKey: "freedProcs")
        reloadFreedTotals()
        Task.detached(priority: .userInitiated) {
            for tweak in allTweaks where touched.contains(tweak.id) {
                Engine.apply(tweak, disable: false)
            }
            DesiredState.clear()
            let states = Engine.computeStates()
            await MainActor.run { self.applyStates(states) }
        }
    }
}

@MainActor
final class CleanModel: ObservableObject {
    @Published var stats: [String: [PathStat]] = [:]
    @Published var selected: Set<String> = []
    @Published var detailCategory: CleanCategory?
    @Published var busy = false
    @Published var hasScanned = false
    @Published var confirmClean = false
    @Published var lastFreed: Int64?
    /// Fenêtre de progression du nettoyage (reste affichée jusqu'à fermeture).
    @Published var cleaningActive = false
    @Published var cleanProgress = 0.0
    @Published var currentTarget = ""
    /// Cumul d'espace libéré depuis l'installation (persisté).
    @Published var totalFreedEver: Int64 = Int64(UserDefaults.standard.integer(forKey: "totalFreedDisk"))

    func categoryBytes(_ id: String) -> Int64 {
        (stats[id] ?? []).reduce(0) { $0 + $1.bytes }
    }

    var totalBytes: Int64 {
        cleanCategories.reduce(0) { $0 + categoryBytes($1.id) }
    }

    var selectedBytes: Int64 {
        selected.reduce(0) { $0 + categoryBytes($1) }
    }

    func scan() {
        busy = true
        Task.detached(priority: .userInitiated) {
            let result = CleanEngine.scan()
            await MainActor.run {
                self.stats = result
                self.busy = false
                self.hasScanned = true
            }
        }
    }

    func cleanSelected() {
        busy = true
        cleaningActive = true
        cleanProgress = 0
        currentTarget = ""
        let ids = selected
        let snapshot = stats
        Task.detached(priority: .userInitiated) {
            let freed = CleanEngine.clean(categoryIDs: ids, stats: snapshot) { frac, path in
                Task { @MainActor in
                    self.cleanProgress = frac
                    self.currentTarget = path
                }
            }
            let result = CleanEngine.scan()
            await MainActor.run {
                self.stats = result
                self.lastFreed = freed
                self.totalFreedEver += freed
                UserDefaults.standard.set(Int(self.totalFreedEver), forKey: "totalFreedDisk")
                self.selected = []
                self.cleanProgress = 1
                self.busy = false
            }
        }
    }
}

@MainActor
final class UninstallModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var cliTools: [InstalledApp] = []
    @Published var dotItems: [InstalledApp] = []
    @Published var listMode = 0   // 0 = apps, 1 = outils CLI, 2 = fichiers cachés
    @Published var scanned = false
    @Published var scanningApps = false
    @Published var searchText = ""

    @Published var selectedApp: InstalledApp?
    @Published var residues: [Residue] = []
    @Published var selectedResidues: Set<String> = []
    @Published var findingResidues = false

    @Published var confirm = false
    @Published var busy = false
    @Published var lastResult: (app: String, freed: Int64, count: Int)?
    @Published var totalUninstalledEver: Int64 = Int64(UserDefaults.standard.integer(forKey: "totalUninstalled"))

    var filteredApps: [InstalledApp] {
        let source = [apps, cliTools, dotItems][min(listMode, 2)]
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return source }
        return source.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    var selectedBytes: Int64 {
        residues.filter { selectedResidues.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    func scanApps() {
        scanningApps = true
        Task.detached(priority: .userInitiated) {
            let list = UninstallEngine.scanApps()
            let cli = UninstallEngine.scanCLITools()
            // Un dotfile déjà rattaché à un outil CLI (ex. ~/.claude ↔ claude)
            // n'apparaît pas en double : il est couvert par la fiche de l'outil.
            let cliNames = Set(cli.map { $0.name.lowercased() })
            let dots = UninstallEngine.scanDotItems().filter { !cliNames.contains($0.name.lowercased()) }
            await MainActor.run {
                self.apps = list
                self.cliTools = cli
                self.dotItems = dots
                self.scanningApps = false
                self.scanned = true
            }
        }
    }

    func inspect(_ app: InstalledApp) {
        selectedApp = app
        residues = []
        selectedResidues = []
        findingResidues = true
        Task.detached(priority: .userInitiated) {
            let found = app.kind == .app ? UninstallEngine.findResidues(for: app)
                                         : UninstallEngine.findCLIResidues(for: app)
            await MainActor.run {
                self.residues = found
                // Préselection : bundle + correspondances de confiance élevée uniquement.
                self.selectedResidues = Set(found.filter { $0.highConfidence }.map(\.id))
                self.findingResidues = false
            }
        }
    }

    func uninstall() {
        guard let app = selectedApp else { return }
        let chosen = residues.filter { selectedResidues.contains($0.id) }
        busy = true
        Task.detached(priority: .userInitiated) {
            let result = UninstallEngine.uninstall(app: app, residues: chosen)
            let list = UninstallEngine.scanApps()
            await MainActor.run {
                self.apps = list
                self.totalUninstalledEver += result.freed
                UserDefaults.standard.set(Int(self.totalUninstalledEver), forKey: "totalUninstalled")
                self.lastResult = (app.name, result.freed, chosen.count)
                self.selectedApp = nil
                self.residues = []
                self.selectedResidues = []
                self.busy = false
            }
        }
    }
}

