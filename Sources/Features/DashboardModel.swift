//
//  DashboardModel.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Dashboard : modèle temps réel

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snap = SysSnapshot()
    @Published var fanCount = 0
    @Published var targetRPM: Double = 0
    @Published var manualMode = false
    @Published var startupOn = false
    @Published var applying = false
    /// Dernière vitesse réellement envoyée au SMC : le bouton Valider ne
    /// s'active que si la cible s'en écarte.
    @Published var appliedRPM: Double = 0

    private static let customKey = "fanCustomRPM"

    private let sampler = SysSampler()
    private var timer: Timer?

    func start() {
        fanCount = SMC.fanCount()
        manualMode = SMC.fanForced(0)
        startupOn = FanControl.startupEnabled
        tick()
        if manualMode {
            // Restaure la vitesse personnalisée validée précédemment.
            let saved = UserDefaults.standard.double(forKey: Self.customKey)
            targetRPM = saved > 0 ? saved : Double(snap.fanRPM)
            appliedRPM = targetRPM
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        snap = sampler.sample()
        if !manualMode { targetRPM = Double(snap.fanRPM) }
    }

    func applyManual(_ on: Bool) {
        manualMode = on
        applying = true
        if on {
            let saved = UserDefaults.standard.double(forKey: Self.customKey)
            if saved > 0 { targetRPM = saved }
        } else {
            // Retour au contrôle système : on retire aussi l'éventuel override de
            // démarrage, sinon macOS reforcerait la vitesse au prochain boot.
            startupOn = false
            appliedRPM = 0
        }
        let rpm = Float(targetRPM)
        Task.detached {
            // Première activation : installer l'autorisation persistante (un mot de
            // passe unique) pour que les changements de vitesse suivants soient muets.
            if on && !FanControl.authInstalled { FanControl.installAuth() }
            if on {
                FanControl.apply(index: 0, mode: 1, rpm: rpm)
            } else {
                FanControl.setAuto(index: 0)          // rend la main au thermal manager
                if FanControl.startupEnabled { FanControl.disableStartup() }
            }
            await MainActor.run {
                if on { self.appliedRPM = Double(rpm) }
                self.applying = false
            }
        }
    }

    /// Remise du ventilateur à l'état d'usine : contrôle automatique, sans override
    /// de démarrage ni vitesse personnalisée mémorisée.
    func resetFanToDefault() {
        manualMode = false
        startupOn = false
        appliedRPM = 0
        UserDefaults.standard.removeObject(forKey: Self.customKey)
        Task.detached {
            FanControl.setAuto(index: 0)
            if FanControl.startupEnabled { FanControl.disableStartup() }
            await MainActor.run { self.targetRPM = Double(self.snap.fanRPM) }
        }
    }

    /// Envoie la cible au SMC et la mémorise comme vitesse personnalisée.
    func commitRPM() {
        guard manualMode else { return }
        applying = true
        let rpm = Float(targetRPM)
        UserDefaults.standard.set(targetRPM, forKey: Self.customKey)
        Task.detached {
            FanControl.apply(index: 0, mode: 1, rpm: rpm)
            await MainActor.run {
                self.appliedRPM = Double(rpm)
                self.applying = false
            }
        }
    }

    // MARK: Test de débit

    @Published var speedTesting = false
    @Published var speedMbps: Double?

    /// Mesure réelle du débit descendant : téléchargement de 25 Mo depuis
    /// l'endpoint de test de Cloudflare, converti en Mbit/s.
    func runSpeedTest() {
        guard !speedTesting else { return }
        speedTesting = true
        speedMbps = nil
        Task.detached {
            func measure() async -> Double? {
                guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")
                else { return nil }
                var req = URLRequest(url: url)
                req.timeoutInterval = 20
                req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let start = CFAbsoluteTimeGetCurrent()
                guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
                let dt = CFAbsoluteTimeGetCurrent() - start
                guard dt > 0, !data.isEmpty else { return nil }
                return Double(data.count) * 8 / dt / 1_000_000
            }
            let mbps = await measure()
            await MainActor.run {
                self.speedMbps = mbps
                self.speedTesting = false
            }
        }
    }

    func toggleStartup(_ on: Bool) {
        startupOn = on
        let rpm = Float(targetRPM)
        Task.detached {
            if on { FanControl.enableStartup(index: 0, rpm: rpm) }
            else  { FanControl.disableStartup() }
            await MainActor.run { self.startupOn = FanControl.startupEnabled }
        }
    }
}

