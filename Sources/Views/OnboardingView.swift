//
//  OnboardingView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : autorisations (premier lancement)

struct OnboardingView: View {
    @ObservedObject var model: PermissionsModel
    @EnvironmentObject var loc: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("onb.welcome")).font(.title2.weight(.semibold))
                    Text(loc.t("onb.perm.intro"))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Choix de la langue
            HStack(spacing: 12) {
                Image(systemName: "globe").font(.title2).foregroundStyle(.blue).frame(width: 28)
                Text(loc.t("onb.lang.q")).font(.headline)
                Spacer()
                LanguagePicker(loc: loc)
            }

            Divider()

            permissionRow(
                granted: model.fda,
                grantedText: loc.t("onb.granted"),
                missingText: loc.t("onb.notGranted"),
                title: loc.t("set.auth.fda"),
                desc: loc.t("onb.fda.desc")
            ) {
                HStack(spacing: 8) {
                    Button(loc.t("onb.fda.open")) { Permissions.openFDASettings() }
                    Button(loc.t("onb.fda.recheck")) { model.recheckFDA() }
                    if !model.fda {
                        Button(loc.t("onb.fda.relaunch")) { Permissions.relaunch() }
                    }
                }
            }

            permissionRow(
                granted: model.adminPersistent || model.adminOK,
                grantedText: model.adminPersistent ? loc.t("set.compat.active") : loc.t("onb.admin.ok"),
                missingText: loc.t("onb.notGranted"),
                title: loc.t("set.auth.admin"),
                desc: loc.t("onb.admin.desc")
            ) {
                HStack(spacing: 8) {
                    if model.adminPersistent {
                        Button(loc.t("common.revoke")) { model.revokePersistent() }
                            .disabled(model.testingAdmin)
                    } else {
                        Button(loc.t("onb.admin.verify")) { model.installPersistent() }
                            .disabled(model.testingAdmin)
                    }
                    if model.testingAdmin { ProgressView().controlSize(.small) }
                }
            }

            Divider()

            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(loc.t("set.about.desc"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(loc.t("common.continue")) { model.finish() }
                    .buttonStyle(DarkButton())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(MTColor.nuit)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckFDA()
        }
    }

    private func permissionRow(granted: Bool, grantedText: String, missingText: String,
                               title: String, desc: String,
                               @ViewBuilder buttons: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(granted ? Color.green : MTColor.ambre)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    Text(granted ? grantedText : missingText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((granted ? Color.green : MTColor.ambre).opacity(0.18))
                        .foregroundStyle(granted ? Color.green : MTColor.ambre)
                        .clipShape(Capsule())
                }
                Text(desc).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                buttons()
            }
        }
    }
}

