//
//  TweakModels.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Modèle : fonctionnalités

enum Risk {
    case faible, moyen, eleve

    var color: Color {
        switch self {
        case .faible: return .green
        case .moyen: return MTColor.ambre
        case .eleve: return MTColor.rouge
        }
    }
    var label: LStr {
        switch self {
        case .faible: return LStr("Risque faible", "Low risk")
        case .moyen:  return LStr("Risque moyen", "Medium risk")
        case .eleve:  return LStr("Risque élevé", "High risk")
        }
    }
}

enum TweakGroup: CaseIterable {
    case assistant, privacy, icloud, media, ui, system
    var name: LStr {
        switch self {
        case .assistant: return LStr("Assistant & suggestions", "Assistant & suggestions")
        case .privacy:   return LStr("Confidentialité & télémétrie", "Privacy & telemetry")
        case .icloud:    return LStr("iCloud & Continuité", "iCloud & Continuity")
        case .media:     return LStr("Médias & apps intégrées", "Media & built-in apps")
        case .ui:        return LStr("Interface & confort", "Interface & comfort")
        case .system:    return LStr("Système (mot de passe admin requis)", "System (admin password required)")
        }
    }
}

enum DefaultsKind {
    case bool(Bool), float(Double), int(Int), string(String)

    var writeArgs: [String] {
        switch self {
        case .bool(let v):   return ["-bool", v ? "true" : "false"]
        case .float(let v):  return ["-float", "\(v)"]
        case .int(let v):    return ["-int", "\(v)"]
        case .string(let v): return ["-string", v]
        }
    }

    var readForm: String {
        switch self {
        case .bool(let v):   return v ? "1" : "0"
        case .float(let v):  return "\(v)"
        case .int(let v):    return "\(v)"
        case .string(let v): return v
        }
    }
}

enum Mechanism {
    case agents([String])
    case defaultsKey(domain: String, key: String, disabledValue: DefaultsKind,
                     enabledValue: DefaultsKind?, killall: String?)
    case admin(label: String, disableCmd: String, enableCmd: String,
               checkCmd: String, disabledMarker: String)
}

struct Tweak: Identifiable {
    let id: String
    let name: LStr
    let icon: String
    let group: TweakGroup
    /// Ce que fait la fonctionnalité.
    let what: LStr
    /// Apps et fonctions concernées (affiché en ligne « Concerne »).
    let affects: [LStr]
    /// Ce qui casse ou change si on désactive.
    let breaks: LStr
    /// Ce qui se passe quand on réactive (coût, délai, effets).
    let reenable: LStr
    let risk: Risk
    let mechanisms: [Mechanism]

    var needsAdmin: Bool {
        mechanisms.contains { if case .admin = $0 { return true } else { return false } }
    }
    /// Vrai si la fonctionnalité repose sur l'arrêt d'un agent launchd Apple.
    /// Ces agents ne peuvent pas être stoppés tant que SIP est activé
    /// (`launchctl bootout` renvoie le code 150) : l'effet réel exige de
    /// désactiver SIP. Les tweaks purement `defaults`/`admin` en sont exempts.
    var requiresSIPDisabled: Bool {
        mechanisms.contains { if case .agents = $0 { return true } else { return false } }
    }
    /// Texte concaténé pour la recherche (les deux langues).
    var searchText: String {
        (name.fr + " " + name.en + " " + what.fr + " " + what.en + " "
         + breaks.fr + " " + breaks.en + " "
         + affects.map { $0.fr + " " + $0.en }.joined(separator: " ")).lowercased()
    }
}

struct DetailItem: Identifiable {
    let id: String
    let disabled: Bool
    /// Consommation mesurée (RAM/CPU) si le service tourne actuellement.
    let info: String?
    /// Label de l'agent launchd si cet item est un sous-processus togglable individuellement.
    let agentLabel: String?
}
