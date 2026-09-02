//
//  FeaturesView.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vues : fonctionnalités (grille de cartes)

/// Pastille colorée compacte (risque, admin, état).
private func chip(_ text: String, _ color: Color) -> some View {
    Text(text)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.16))
        .foregroundStyle(color)
        .clipShape(Capsule())
}

struct TweakCard: View {
    let tweak: Tweak
    @ObservedObject var model: TunerModel
    @EnvironmentObject var loc: L10n

    private var isDisabled: Bool { model.isDisabled(tweak) }

    /// Drapeau posé, mais des processus tournent quand même : macOS les réveille
    /// à la demande malgré le drapeau, et SIP interdit de les arrêter. Un
    /// redémarrage n'y change rien — on le signale sans jamais bloquer l'action.
    private var stillRunningDespiteFlag: Bool {
        (model.itemStates[tweak.id] ?? []).contains(where: \.stillRunning)
    }
    /// Réglage encore actif dont la part « agents » restera sans effet tant que
    /// SIP est activé.
    private var willBeLimited: Bool { !isDisabled && tweak.limitedBySIP }
    /// « Effet partiel » quand une préférence coupe quand même la fonction,
    /// « SIP requis » quand la fiche n'agit que sur des agents.
    private var limitChipKey: String {
        tweak.hasFunctionalSwitch ? "feat.partial.chip" : "feat.reboot.chip"
    }

    /// Bordure : rouge si désactivé et effectif, ambre si l'effet est bridé par SIP.
    private var borderColor: Color {
        if stillRunningDespiteFlag { return MTColor.ambre.opacity(0.45) }
        if isDisabled { return MTColor.rouge.opacity(0.30) }
        return MTColor.ligne
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: tweak.icon)
                    .font(.body)
                    .foregroundStyle(isDisabled ? Color.secondary : MTColor.mac)
                    .frame(width: 20, alignment: .leading)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !isDisabled },
                    set: { newActive in
                        if newActive { model.setTweak(tweak, disabled: false) }
                        else { model.pendingDisable = tweak }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(model.busy)
            }
            Text(tweak.name.current)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(tweak.affects.prefix(2).map(\.current).joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Circle().fill(tweak.risk.color).frame(width: 6, height: 6)
                if tweak.needsAdmin {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.purple)
                }
                if willBeLimited {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9)).foregroundStyle(MTColor.ambre)
                }
                Spacer(minLength: 0)
                if stillRunningDespiteFlag {
                    Text(loc.t(limitChipKey))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tweak.hasFunctionalSwitch ? MTColor.bleu : MTColor.ambre)
                } else if isDisabled {
                    Text(loc.t("common.disabled"))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(MTColor.rouge)
                } else if let u = model.tweakUsage[tweak.id], u.procs > 0 {
                    Text(humanBytes(u.rssBytes))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(MTColor.bleu)
                }
            }
            .padding(.top, 1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(borderColor, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.detailTweak = tweak }
        .animation(.easeInOut(duration: 0.2), value: isDisabled)
    }
}

/// Fiche complète d'une fonctionnalité : rôle, impacts, réactivation et
/// sous-processus désactivables un par un.
struct TweakDetailSheet: View {
    let tweak: Tweak
    @ObservedObject var model: TunerModel
    @EnvironmentObject var loc: L10n

    private var isDisabled: Bool { model.isDisabled(tweak) }
    private var items: [DetailItem] { model.itemStates[tweak.id] ?? [] }
    /// Drapeau posé, processus quand même relancé à la demande par macOS.
    /// SIP refuse `bootout` : ni le drapeau ni un redémarrage ne l'arrêteront.
    private var stillRunningDespiteFlag: Bool { items.contains(where: \.stillRunning) }
    /// Encore actif, et dont la part « agents » restera sans effet sous SIP.
    private var willBeLimited: Bool { !isDisabled && tweak.limitedBySIP }
    /// Même distinction que sur la carte : partiel si une préférence agit malgré tout.
    private var limitChipKey: String {
        tweak.hasFunctionalSwitch ? "feat.partial.chip" : "feat.reboot.chip"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: tweak.icon).font(.title2).foregroundStyle(MTColor.mac)
                Text(tweak.name.current).font(.title3.weight(.semibold))
                chip(tweak.risk.label.current, tweak.risk.color)
                if tweak.needsAdmin { chip(loc.t("common.admin"), .purple) }
                if stillRunningDespiteFlag || willBeLimited {
                    chip(loc.t(limitChipKey),
                         tweak.hasFunctionalSwitch ? MTColor.bleu : MTColor.ambre)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !isDisabled },
                    set: { newActive in
                        if newActive { model.setTweak(tweak, disabled: false) }
                        else { model.pendingDisable = tweak }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.busy)
            }

            if stillRunningDespiteFlag || willBeLimited {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(MTColor.ambre)
                    Text(loc.t(stillRunningDespiteFlag ? "feat.reboot.pending" : "feat.reboot.will"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MTColor.ambre.opacity(0.10)))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    detail(icon: "info.circle.fill", color: .blue,
                           title: loc.t("feat.what"), text: tweak.what.current)
                    detail(icon: "app.badge.fill", color: .indigo,
                           title: loc.t("feat.affects"),
                           text: tweak.affects.map(\.current).joined(separator: " · "))
                    detail(icon: "exclamationmark.triangle.fill", color: MTColor.ambre,
                           title: loc.t("feat.breaks"), text: tweak.breaks.current)
                    detail(icon: "arrow.counterclockwise.circle.fill", color: .teal,
                           title: loc.t("feat.reenable"), text: tweak.reenable.current)

                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            if items.contains(where: { $0.agentLabel != nil }) {
                                Text(loc.t("feat.subprocesses"))
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            ForEach(items) { item in
                                HStack(spacing: 6) {
                                    // Vert : actif · Ambre : désactivé mais encore en
                                    // mémoire (effet au redémarrage) · Rouge : arrêté.
                                    Circle()
                                        .fill(item.stillRunning ? MTColor.ambre
                                              : (item.disabled ? MTColor.rouge : Color.green))
                                        .frame(width: 7, height: 7)
                                    Text(item.id).font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    if let info = item.info {
                                        Text(info)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(MTColor.bleu)
                                    }
                                    if let label = item.agentLabel {
                                        Toggle("", isOn: Binding(
                                            get: { !item.disabled },
                                            set: { model.setAgent(label, disabled: !$0) }
                                        ))
                                        .toggleStyle(.switch)
                                        .controlSize(.mini)
                                        .labelsHidden()
                                        .disabled(model.busy)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }

            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(loc.t("common.close")) { model.detailTweak = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 540)
    }

    private func detail(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FeaturesView: View {
    @ObservedObject var model: TunerModel
    @EnvironmentObject var loc: L10n

    /// Mode d'emploi de la désactivation de SIP : la seule manière d'arrêter
    /// réellement les agents Apple relancés à la demande.
    /// State(initialValue:) direct : la toolchain CLI n'a pas la macro @State.
    private var showSIPHelp = State(initialValue: false)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var filteredTweaks: [Tweak] {
        let q = model.searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allTweaks }
        return allTweaks.filter { $0.searchText.contains(q) }
    }

    private func groupRank(_ t: Tweak) -> Int { groupOrder.firstIndex(of: t.group) ?? 0 }

    /// Réglages `defaults` et commandes admin uniquement : effet immédiat et
    /// complet, SIP sans influence. Ce sont les seuls qui tiennent toutes leurs
    /// promesses sur un Mac protégé.
    private var sipCompatibleTweaks: [Tweak] {
        filteredTweaks.filter { !$0.usesAgents }
            .sorted { groupRank($0) < groupRank($1) }
    }
    /// Coupent la fonction par une préférence ET visent des agents launchd. Sous
    /// SIP la préférence agit — donc la fonction s'arrête — mais les agents,
    /// eux, continuent d'être réveillés à la demande. Effet réel, mais partiel.
    private var partialTweaks: [Tweak] {
        filteredTweaks.filter { $0.usesAgents && $0.hasFunctionalSwitch }
            .sorted { groupRank($0) < groupRank($1) }
    }
    /// N'agissent QUE sur des agents launchd, sans interrupteur fonctionnel de
    /// repli. Sous SIP, poser leur drapeau ne change rien d'observable : macOS
    /// réveille ces agents à la demande et interdit de les arrêter.
    private var sipRequiredTweaks: [Tweak] {
        filteredTweaks.filter { $0.usesAgents && !$0.hasFunctionalSwitch }
            .sorted { groupRank($0) < groupRank($1) }
    }

    private var sipBanner: some View {
        let accent = SIP.enabled ? MTColor.ambre : Color.green
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3)
            Image(systemName: SIP.enabled ? "lock.shield.fill" : "lock.open.fill")
                .foregroundStyle(accent)
            Text(loc.t(SIP.enabled ? "feat.sip.on" : "feat.sip.off"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(MTColor.ligne, lineWidth: 1))
    }

    private func categorySection(title: String, desc: String, accent: Color,
                                 icon: String, tweaks: [Tweak]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        Text(loc.t("feat.count", tweaks.count))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.22)))
                            .foregroundStyle(accent)
                    }
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(tweaks) { tweak in
                    TweakCard(tweak: tweak, model: model)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(accent.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(accent.opacity(0.28), lineWidth: 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "switch.2", title: loc.t("tab.features"),
                      subtitle: loc.t("feat.footer", model.disabledCount, allTweaks.count)) {
                TextField(loc.t("feat.search"), text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sipBanner
                    if !sipCompatibleTweaks.isEmpty {
                        categorySection(
                            title: loc.t("feat.sip.compatible.title"),
                            desc: loc.t("feat.sip.compatible.desc"),
                            accent: .green, icon: "checkmark.seal.fill",
                            tweaks: sipCompatibleTweaks)
                    }
                    if !partialTweaks.isEmpty {
                        categorySection(
                            title: loc.t(SIP.enabled ? "feat.sip.partial.title"
                                                     : "feat.sip.required.title.off"),
                            desc: loc.t(SIP.enabled ? "feat.sip.partial.desc.on"
                                                    : "feat.sip.required.desc.off"),
                            accent: SIP.enabled ? MTColor.bleu : .green,
                            icon: "checkmark.shield.fill", tweaks: partialTweaks)
                    }
                    if !sipRequiredTweaks.isEmpty {
                        categorySection(
                            title: loc.t(SIP.enabled ? "feat.sip.required.title"
                                                     : "feat.sip.required.title.off"),
                            desc: loc.t(SIP.enabled ? "feat.sip.required.desc.on"
                                                    : "feat.sip.required.desc.off"),
                            accent: SIP.enabled ? MTColor.ambre : .green,
                            icon: "lock.shield", tweaks: sipRequiredTweaks)
                    }
                }
                .tabContent()
            }
            .background(MTColor.fond)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if model.driftCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(.red)
                        Text(loc.t("feat.drift", model.driftCount))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(loc.t("feat.reapply")) { model.reapplyDrift() }
                            .controlSize(.small)
                            .disabled(model.busy)
                    }
                }
                // Des agents tournent malgré leur drapeau. Ne proposer un redémarrage
                // serait mentir : macOS les réveille à la demande, drapeau ou pas, et
                // un boot à froid les ramène à l'identique. La seule sortie réelle est
                // de désactiver SIP, donc c'est ça qu'on documente.
                if model.stillRunningDespiteFlagCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill").foregroundStyle(MTColor.ambre)
                        Text(loc.t("feat.reboot", model.stillRunningDespiteFlagCount))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(loc.t("feat.sip.howto")) { showSIPHelp.wrappedValue = true }
                            .controlSize(.small)
                    }
                }
                HStack {
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button(loc.t("common.refresh")) { model.refresh() }.disabled(model.busy)
                    Button(loc.t("common.restoreAll")) { model.restoreAll() }.disabled(model.busy)
                }
            }
            .padding(12)
        }
        .onAppear { if model.tweakDisabled.isEmpty { model.refresh() } }
        .sheet(item: $model.detailTweak) { tweak in
            TweakDetailSheet(tweak: tweak, model: model).environmentObject(loc)
        }
        .alert(loc.t("feat.sip.howto.title"), isPresented: showSIPHelp.projectedValue) {
            Button(loc.t("common.close"), role: .cancel) { }
        } message: {
            Text(loc.t("feat.sip.howto.body"))
        }
        .alert(
            loc.t("feat.confirm", model.pendingDisable?.name.current ?? ""),
            isPresented: Binding(
                get: { model.pendingDisable != nil },
                set: { if !$0 { model.pendingDisable = nil } }
            ),
            presenting: model.pendingDisable
        ) { tweak in
            Button(loc.t("feat.confirm.ok"), role: .destructive) {
                model.setTweak(tweak, disabled: true)
                model.pendingDisable = nil
            }
            Button(loc.t("common.cancel"), role: .cancel) { model.pendingDisable = nil }
        } message: { tweak in
            // L'avertissement « effet au redémarrage » n'a de sens que pour les
            // agents launchd sous SIP : un réglage `defaults` prend effet tout de suite.
            Text(tweak.limitedBySIP
                 ? tweak.breaks.current + "\n\n" + loc.t("feat.confirm.reboot")
                 : tweak.breaks.current)
        }
    }
}
