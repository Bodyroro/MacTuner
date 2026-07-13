//
//  UninstallModels.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Modèle : désinstallation

enum TargetKind { case app, cli, dotfile }

struct InstalledApp: Identifiable {
    let id: String        // chemin du bundle (.app) ou du binaire (CLI)
    let name: String
    let path: String
    let bundleID: String  // vide pour un outil CLI
    let bytes: Int64
    var kind: TargetKind = .app
    /// Binaires supplémentaires (alias) regroupés sous cet outil (ex. « mo » sous « mole »).
    var extraExecutables: [String] = []
    var aliases: [String] = []
    var isApple: Bool { bundleID.hasPrefix("com.apple.") }
    var isCLI: Bool { kind == .cli }
}

struct Residue: Identifiable {
    enum Kind: String {
        case appBundle = "Application"
        case preferences = "Préférences"
        case appSupport = "Support d'application"
        case caches = "Caches"
        case container = "Conteneur (sandbox)"
        case groupContainer = "Conteneur de groupe"
        case savedState = "État de fenêtres"
        case logs = "Journaux"
        case httpStorage = "Stockage HTTP / cookies"
        case webkit = "Données WebKit"
        case scripts = "Scripts d'application"
        case launchAgent = "Agent de lancement"
        case launchDaemon = "Démon de lancement (système)"
        case helper = "Outil d'assistance privilégié"
        case loginItem = "Ouverture à la connexion"
        case executable = "Exécutable / lien"
        case config = "Configuration"
        case data = "Données du programme"

        /// Libellé localisé (clé "res.<case>").
        var label: String {
            switch self {
            case .appBundle: return T("res.appBundle")
            case .preferences: return T("res.preferences")
            case .appSupport: return T("res.appSupport")
            case .caches: return T("res.caches")
            case .container: return T("res.container")
            case .groupContainer: return T("res.groupContainer")
            case .savedState: return T("res.savedState")
            case .logs: return T("res.logs")
            case .httpStorage: return T("res.httpStorage")
            case .webkit: return T("res.webkit")
            case .scripts: return T("res.scripts")
            case .launchAgent: return T("res.launchAgent")
            case .launchDaemon: return T("res.launchDaemon")
            case .helper: return T("res.helper")
            case .loginItem: return T("res.loginItem")
            case .executable: return T("res.executable")
            case .config: return T("res.config")
            case .data: return T("res.data")
            }
        }
    }
    let id: String
    let kind: Kind
    let path: String
    let bytes: Int64
    let system: Bool     // hors dossier personnel → suppression admin
    let highConfidence: Bool
}

func nsIcon(_ path: String) -> NSImage {
    NSWorkspace.shared.icon(forFile: path)
}

func humanBytes(_ b: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    // Sans ça, zéro s'affiche en toutes lettres (« Zero KB ») dans les tuiles.
    f.allowsNonnumericFormatting = false
    return f.string(fromByteCount: b)
}

func humanCPU(_ s: Double) -> String {
    if s < 1 { return "< 1 s" }
    if s < 60 { return String(format: "%.0f s", s) }
    if s < 3600 { return String(format: "%.0f min", s / 60) }
    return String(format: "%.1f h", s / 3600)
}

