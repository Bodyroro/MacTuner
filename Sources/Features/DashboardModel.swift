//
//  DashboardModel.swift · MacTuner
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

    private let sampler = SysSampler()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        fanCount = SMC.fanCount()
        startupOn = FanControl.startupEnabled
        tick()
        // Le mode voulu prime sur l'état réel : le SMC repasse en automatique à chaque
        // redémarrage, donc « pas forcé » ne veut pas dire « l'utilisateur veut auto ».
        let saved = FanControl.desiredRPM
        manualMode = FanControl.desiredManual || SMC.fanForced(0)
        if manualMode {
            targetRPM = saved > 0 ? saved : Double(snap.fanRPM)
            appliedRPM = targetRPM
            // Réglage perdu depuis la dernière session : on le renvoie au SMC au lieu
            // de laisser l'utilisateur le refaire à la main.
            restoreIfNeeded()
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        observeWake()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let o = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            wakeObserver = nil
        }
    }

    /// Le retour de veille remet souvent le ventilateur en automatique : on ré-affirme
    /// la consigne voulue, sans invite de mot de passe (règle sudoers en place).
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restoreIfNeeded() }
        }
    }

    /// Ré-applique en tâche de fond le réglage voulu s'il n'est plus effectif.
    private func restoreIfNeeded() {
        guard FanControl.desiredManual else { return }
        Task.detached {
            guard FanControl.restoreDesiredIfNeeded() else { return }
            await MainActor.run { self.appliedRPM = FanControl.desiredRPM }
        }
    }

    private func tick() {
        snap = sampler.sample()
        if !manualMode { targetRPM = Double(snap.fanRPM) }
    }

    func applyManual(_ on: Bool) {
        manualMode = on
        applying = true
        // Mémorise l'intention : c'est elle qui sera restaurée au prochain lancement.
        FanControl.desiredManual = on
        if on {
            let saved = FanControl.desiredRPM
            if saved > 0 { targetRPM = saved }
            FanControl.desiredRPM = targetRPM
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
        FanControl.forgetDesired()
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
        FanControl.desiredRPM = targetRPM
        FanControl.desiredManual = true
        Task.detached {
            FanControl.apply(index: 0, mode: 1, rpm: rpm)
            // Le démon de démarrage embarque la vitesse : sans ça, il continuerait
            // d'appliquer l'ANCIENNE consigne au prochain redémarrage.
            FanControl.refreshStartup(index: 0, rpm: rpm)
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
