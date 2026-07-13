//
//  MacTunerApp.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Racine

final class TabSelection: ObservableObject {
    @Published var sel: Int
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
            CleanView(model: cleanModel)
                .tabItem { Label(loc.t("tab.cleaning"), systemImage: "trash") }.tag(2)
            UninstallView(model: uninstallModel)
                .tabItem { Label(loc.t("tab.uninstall"), systemImage: "xmark.bin.fill") }.tag(3)
            MaintenanceView()
                .tabItem { Label(loc.t("tab.maintenance"), systemImage: "wrench.and.screwdriver") }.tag(4)
            LogView()
                .tabItem { Label(loc.t("tab.log"), systemImage: "list.bullet.rectangle") }.tag(5)
            GainsView(tuner: tunerModel, clean: cleanModel, uninstall: uninstallModel)
                .tabItem { Label(loc.t("tab.gains"), systemImage: "speedometer") }.tag(6)
            SettingsView(perm: permModel)
                .tabItem { Label(loc.t("tab.settings"), systemImage: "gearshape") }.tag(7)
            GuideView()
                .tabItem { Label(loc.t("tab.guide"), systemImage: "questionmark.circle") }.tag(8)
        }
        .frame(minWidth: 1240, minHeight: 760)
        .buttonStyle(DarkButton())
        // Encre de nuit derrière la bande d'onglets et les en-têtes : sans ça,
        // ces zones affichent le gris système (le fameux gris-marron).
        .background(MTColor.nuit.ignoresSafeArea())
        .toolbarBackground(MTColor.nuit, for: .windowToolbar)
        .navigationTitle("MacTuner — \(SysCompat.osName)")
        .toolbar {
            ToolbarItem {
                Button {
                    permModel.recheckFDA()
                    permModel.showSheet = true
                } label: {
                    Label(loc.t("set.auth"),
                          systemImage: permModel.fda ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(permModel.fda ? Color.green : MTColor.ambre)
                }
                .help(loc.t("set.auth"))
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $permModel.showSheet) {
            OnboardingView(model: permModel).environmentObject(loc)
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
        // Réaligne l'agent de ré-application sur l'état voulu (migration de
        // format, fichiers supprimés à la main…). Sans effet si rien n'a changé.
        Task.detached(priority: .background) { ReapplyAgent.sync() }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(L10n.shared)
                // Identité visuelle du site : encre de nuit, sombre en permanence.
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1300, height: 820)
        .windowResizability(.contentMinSize)
    }
}
