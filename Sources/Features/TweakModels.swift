//
//  TweakModels.swift · MacTuner
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
    /// Agents launchd du domaine `gui/<uid>` : /System/Library/LaunchAgents.
    /// Désactivables sans mot de passe.
    case agents([String])
    /// Démons launchd du domaine `system` : /System/Library/LaunchDaemons.
    /// Ils tournent en root, hors session, et ne sont donc PAS couverts par le
    /// domaine `gui` — c'est pour eux que le mode helper `--launchd-system` existe.
    /// Chaque label doit figurer dans `SystemDaemons.allowed`, liste blanche
    /// compilée : le helper root refuse tout label absent de cette liste.
    case systemDaemons([String])
    case defaultsKey(domain: String, key: String, disabledValue: DefaultsKind,
                     enabledValue: DefaultsKind?, killall: String?)
    /// Comme `defaultsKey`, mais dans le domaine « par machine » (ByHost),
    /// c'est-à-dire `defaults -currentHost`. macOS y range les réglages propres
    /// à CET ordinateur — Handoff notamment. Une écriture sans `-currentHost`
    /// atterrit dans un autre fichier et se retrouve tout simplement ignorée,
    /// d'où ce cas distinct plutôt qu'un drapeau ajouté au cas précédent.
    case defaultsHostKey(domain: String, key: String, disabledValue: DefaultsKind,
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

    /// Exige des privilèges root : commande admin, ou démon du domaine `system`.
    var needsAdmin: Bool {
        mechanisms.contains {
            switch $0 {
            case .admin, .systemDaemons: return true
            default: return false
            }
        }
    }
    /// Repose sur au moins un démon système (domaine `system`, root requis).
    var usesSystemDaemons: Bool {
        mechanisms.contains { if case .systemDaemons = $0 { return true } else { return false } }
    }
    /// Vrai si la fonctionnalité repose sur des agents launchd Apple.
    ///
    /// Ce que `launchctl disable` fait vraiment, mesuré sur macOS 26/27 : il écrit
    /// un drapeau persistant, et c'est tout. Ce drapeau n'empêche que le démarrage
    /// automatique (`RunAtLoad`, `KeepAlive`). Or les agents Apple d'aujourd'hui
    /// n'utilisent quasiment plus ces clés : ils déclarent des `MachServices` et
    /// sont réveillés À LA DEMANDE par le premier client XPC qui les appelle.
    /// launchd honore cette demande MÊME si le drapeau « disabled » est posé.
    ///
    /// Conséquence : sur un Mac où 73 agents portaient le drapeau, 40 tournaient
    /// quand même après un redémarrage à froid, avec pour motif de lancement
    /// `ipc (mach)` ou `xpc event` — donc réveillés après le boot, drapeau en
    /// place. Un `launchctl kickstart` sur un agent désactivé ET arrêté le démarre
    /// sans la moindre erreur. Le redémarrage ne change donc rien.
    ///
    /// Et SIP interdit `launchctl bootout` (« Operation not permitted while System
    /// Integrity Protection is engaged », code 150) : on ne peut pas non plus les
    /// arrêter après coup. Les deux portes sont fermées.
    ///
    /// Le seul levier qui fonctionne avec SIP activé, c'est de couper la FONCTION
    /// (mécanismes `.defaultsKey` et `.admin`) : sans client pour les solliciter,
    /// les agents ne sont plus réveillés et s'éteignent d'eux-mêmes.
    var usesAgents: Bool {
        mechanisms.contains {
            switch $0 {
            case .agents, .systemDaemons: return true
            default: return false
            }
        }
    }
    /// Vrai si la fiche coupe aussi la fonction elle-même (préférence ou commande
    /// admin), et pas seulement les agents launchd. Ces mécanismes-là s'appliquent
    /// réellement, SIP activé ou non.
    var hasFunctionalSwitch: Bool {
        mechanisms.contains {
            switch $0 {
            case .defaultsKey, .defaultsHostKey, .admin: return true
            default: return false
            }
        }
    }
    /// Avec SIP activé, la part « agents launchd » de cette fiche est posée mais
    /// reste sans effet réel : macOS relancera les agents à la demande. Seule la
    /// désactivation de SIP depuis la Recovery les arrête pour de bon.
    var limitedBySIP: Bool { usesAgents && SIP.enabled }
    /// Fiche dont TOUT l'effet repose sur des agents launchd : avec SIP activé,
    /// elle n'a aucun levier fonctionnel de repli, donc aucun effet garanti.
    var sipOnlyEffect: Bool { limitedBySIP && !hasFunctionalSwitch }
    /// Texte concaténé pour la recherche (les deux langues).
    var searchText: String {
        (name.fr + " " + name.en + " " + what.fr + " " + what.en + " "
         + breaks.fr + " " + breaks.en + " "
         + affects.map { $0.fr + " " + $0.en }.joined(separator: " ")).lowercased()
    }
}

struct DetailItem: Identifiable {
    let id: String
    /// Le réglage est enregistré comme désactivé (drapeau launchd, clé `defaults`,
    /// commande admin). C'est l'état PERSISTANT : il survit au redémarrage.
    let disabled: Bool
    /// Le processus tourne encore malgré le drapeau. Vrai typiquement sous SIP,
    /// où `bootout` est refusé : désactivé, mais effectif au prochain redémarrage.
    let stillRunning: Bool
    /// Consommation mesurée (RAM/CPU) si le service tourne actuellement.
    let info: String?
    /// Label de l'agent launchd si cet item est un sous-processus togglable individuellement.
    let agentLabel: String?

    init(id: String, disabled: Bool, stillRunning: Bool = false,
         info: String? = nil, agentLabel: String? = nil) {
        self.id = id
        self.disabled = disabled
        self.stillRunning = stillRunning
        self.info = info
        self.agentLabel = agentLabel
    }
    /// Désactivé ET arrêté : plus rien ne tourne.
    var fullyOff: Bool { disabled && !stillRunning }
}
