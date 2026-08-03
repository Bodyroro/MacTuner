//
//  SystemExtras.swift · MacTuner
//
import Foundation
import IOKit
import IOKit.pwr_mgt
import Metal
import SwiftUI

// MARK: - Batterie (IOKit AppleSmartBattery, lecture seule)

enum BatteryHealth {
    struct Info {
        let present: Bool
        let cycles: Int
        let healthPct: Int
        let condition: String
        let chargePct: Int
    }

    private static func intProp(_ service: io_service_t, _ key: String) -> Int? {
        guard let v = IORegistryEntryCreateCFProperty(service, key as CFString,
                                                      kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return nil }
        return (v as? NSNumber)?.intValue
    }

    static func read() -> Info {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return Info(present: false, cycles: 0, healthPct: 0, condition: "", chargePct: 0)
        }
        defer { IOObjectRelease(service) }
        let cycles = intProp(service, "CycleCount") ?? 0
        let maxCap = intProp(service, "AppleRawMaxCapacity") ?? intProp(service, "MaxCapacity") ?? 0
        let designCap = intProp(service, "DesignCapacity") ?? 0
        let curCap = intProp(service, "AppleRawCurrentCapacity") ?? intProp(service, "CurrentCapacity") ?? 0
        guard designCap > 0 else {
            return Info(present: false, cycles: 0, healthPct: 0, condition: "", chargePct: 0)
        }
        let health = min(100, Int((Double(maxCap) / Double(designCap) * 100).rounded()))
        let charge = maxCap > 0 ? min(100, Int((Double(curCap) / Double(maxCap) * 100).rounded())) : 0
        let condition = health >= 80 ? T("battery.normal") : T("battery.service")
        return Info(present: true, cycles: cycles, healthPct: health,
                    condition: condition, chargePct: charge)
    }
}

// MARK: - Modèle du Mac (nom marketing, symbole, numéro de série)

enum HardwareInfo {
    /// Nom marketing (« Mac mini », « MacBook Pro »…) via system_profiler, lu une fois.
    static let modelName: String = {
        let out = Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType"])
        for line in out.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("Model Name:") {
                return l.replacingOccurrences(of: "Model Name:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return SysInfo.model
    }()

    /// Symbole SF représentant la famille du Mac (rendu façon Apple, sans photo).
    static var symbol: String {
        let n = modelName.lowercased()
        if n.contains("mac mini") || n.contains("macmini") { return "macmini.fill" }
        if n.contains("studio") { return "macstudio.fill" }
        if n.contains("macbook") { return "laptopcomputer" }
        if n.contains("imac") { return "desktopcomputer" }
        if n.contains("mac pro") { return "macpro.gen3.fill" }
        return "desktopcomputer"
    }

    /// Numéro de série via IOKit (IOPlatformExpertDevice), lu une fois.
    static let serial: String = {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("IOPlatformExpertDevice"))
        guard svc != 0 else { return "" }
        defer { IOObjectRelease(svc) }
        return (IORegistryEntryCreateCFProperty(svc, kIOPlatformSerialNumberKey as CFString,
                                                kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String) ?? ""
    }()

    /// Préchauffe les caches lents (system_profiler) hors du thread principal.
    static func warm() { _ = modelName; _ = serial; _ = GPUInfo.cores }
}

// MARK: - GPU (Metal + system_profiler)

enum GPUInfo {
    static let name: String = MTLCreateSystemDefaultDevice()?.name ?? "GPU"

    /// Nombre de cœurs GPU (Apple Silicon), lu une fois via system_profiler.
    static let cores: Int = {
        let out = Shell.run("/usr/sbin/system_profiler", ["SPDisplaysDataType"])
        for line in out.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("Total Number of Cores:") {
                return Int(l.replacingOccurrences(of: "Total Number of Cores:", with: "")
                    .trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }()
}

// MARK: - Empêcher la mise en veille (assertion d'alimentation IOKit)

@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    static let prefKey = "keepAwakeEnabled"
    @Published private(set) var active = false
    private var assertionID: IOPMAssertionID = 0

    func toggle() { if active { stop() } else { start() } }

    func start() {
        guard assertionID == 0 else { return }
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "MacTuner veille desactivee" as CFString, &id)
        if r == kIOReturnSuccess {
            assertionID = id
            active = true
            UserDefaults.standard.set(true, forKey: Self.prefKey)
        }
    }

    func stop() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
        active = false
        UserDefaults.standard.set(false, forKey: Self.prefKey)
    }

    /// Réapplique le choix de l'utilisateur au lancement de l'app (l'assertion
    /// d'alimentation ne survit pas à la fermeture du processus, on la recrée).
    func restore() {
        if UserDefaults.standard.bool(forKey: Self.prefKey) { start() }
    }
}
