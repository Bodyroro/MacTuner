//
//  ViewModels.swift · MacTuner
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
    /// Écart entre l'état voulu (persisté) et l'état réel : ce que macOS a réactivé.
    @Published var driftTweakIDs: [String] = []
    @Published var driftAgentLabels: [String] = []

    var disabledCount: Int { tweakDisabled.values.filter { $0 }.count }

    var driftCount: Int { driftTweakIDs.count + driftAgentLabels.count }

    /// Agents portant le drapeau « disabled » dont le processus tourne quand même.
    /// Ce n'est PAS un état transitoire qu'un redémarrage résoudrait : macOS les
    /// réveille à la demande (XPC/Mach) malgré le drapeau, et SIP interdit de les
    /// arrêter. Sans désactiver SIP, ce compteur reste durablement non nul.
    var stillRunningDespiteFlagCount: Int {
        itemStates.values.flatMap { $0 }.filter(\.stillRunning).count
    }

    func isDisabled(_ tweak: Tweak) -> Bool { tweakDisabled[tweak.id] ?? false }

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
            Engine.apply(tweak, disable: disabled)
            let states = Engine.computeStates()
            await MainActor.run { self.applyStates(states) }
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
        // partie) : un réglage jamais touché n'est pas réécrit, on ne force pas,
        // par exemple, la pub personnalisée chez qui l'avait coupée ailleurs.
        let touched = Set(itemStates.filter { $0.value.contains(where: \.disabled) }.map(\.key))
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
    /// Section affichée dans l'onglet Nettoyage : 0 catégories, 1 langues, 2 journal.
    @Published var section = 0
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

    func categoryBytes(_ id: String) -> Int64 {
        (stats[id] ?? []).reduce(0) { $0 + $1.bytes }
    }

    var totalBytes: Int64 {
        cleanCategories.reduce(0) { $0 + categoryBytes($1.id) }
    }

    var selectedBytes: Int64 {
        selected.reduce(0) { $0 + categoryBytes($1) }
    }

    /// Catégories sélectionnables : analysées, non vides.
    var selectableIDs: [String] {
        guard hasScanned else { return [] }
        return cleanCategories.map(\.id).filter { categoryBytes($0) > 0 }
    }

    /// true si une catégorie « système » (droits admin) est sélectionnée.
    var selectionNeedsAdmin: Bool {
        cleanCategories.contains { selected.contains($0.id) && $0.needsAdmin }
    }

    var allSelectableSelected: Bool {
        let ids = selectableIDs
        return !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
    }

    /// Tout sélectionner / tout désélectionner (bascule).
    func toggleSelectAll() {
        if allSelectableSelected { selected = [] }
        else { selected = Set(selectableIDs) }
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
        let needsAdmin = selectionNeedsAdmin
        Task.detached(priority: .userInitiated) {
            // Une seule invite de mot de passe pour tout le nettoyage système :
            // on installe la règle sudoers dédiée avant de lancer le helper, plutôt
            // qu'une invite par catégorie.
            if needsAdmin && !Permissions.hasCleanAuth() {
                _ = Permissions.installCleanAuth()
            }
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
    @Published var sortBySize = true   // par défaut : les plus volumineux d'abord

    @Published var selectedApp: InstalledApp?
    @Published var residues: [Residue] = []
    @Published var selectedResidues: Set<String> = []
    @Published var findingResidues = false

    @Published var confirm = false
    @Published var busy = false
    @Published var lastResult: (app: String, freed: Int64, count: Int)?

    var filteredApps: [InstalledApp] {
        let source = [apps, cliTools, dotItems][min(listMode, 2)]
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? source
            : source.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
        return filtered.sorted {
            sortBySize ? $0.bytes > $1.bytes
                       : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Nombre et poids total de la liste affichée (pour l'en-tête).
    var currentCount: Int { filteredApps.count }
    var currentTotalBytes: Int64 { filteredApps.reduce(0) { $0 + $1.bytes } }
    /// Résidus système (hors dossier perso) parmi ceux sélectionnés.
    var selectedSystemCount: Int {
        residues.filter { selectedResidues.contains($0.id) && $0.system }.count
    }
    var residuesTotalBytes: Int64 { residues.reduce(0) { $0 + $1.bytes } }

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
                self.lastResult = (app.name, result.freed, chosen.count)
                self.selectedApp = nil
                self.residues = []
                self.selectedResidues = []
                self.busy = false
            }
        }
    }
}
