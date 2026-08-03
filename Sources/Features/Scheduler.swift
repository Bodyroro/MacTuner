//
//  Scheduler.swift · MacTuner
//
import Foundation
import Darwin

// MARK: - Nettoyage planifié (LaunchAgent hebdomadaire)

enum Scheduler {
    static let label = "local.rodolphe.mactuner.cleanup"
    static var agentPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }
    static var binaryPath: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: agentPath) }

    /// Installe un agent qui relance MacTuner en mode `--clean-scheduled` chaque
    /// lundi à midi. Aucune fenêtre : le binaire nettoie puis quitte (voir init).
    static func enable() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(label)</string>
        <key>ProgramArguments</key><array>
        <string>\(binaryPath)</string><string>--clean-scheduled</string>
        </array>
        <key>StartCalendarInterval</key><dict>
        <key>Weekday</key><integer>1</integer><key>Hour</key><integer>12</integer>
        </dict>
        <key>ProcessType</key><string>Background</string>
        </dict></plist>
        """
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? plist.write(toFile: agentPath, atomically: true, encoding: .utf8)
        Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentPath])
    }

    static func disable() {
        Shell.runResult("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(atPath: agentPath)
    }

    /// Exécuté par l'agent : nettoie uniquement les catégories utilisateur sûres
    /// (régénérables, risque faible, jamais système ni éléments mis à la Corbeille).
    static func runScheduledCleanup() {
        let ids = Set(cleanCategories
            .filter { !$0.needsAdmin && $0.risk == .faible && !$0.removeItems }
            .map(\.id))
        let stats = CleanEngine.scan()
        _ = CleanEngine.clean(categoryIDs: ids, stats: stats)
    }
}
