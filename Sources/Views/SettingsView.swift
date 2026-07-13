//
//  SettingsView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : Réglages

@MainActor
final class SettingsModel: ObservableObject {
    // Valeurs sûres par défaut : aucun appel bloquant pendant la construction de la vue.
    @Published var fda = false
    @Published var adminPersistent = false
    @Published var fanAuth = false
    @Published var resetDone = false

    /// Interroge l'état des autorisations HORS du thread principal (évite tout gel/kill
    /// pendant l'affichage de l'onglet Réglages).
    func refresh() {
        Task.detached {
            let fda = Permissions.hasFullDiskAccess()
            let admin = Permissions.hasPersistentAdmin()
            let fan = FanControl.authInstalled
            await MainActor.run {
                self.fda = fda; self.adminPersistent = admin; self.fanAuth = fan
            }
        }
    }
    func revokeAdmin() {
        Task.detached {
            _ = Permissions.revokePersistentAdmin()
            await MainActor.run { self.refresh() }
        }
    }
    func revokeFan() {
        Task.detached {
            FanControl.removeAuth()
            await MainActor.run { self.refresh() }
        }
    }
    /// Remet MacTuner comme au tout premier lancement, puis relance l'app.
    func resetPrefs() {
        resetDone = true
        Task.detached {
            AppReset.toFactoryDefaults()
            await MainActor.run { Permissions.relaunch() }
        }
    }

    @Published var confirmRemove = false
    @Published var removeRestore = false
    func removeMacTuner() {
        let restore = removeRestore
        Task.detached { SelfUninstall.run(restoreFeatures: restore) }
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @ObservedObject var perm: PermissionsModel
    @StateObject private var model = SettingsModel()
    @EnvironmentObject var loc: L10n

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "gearshape.fill",
                      title: AppInfo.name,
                      subtitle: "\(loc.t("set.tagline")) · v\(AppInfo.version) (build \(AppInfo.build))") {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 32, height: 32)
            }
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(loc.t("set.language"))
                Card {
                    SettingsRow(icon: "globe", color: .blue,
                                title: loc.t("set.language"), subtitle: loc.t("set.language.desc")) {
                        LanguagePicker(loc: loc)
                    }
                }

                sectionTitle(loc.t("set.compat"))
                Card {
                    VStack(spacing: 10) {
                        SettingsRow(icon: SysCompat.isAppleSilicon ? "checkmark.seal.fill" : "xmark.seal.fill",
                                    color: SysCompat.isAppleSilicon ? .green : .red,
                                    title: loc.t("set.compat.arch"), subtitle: SysInfo.chip) {
                            badge(SysCompat.isAppleSilicon ? "Apple Silicon" : "Intel",
                                  SysCompat.isAppleSilicon ? .green : .red)
                        }
                        Divider()
                        SettingsRow(icon: SysCompat.isSupportedOS ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                                    color: SysCompat.isSupportedOS ? .green : MTColor.ambre,
                                    title: loc.t("set.compat.os"), subtitle: SysCompat.osName) {
                            badge(SysCompat.isSupportedOS ? loc.t("set.compat.supported") : loc.t("set.compat.unvalidated"),
                                  SysCompat.isSupportedOS ? .green : MTColor.ambre)
                        }
                        Divider()
                        SettingsRow(icon: "fanblades.fill", color: .cyan,
                                    title: loc.t("set.compat.fan"),
                                    subtitle: SysInfo.chip) {
                            badge(SysCompat.fanControlAllowed ? loc.t("set.compat.active") : loc.t("set.compat.blocked"),
                                  SysCompat.fanControlAllowed ? .green : .secondary)
                        }
                    }
                }

                sectionTitle(loc.t("set.auth"))
                Card {
                    VStack(spacing: 10) {
                        SettingsRow(icon: model.fda ? "externaldrive.badge.checkmark" : "externaldrive.badge.xmark",
                                    color: model.fda ? .green : MTColor.ambre,
                                    title: loc.t("set.auth.fda"),
                                    subtitle: model.fda ? loc.t("set.auth.fda.on") : loc.t("set.auth.fda.off")) {
                            Button(model.fda ? loc.t("common.open") : loc.t("common.grant")) { Permissions.openFDASettings() }
                        }
                        Divider()
                        SettingsRow(icon: "lock.shield.fill",
                                    color: model.adminPersistent ? .green : .secondary,
                                    title: loc.t("set.auth.admin"),
                                    subtitle: model.adminPersistent ? loc.t("set.auth.admin.on") : loc.t("set.auth.admin.off")) {
                            if model.adminPersistent { Button(loc.t("common.revoke")) { model.revokeAdmin() } }
                            else { Text("—").foregroundStyle(.secondary) }
                        }
                        Divider()
                        SettingsRow(icon: "fanblades",
                                    color: model.fanAuth ? .green : .secondary,
                                    title: loc.t("set.auth.fan"),
                                    subtitle: model.fanAuth ? loc.t("set.auth.fan.on") : loc.t("set.auth.fan.off")) {
                            if model.fanAuth { Button(loc.t("common.revoke")) { model.revokeFan() } }
                            else { Text("—").foregroundStyle(.secondary) }
                        }
                    }
                }

                sectionTitle(loc.t("set.data"))
                Card {
                    SettingsRow(icon: "arrow.counterclockwise.circle.fill", color: MTColor.ambre,
                                title: loc.t("set.reset"), subtitle: loc.t("set.reset.desc")) {
                        if model.resetDone {
                            Label(loc.t("common.done"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button(loc.t("set.reset.btn"), role: .destructive) { model.resetPrefs() }
                        }
                    }
                }

                sectionTitle(loc.t("set.about"))
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.t("set.about.desc"))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(loc.t("set.hardware")) : \(SysInfo.model) · \(SysInfo.chip) · \(SysInfo.totalCores) \(loc.t("dash.cpu.cores")) · \(humanBytesShort(Int64(SysInfo.int("hw.memsize"))))")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        HStack(spacing: 10) {
                            Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink)
                            Text(loc.t("set.credits")).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Link(destination: URL(string: AppInfo.repo)!) {
                                Label(loc.t("set.source"), systemImage: "chevron.left.forwardslash.chevron.right").font(.caption)
                            }
                            Link(destination: URL(string: AppInfo.website)!) {
                                Label(loc.t("set.website"), systemImage: "safari").font(.caption)
                            }
                        }
                    }
                }

                sectionTitle(loc.t("set.remove"))
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsRow(icon: "trash.slash.fill", color: .red,
                                    title: loc.t("set.remove"), subtitle: loc.t("set.remove.desc")) {
                            Button(loc.t("set.remove.btn"), role: .destructive) {
                                model.confirmRemove = true
                            }.buttonStyle(DarkButton(accent: MTColor.rouge))
                        }
                        Toggle(isOn: Binding(get: { model.removeRestore },
                                             set: { model.removeRestore = $0 })) {
                            Text(loc.t("set.remove.restore")).font(.callout)
                        }
                        .toggleStyle(.switch)
                    }
                }
            }
            .tabContent()
            }
            .background(MTColor.fond)
        }
        .onAppear { model.refresh() }
        .alert(loc.t("set.remove.confirm"), isPresented: $model.confirmRemove) {
            Button(loc.t("set.remove.ok"), role: .destructive) { model.removeMacTuner() }
            Button(loc.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("set.remove.msg"))
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        // Même style que les titres de section des autres onglets (Fonctionnalités).
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }
    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.16)).foregroundStyle(color).clipShape(Capsule())
    }
}

