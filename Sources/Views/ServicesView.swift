//
//  ServicesView.swift · MacTuner
//
import SwiftUI

// MARK: - Vue : inventaire des services

/// Référence et vérification. Deux questions, une seule vue :
/// « que fait ce service ? » et « est-il vraiment arrêté ? ».
/// Rien n'y est modifiable — les interrupteurs vivent dans Fonctionnalités.
struct ServicesView: View {
    @StateObject private var model = ServicesModel()
    @EnvironmentObject var loc: L10n

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "list.bullet.rectangle.portrait",
                      title: loc.t("tab.services"),
                      subtitle: loc.t("svc.subtitle")) {
                TextField(loc.t("svc.search"), text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            Divider()

            controls
            Divider()

            if model.busy && model.rows.isEmpty {
                Spacer()
                ProgressView().controlSize(.large)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.filtered) { row in ServiceRowView(row: row) }
                        if model.filtered.isEmpty && model.scanned {
                            Text(loc.t("svc.empty"))
                                .font(.callout).foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                    }
                    .tabContent()
                }
                .background(MTColor.fond)
            }
        }
        .onAppear { if !model.scanned { model.load() } }
    }

    // MARK: Bandeau de contrôle et statistiques

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("", selection: Binding(
                    get: { model.scope },
                    set: { model.scope = $0; model.load() }
                )) {
                    Text(loc.t("svc.scope.catalog")).tag(0)
                    Text(loc.t("svc.scope.all")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                Toggle(loc.t("svc.runningOnly"), isOn: $model.runningOnly)
                    .toggleStyle(.switch).controlSize(.mini)

                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(loc.t("common.refresh")) { model.load() }.disabled(model.busy)
            }

            HStack(spacing: 8) {
                stat(loc.t("svc.stat.running"), "\(model.runningCount)", .green)
                stat(loc.t("svc.stat.ram"), humanBytes(model.totalRSS), MTColor.bleu)
                stat(loc.t("svc.stat.disabled"), "\(model.disabledCount)", MTColor.rouge)
                if model.runningDespiteFlagCount > 0 {
                    stat(loc.t("svc.stat.pending"), "\(model.runningDespiteFlagCount)", MTColor.ambre)
                }
                Spacer(minLength: 0)
            }

            // La seule chose qui compte pour vérifier : ce qui reste en mémoire.
            if model.runningDespiteFlagCount > 0 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(MTColor.ambre)
                    Text(loc.t("svc.verify.pending", model.runningDespiteFlagCount))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MTColor.ambre.opacity(0.10)))
            } else if model.scope == 0 && model.disabledCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(loc.t("svc.verify.clean", model.disabledCount))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.08)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - Une ligne de service

private struct ServiceRowView: View {
    let row: ServiceRow
    @EnvironmentObject var loc: L10n

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(row.state.color).frame(width: 8, height: 8).padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    badge(row.domain.badge.current, row.domain.color)
                    if !row.tweakName.isEmpty { badge(row.tweakName, MTColor.mac) }
                    Spacer(minLength: 0)
                }
                Text(row.role?.current ?? loc.t("svc.role.unknown"))
                    .font(.caption2)
                    .foregroundStyle(row.role == nil ? Color.secondary.opacity(0.6) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text(loc.t(row.state.key))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.state.color)
                if row.running {
                    Text("\(humanBytes(row.rssBytes)) · PID \(row.pid.map(String.init) ?? "—")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MTColor.bleu)
                }
            }
            .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(row.runningDespiteFlag ? MTColor.ambre.opacity(0.45) : MTColor.ligne, lineWidth: 1))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
