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

/// LaunchAgent qui maintient l'anti-veille SANS MacTuner ouvert.
///
/// Une assertion `IOPMAssertion` ne vit que le temps du processus qui la crée :
/// dès que MacTuner quitte, la veille revient, et un redémarrage efface tout.
/// Pour que le réglage soit réellement permanent, on installe un agent utilisateur
/// qui lance `/usr/bin/caffeinate -i` — exactement la même assertion, tenue par un
/// processus que launchd relance au login et maintient en vie (`KeepAlive`).
/// Aucun droit administrateur, entièrement réversible : l'agent est supprimé dès
/// que l'utilisateur réactive la veille.
enum KeepAwakeAgent {
    static let label = "local.rodolphe.mactuner.keepawake"
    static var plistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }
    static var installed: Bool { FileManager.default.fileExists(atPath: plistPath) }

    private static let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array><string>/usr/bin/caffeinate</string><string>-i</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>ProcessType</key><string>Background</string>
        </dict>
        </plist>
        """

    static func install() {
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard (try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)) != nil else { return }
        Shell.runResult("/bin/launchctl", ["bootout", "\(LaunchCtl.domain)/\(label)"])
        Shell.runResult("/bin/launchctl", ["bootstrap", LaunchCtl.domain, plistPath])
    }

    static func remove() {
        guard installed else { return }
        Shell.runResult("/bin/launchctl", ["bootout", "\(LaunchCtl.domain)/\(label)"])
        try? FileManager.default.removeItem(atPath: plistPath)
    }
}

@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    static let prefKey = "keepAwakeEnabled"
    @Published private(set) var active = false
    private var assertionID: IOPMAssertionID = 0

    func toggle() { if active { stop() } else { start() } }

    func start() {
        // L'agent `caffeinate` est ce qui rend le réglage permanent : il survit à la
        // fermeture de MacTuner, à la veille et au redémarrage. L'assertion locale
        // ci-dessous ne sert qu'à rendre l'effet immédiat, sans attendre launchd.
        KeepAwakeAgent.install()
        UserDefaults.standard.set(true, forKey: Self.prefKey)
        active = true
        guard assertionID == 0 else { return }
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "MacTuner veille desactivee" as CFString, &id)
        if r == kIOReturnSuccess { assertionID = id }
    }

    func stop() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
        KeepAwakeAgent.remove()
        active = false
        UserDefaults.standard.set(false, forKey: Self.prefKey)
    }

    /// Réaligne l'app sur l'état réel au lancement. L'agent `caffeinate` fait foi :
    /// s'il est en place, l'anti-veille est déjà active, on le reflète simplement.
    /// S'il manque alors que l'utilisateur l'avait demandé (préférences restaurées,
    /// agent supprimé à la main), on le réinstalle.
    func restore() {
        let wanted = UserDefaults.standard.bool(forKey: Self.prefKey)
        if wanted || KeepAwakeAgent.installed {
            start()
        } else {
            active = false
        }
    }
}
