//
//  MacTunerApp.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Racine

final class TabSelection: ObservableObject {
    @Published var sel: Int
    // Réglages s'ouvre depuis l'icône ronde de la barre du haut, pas comme onglet.
    @Published var showSettings = false
    init() {
        // Débogage : MT_TAB ouvre directement un onglet ; MT_AUTONAV bascule après 3 s.
        sel = Int(ProcessInfo.processInfo.environment["MT_TAB"] ?? "0") ?? 0
    }
}

struct ContentView: View {
    @StateObject private var tunerModel = TunerModel()
    @StateObject private var cleanModel = CleanModel()
    @StateObject private var uninstallModel = UninstallModel()
    @StateObject private var dashboardModel = DashboardModel()
    @StateObject private var permModel = PermissionsModel()
    @StateObject private var tab = TabSelection()
    @EnvironmentObject var loc: L10n

    var body: some View {
        TabView(selection: $tab.sel) {
            DashboardView(model: dashboardModel)
                .tabItem { Label(loc.t("tab.dashboard"), systemImage: "gauge.with.dots.needle.67percent") }.tag(0)
            FeaturesView(model: tunerModel)
                .tabItem { Label(loc.t("tab.features"), systemImage: "switch.2") }.tag(1)
            // Vérification : ce que chaque service fait, et s'il tourne encore.
            ServicesView()
                .tabItem { Label(loc.t("tab.services"), systemImage: "list.bullet.rectangle.portrait") }.tag(2)
            CleanupHubView(model: cleanModel)
                .tabItem { Label(loc.t("tab.cleaning"), systemImage: "trash") }.tag(3)
            DiskView()
                .tabItem { Label(loc.t("tab.disk"), systemImage: "internaldrive") }.tag(4)
            UninstallView(model: uninstallModel)
                .tabItem { Label(loc.t("tab.uninstall"), systemImage: "xmark.bin.fill") }.tag(5)
            MaintenanceView()
                .tabItem { Label(loc.t("tab.maintenance"), systemImage: "wrench.and.screwdriver") }.tag(6)
            TweaksView()
                .tabItem { Label(loc.t("tab.tweaks"), systemImage: "slider.horizontal.3") }.tag(7)
            SystemInfoView()
                .tabItem { Label(loc.t("tab.system"), systemImage: "info.circle") }.tag(8)
        }
        .frame(minWidth: 1440, minHeight: 760)
        .buttonStyle(DarkButton())
        // Encre de nuit derrière la bande d'onglets et les en-têtes : sans ça,
        // ces zones affichent le gris système (le fameux gris-marron).
        .background(MTColor.nuit.ignoresSafeArea())
        .toolbarBackground(MTColor.nuit, for: .windowToolbar)
        .navigationTitle("MacTuner · \(SysCompat.osName)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                RoundToolbarButton(icon: "gearshape.fill", tint: MTColor.mac,
                                   help: loc.t("tab.settings")) {
                    tab.showSettings = true
                }
                RoundToolbarButton(icon: permModel.fda ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                                   tint: permModel.fda ? .green : MTColor.ambre,
                                   help: loc.t("set.auth")) {
                    permModel.recheckFDA()
                    permModel.showSheet = true
                }
            }
        }
        .sheet(isPresented: $permModel.showSheet) {
            OnboardingView(model: permModel).environmentObject(loc)
                .buttonStyle(DarkButton())
        }
        .sheet(isPresented: $tab.showSettings) {
            ModalSheet { SettingsView(perm: permModel).environmentObject(loc) } onClose: { tab.showSettings = false }
                .buttonStyle(DarkButton())
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            permModel.recheckFDA()
        }
    }
}

// MARK: - Réveil du Mac

/// Observateur de sortie de veille, vivant tant que l'application tourne.
/// Rejoue les réglages que le matériel ne conserve pas d'une veille à l'autre.
/// (Les désactivations launchd et les clés `defaults`, elles, sont persistées sur
/// disque : la veille ne les touche pas, rien à rejouer de ce côté.)
final class WakeWatcher {
    static let shared = WakeWatcher()
    private var token: NSObjectProtocol?

    func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task.detached(priority: .background) { FanControl.restoreDesiredIfNeeded() }
            // L'assertion anti-veille survit à la veille, mais pas à un plantage de
            // caffeinate : on vérifie que l'agent est toujours là.
            Task { @MainActor in
                if UserDefaults.standard.bool(forKey: KeepAwake.prefKey),
                   !KeepAwakeAgent.installed {
                    KeepAwake.shared.start()
                }
            }
        }
    }
}

// MARK: - Application

@main
struct MacTunerApp: App {
    init() {
        // Mode helper root : « MacTuner --smc-fan <index> <mode> <rpm> ».
        // Lancé par osascript/LaunchDaemon en root, écrit dans le SMC puis quitte
        // avant toute création de fenêtre.
        let a = CommandLine.arguments
        if a.count >= 5, a[1] == "--smc-fan" {
            let idx = Int(a[2]) ?? 0
            let mode = UInt8(a[3]) ?? 0
            let rpm = Float(a[4]) ?? 0
            SMC.applyFan(index: idx, mode: mode, rpm: rpm)
            exit(0)
        }
        // Mode helper root : « MacTuner --fan-daemon <index> <rpm> <1|0> ».
        // Écrit (1) ou retire (0) le LaunchDaemon qui rejoue la vitesse au démarrage,
        // puis quitte. Passer par le helper évite de redemander le mot de passe à
        // chaque changement de vitesse quand le réglage de démarrage est actif.
        if a.count >= 5, a[1] == "--fan-daemon" {
            FanControl.runDaemonHelper(index: Int(a[2]) ?? 0, rpm: Int(a[3]) ?? 0,
                                       install: a[4] == "1")
            exit(0)
        }
        // Mode helper root : « MacTuner --clean-system <catégorie> ».
        // Lancé en root (sudo/osascript) pour vider une racine système autorisée,
        // puis quitte avant toute création de fenêtre. La liste blanche compilée
        // (SafetyGuard.isSystemDeletable) borne strictement ce qui peut être supprimé.
        if a.count >= 3, a[1] == "--clean-system" {
            SystemClean.run(categoryID: a[2])
            exit(0)
        }
        // Mode helper root : « MacTuner --launchd-system <disable|enable> <label…> ».
        // Agit sur un ou plusieurs démons du domaine `system` (root requis), puis
        // quitte. Chaque label est confronté à la liste blanche compilée
        // SystemDaemons.allowed : un label absent est ignoré, même appelé en root.
        // C'est ce contrôle — et non la règle sudoers — qui borne réellement ce que
        // ce mode peut désactiver.
        if a.count >= 4, a[1] == "--launchd-system" {
            LaunchCtl.applySystemDaemons(Array(a[3...]), disable: a[2] == "disable")
            exit(0)
        }
        // Mode helper root : « MacTuner --prune-overrides ».
        // Retire de la base launchd les entrées valant « activé », qui ne décrivent
        // rien d'autre que le comportement par défaut. Les désactivations (valeur
        // vraie) ne sont jamais touchées. Le nombre d'entrées retirées est imprimé.
        if a.count >= 2, a[1] == "--prune-overrides" {
            print(LaunchCtl.pruneInertOverrides())
            exit(0)
        }
        // Mode diagnostic : « MacTuner --list-services [all] ».
        // Imprime l'inventaire tel que l'onglet Services le calcule, puis quitte.
        // Sert à vérifier depuis le Terminal, et à contrôler que l'analyse de la
        // sortie de launchctl reste juste après une mise à jour de macOS.
        if a.count >= 2, a[1] == "--list-services" {
            let all = a.count >= 3 && a[2] == "all"
            let rows = ServiceInventory.scan(catalogOnly: !all)
            let running = rows.filter(\.running)
            let pending = rows.filter(\.runningDespiteFlag)
            for r in rows.sorted(by: { $0.rssBytes > $1.rssBytes }) {
                let state: String
                switch r.state {
                case .running:       state = "ACTIF"
                case .idle:          state = "demande"
                case .runningDespiteFlag: state = "RELANCE"
                case .off:           state = "arrete"
                }
                // String(format:) ne remplit pas les gabarits %-N@ : on aligne à la main.
                func pad(_ s: String, _ n: Int) -> String {
                    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
                }
                func padLeft(_ s: String, _ n: Int) -> String {
                    s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
                }
                print(pad(state, 12) + pad(r.domain.rawValue, 8)
                      + padLeft(r.running ? humanBytes(r.rssBytes) : "—", 10) + "  "
                      + pad(r.label, 46) + (r.tweakName.isEmpty ? "—" : r.tweakName))
            }
            print("── \(rows.count) services · \(running.count) actifs · "
                  + "\(humanBytes(rows.reduce(0) { $0 + $1.rssBytes })) · "
                  + "\(rows.filter(\.disabled).count) désactivés · "
                  + "\(pending.count) encore en mémoire")
            exit(0)
        }
        // Mode planifié : nettoyage utilisateur sûr lancé par le LaunchAgent, puis quitte.
        if a.count >= 2, a[1] == "--clean-scheduled" {
            Scheduler.runScheduledCleanup()
            exit(0)
        }
        // Réaligne l'agent de ré-application sur l'état voulu (migration de
        // format, fichiers supprimés à la main…). Sans effet si rien n'a changé.
        Task.detached(priority: .background) { ReapplyAgent.sync() }
        // Préchauffe les infos matériel lentes (system_profiler) pour un onglet
        // Système instantané.
        Task.detached(priority: .background) { HardwareInfo.warm() }
        // Réapplique le choix de veille de l'utilisateur (l'assertion ne survit pas
        // à la fermeture de l'app). Sur la boucle principale, une fois l'app prête.
        DispatchQueue.main.async { KeepAwake.shared.restore() }
        // Réapplique la vitesse de ventilation voulue : le SMC repasse en automatique
        // à chaque redémarrage. Silencieux (aucune invite) et sans effet si
        // l'utilisateur n'a jamais activé le mode manuel.
        Task.detached(priority: .background) { FanControl.restoreDesiredIfNeeded() }
        // Retour de veille : le gestionnaire thermique reprend souvent la main. On
        // ré-affirme la consigne au niveau de l'APPLICATION et non de l'onglet
        // Tableau de bord — cet onglet retire son observateur dès qu'on le quitte,
        // et le réglage n'était alors plus rejoué au réveil.
        WakeWatcher.shared.start()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(L10n.shared)
                // Identité visuelle du site : encre de nuit, sombre en permanence.
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1520, height: 860)
        .windowResizability(.contentMinSize)
    }
}
