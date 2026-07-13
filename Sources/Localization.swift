//
//  Localization.swift — Système de traduction FR / EN
//  Toutes les chaînes de l'interface passent par L10n.t("clé"). Aucun texte en dur.
//  Ajouter une langue = ajouter un cas à Lang + une colonne dans Strings.table.
//

import SwiftUI

enum Lang: String, CaseIterable, Identifiable {
    case fr, en
    var id: String { rawValue }
    var displayName: String { self == .fr ? "Français" : "English" }
    var flag: String { self == .fr ? "🇫🇷" : "🇬🇧" }
}

/// Source de vérité de la langue courante. Observable → l'UI se retraduit à chaud.
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published private(set) var lang: Lang

    static let storageKey = "appLanguage"
    var hasChosen: Bool { UserDefaults.standard.string(forKey: L10n.storageKey) != nil }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: L10n.storageKey),
           let l = Lang(rawValue: raw) {
            lang = l
        } else {
            let sys = Locale.current.language.languageCode?.identifier
            lang = (sys == "fr") ? .fr : .en
        }
    }

    func set(_ l: Lang) {
        UserDefaults.standard.set(l.rawValue, forKey: L10n.storageKey)
        lang = l
    }

    /// Traduction d'une clé. Repli sur le français puis sur la clé brute.
    func t(_ key: String) -> String {
        Strings.table[key]?[lang] ?? Strings.table[key]?[.fr] ?? key
    }

    /// Traduction avec arguments (ex. "%d désactivés").
    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

/// Raccourci global pour les contextes hors-vue (moteurs, catalogues).
func T(_ key: String) -> String { L10n.shared.t(key) }

/// Chaîne bilingue co-localisée avec la donnée (catalogues). Repli FR si EN vide.
struct LStr {
    let fr: String
    let en: String
    init(_ fr: String, _ en: String) { self.fr = fr; self.en = en }
    var current: String {
        let v = L10n.shared.lang == .en ? en : fr
        return v.isEmpty ? fr : v
    }
}
