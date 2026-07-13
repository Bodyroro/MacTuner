//
//  FeaturesView.swift — MacTuner
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

    /// Non modifiable ici : repose sur l'arrêt d'un agent Apple, refusé tant que
    /// SIP est activé. La carte est grisée et l'interrupteur désactivé.
    private var sipBlocked: Bool { tweak.requiresSIPDisabled && SIP.enabled }

    /// Bordure : rouge si désactivé, ambre si bloqué par SIP, neutre sinon.
    private var borderColor: Color {
        if isDisabled { return MTColor.rouge.opacity(0.30) }
        if sipBlocked { return MTColor.ambre.opacity(0.30) }
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
                .disabled(model.busy || sipBlocked)
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
                if sipBlocked {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9)).foregroundStyle(MTColor.ambre)
                }
                Spacer(minLength: 0)
                if isDisabled {
                    Text(loc.t("common.disabled"))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(MTColor.rouge)
                } else if sipBlocked {
                    Text(loc.t("feat.sip.chip"))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(MTColor.ambre)
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
        // Grisé quand SIP rend le réglage inopérant (mais la fiche reste consultable).
        .opacity(sipBlocked ? 0.55 : 1)
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
    private var sipBlocked: Bool { tweak.requiresSIPDisabled && SIP.enabled }
    private var items: [DetailItem] { model.itemStates[tweak.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: tweak.icon).font(.title2).foregroundStyle(MTColor.mac)
                Text(tweak.name.current).font(.title3.weight(.semibold))
                chip(tweak.risk.label.current, tweak.risk.color)
                if tweak.needsAdmin { chip(loc.t("common.admin"), .purple) }
                if sipBlocked { chip(loc.t("feat.sip.chip"), MTColor.ambre) }
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
                .disabled(model.busy || sipBlocked)
            }

            if sipBlocked {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(MTColor.ambre)
                    Text(loc.t("feat.sip.blocked"))
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
                                    Circle()
                                        .fill(item.disabled ? MTColor.rouge : Color.green)
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
                                        .disabled(model.busy || sipBlocked)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                        .opacity(sipBlocked ? 0.55 : 1)
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var filteredTweaks: [Tweak] {
        let q = model.searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allTweaks }
        return allTweaks.filter { $0.searchText.contains(q) }
    }

    private func groupRank(_ t: Tweak) -> Int { groupOrder.firstIndex(of: t.group) ?? 0 }

    /// Compatibles SIP : réglages `defaults` et commandes admin. Effet immédiat.
    private var sipCompatibleTweaks: [Tweak] {
        filteredTweaks.filter { !$0.requiresSIPDisabled }
            .sorted { groupRank($0) < groupRank($1) }
    }
    /// Reposent sur l'arrêt d'un agent Apple : bloqués tant que SIP est activé.
    private var sipRequiredTweaks: [Tweak] {
        filteredTweaks.filter { $0.requiresSIPDisabled }
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
            HStack(spacing: 12) {
                Image(systemName: "switch.2").font(.title2).foregroundStyle(MTColor.mac)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.t("tab.features")).font(.headline)
                    Text(loc.t("feat.footer", model.disabledCount, allTweaks.count))
                        .font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: model.disabledCount)
                }
                Spacer()
                TextField(loc.t("feat.search"), text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            .padding(12)

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
                    if !sipRequiredTweaks.isEmpty {
                        categorySection(
                            title: loc.t("feat.sip.required.title"),
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
                if model.disabledCount > 0 && !SIP.enabled {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(MTColor.ambre)
                        Text(loc.t("feat.reboot"))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(loc.t("feat.restart")) {
                            Shell.run("/usr/bin/osascript", ["-e", "tell app \"System Events\" to restart"])
                        }.controlSize(.small)
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
            Text(tweak.breaks.current + "\n\n" + loc.t("feat.confirm.reboot"))
        }
    }
}
