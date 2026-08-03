//
//  TweaksView.swift · MacTuner
//
import SwiftUI
import AppKit

// MARK: - Modèle : un réglage rapide (defaults ou assertion)

/// Un tweak booléen. La plupart écrivent une clé `defaults` puis relancent une app ;
/// « veille » (id "wake") est un cas spécial géré par KeepAwake.
struct QuickTweak: Identifiable {
    let id: String
    let name: LStr
    let desc: LStr
    let icon: String
    let section: Section
    // Réglage `defaults` (nil pour le cas spécial « veille »).
    var domain: String = ""
    var key: String = ""
    var restart: [String] = []   // apps à relancer après écriture

    enum Section: Int, CaseIterable, Identifiable {
        case session, finder, dock, other
        var id: Int { rawValue }
    }
}

enum TweaksEngine {
    /// Toutes les clés listées valent « faux » quand elles sont absentes, donc une
    /// lecture vide équivaut à l'état par défaut du système : pas de faux positif.
    static func read(_ t: QuickTweak) -> Bool {
        guard !t.domain.isEmpty else { return false }
        let out = Shell.run("/usr/bin/defaults", ["read", t.domain, t.key])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out == "1" || out.lowercased() == "true"
    }

    static func write(_ t: QuickTweak, _ on: Bool) {
        guard !t.domain.isEmpty else { return }
        Shell.run("/usr/bin/defaults", ["write", t.domain, t.key, "-bool", on ? "true" : "false"])
        for app in t.restart { Shell.runResult("/usr/bin/killall", [app]) }
    }
}

let quickTweaks: [QuickTweak] = [
    QuickTweak(id: "hidden", name: LStr("", ""), desc: LStr("", ""), icon: "eye.fill",
               section: .finder, domain: "com.apple.finder", key: "AppleShowAllFiles", restart: ["Finder"]),
    QuickTweak(id: "ext", name: LStr("", ""), desc: LStr("", ""), icon: "textformat.abc.dottedunderline",
               section: .finder, domain: "NSGlobalDomain", key: "AppleShowAllExtensions", restart: ["Finder"]),
    QuickTweak(id: "pathbar", name: LStr("", ""), desc: LStr("", ""), icon: "point.topleft.down.to.point.bottomright.curvepath",
               section: .finder, domain: "com.apple.finder", key: "ShowPathbar", restart: ["Finder"]),
    QuickTweak(id: "statusbar", name: LStr("", ""), desc: LStr("", ""), icon: "info.square",
               section: .finder, domain: "com.apple.finder", key: "ShowStatusBar", restart: ["Finder"]),
    QuickTweak(id: "foldersfirst", name: LStr("", ""), desc: LStr("", ""), icon: "folder.fill",
               section: .finder, domain: "com.apple.finder", key: "_FXSortFoldersFirst", restart: ["Finder"]),
    QuickTweak(id: "dockhide", name: LStr("", ""), desc: LStr("", ""), icon: "dock.rectangle",
               section: .dock, domain: "com.apple.dock", key: "autohide", restart: ["Dock"]),
    QuickTweak(id: "docknorecent", name: LStr("", ""), desc: LStr("", ""), icon: "clock.arrow.circlepath",
               section: .dock, domain: "com.apple.dock", key: "show-recents", restart: ["Dock"]),
    QuickTweak(id: "shadow", name: LStr("", ""), desc: LStr("", ""), icon: "camera.viewfinder",
               section: .other, domain: "com.apple.screencapture", key: "disable-shadow", restart: ["SystemUIServer"]),
    QuickTweak(id: "savepanel", name: LStr("", ""), desc: LStr("", ""), icon: "square.and.arrow.down",
               section: .other, domain: "NSGlobalDomain", key: "NSNavPanelExpandedStateForSaveMode"),
]

@MainActor
final class TweaksModel: ObservableObject {
    @Published var states: [String: Bool] = [:]
    @Published var loaded = false

    func load() {
        Task.detached(priority: .userInitiated) {
            var s = [String: Bool]()
            for t in quickTweaks { s[t.id] = TweaksEngine.read(t) }
            let final = s
            await MainActor.run { self.states = final; self.loaded = true }
        }
    }

    func toggle(_ t: QuickTweak, _ on: Bool) {
        states[t.id] = on
        Task.detached(priority: .userInitiated) { TweaksEngine.write(t, on) }
    }
}

// MARK: - Vue : Tweaks

struct TweaksView: View {
    @StateObject private var model = TweaksModel()
    @ObservedObject private var keepAwake = KeepAwake.shared
    @EnvironmentObject var loc: L10n

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 12)]

    /// Métadonnées d'affichage par id (les LStr du catalogue restent vides pour ne
    /// pas dupliquer : on lit les libellés depuis la table localisée).
    private func label(_ id: String) -> (String, String) {
        (loc.t("tweaks.\(id).name"), loc.t("tweaks.\(id).desc"))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "slider.horizontal.3", tint: MTColor.mac,
                      title: loc.t("tweaks.title"), subtitle: loc.t("tweaks.subtitle")) {
                Button { model.load() } label: {
                    Label(loc.t("common.refresh"), systemImage: "arrow.clockwise")
                }
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Session : la veille (cas spécial, pas un defaults).
                    section(loc.t("tweaks.sec.session"))
                    LazyVGrid(columns: columns, spacing: 12) { wakeCard }

                    ForEach(sectionsWithTweaks, id: \.0.id) { sec, tweaks in
                        section(sectionTitle(sec))
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(tweaks) { t in tweakCard(t) }
                        }
                    }
                }
                .tabContent()
            }
            .background(MTColor.fond)
        }
        .onAppear { if !model.loaded { model.load() } }
    }

    private var sectionsWithTweaks: [(QuickTweak.Section, [QuickTweak])] {
        let order: [QuickTweak.Section] = [.finder, .dock, .other]
        return order.compactMap { sec in
            let items = quickTweaks.filter { $0.section == sec }
            return items.isEmpty ? nil : (sec, items)
        }
    }
    private func sectionTitle(_ s: QuickTweak.Section) -> String {
        switch s {
        case .session: return loc.t("tweaks.sec.session")
        case .finder:  return loc.t("tweaks.sec.finder")
        case .dock:    return loc.t("tweaks.sec.dock")
        case .other:   return loc.t("tweaks.sec.other")
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private var wakeCard: some View {
        toggleCard(icon: keepAwake.active ? "sun.max.fill" : "moon.zzz",
                   tint: keepAwake.active ? MTColor.ambre : MTColor.mac,
                   name: loc.t("tweaks.wake.name"), desc: loc.t("tweaks.wake.desc"),
                   on: keepAwake.active) { _ in keepAwake.toggle() }
    }

    private func tweakCard(_ t: QuickTweak) -> some View {
        let (name, desc) = label(t.id)
        let on = model.states[t.id] ?? false
        return toggleCard(icon: t.icon, tint: on ? MTColor.mac : Color.secondary,
                          name: name, desc: desc, on: on) { model.toggle(t, $0) }
    }

    private func toggleCard(icon: String, tint: Color, name: String, desc: String,
                            on: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(desc).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { on }, set: set)).labelsHidden().toggleStyle(.switch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(on ? MTColor.bleu.opacity(0.4) : MTColor.ligne, lineWidth: 1))
    }
}
