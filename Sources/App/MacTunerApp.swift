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
            CleanupHubView(model: cleanModel)
                .tabItem { Label(loc.t("tab.cleaning"), systemImage: "trash") }.tag(2)
            DiskView()
                .tabItem { Label(loc.t("tab.disk"), systemImage: "internaldrive") }.tag(3)
            UninstallView(model: uninstallModel)
                .tabItem { Label(loc.t("tab.uninstall"), systemImage: "xmark.bin.fill") }.tag(4)
            MaintenanceView()
                .tabItem { Label(loc.t("tab.maintenance"), systemImage: "wrench.and.screwdriver") }.tag(5)
            TweaksView()
                .tabItem { Label(loc.t("tab.tweaks"), systemImage: "slider.horizontal.3") }.tag(6)
            SystemInfoView()
                .tabItem { Label(loc.t("tab.system"), systemImage: "info.circle") }.tag(7)
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
