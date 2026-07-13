//
//  UninstallView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : désinstallation

struct AppIcon: View {
    let path: String
    var size: CGFloat = 32
    var body: some View {
        Image(nsImage: nsIcon(path))
            .resizable().frame(width: size, height: size)
    }
}

struct ResidueRow: View {
    let residue: Residue
    @ObservedObject var model: UninstallModel
    @EnvironmentObject var loc: L10n

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.selectedResidues.contains(residue.id) },
                set: { on in
                    if on { model.selectedResidues.insert(residue.id) }
                    else { model.selectedResidues.remove(residue.id) }
                }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .disabled(residue.kind == .appBundle ? false : model.busy)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(residue.kind.label).font(.callout.weight(.medium))
                    if residue.system {
                        Label(loc.t("common.admin"), systemImage: "lock.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple).clipShape(Capsule())
                    }
                    if !residue.highConfidence {
                        Text(loc.t("uninst.byName"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(MTColor.ambre.opacity(0.15))
                            .foregroundStyle(MTColor.ambre).clipShape(Capsule())
                            .help(loc.t("uninst.byNameHelp"))
                    }
                }
                Text((residue.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(humanBytes(residue.bytes))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.selectFile(residue.path, inFileViewerRootedAtPath: "")
            } label: { Image(systemName: "magnifyingglass").font(.caption) }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help(loc.t("common.finder"))
        }
        .padding(.vertical, 3)
    }
}

struct UninstallView: View {
    @ObservedObject var model: UninstallModel
    @EnvironmentObject var loc: L10n

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "xmark.bin.fill",
                      title: loc.t("uninst.title"),
                      subtitle: loc.t("uninst.selectHint")) {
                if model.scanningApps { ProgressView().controlSize(.small) }
                Button { model.scanApps() } label: {
                    Label(loc.t("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(model.scanningApps)
            }
            Divider()
            HSplitView {
                appList
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                residuePanel
                    .frame(minWidth: 420)
            }
        }
        .background(MTColor.fond.ignoresSafeArea())
        .onAppear { if !model.scanned { model.scanApps() } }
        .alert(loc.t("uninst.confirm", model.selectedApp?.name ?? ""),
               isPresented: $model.confirm) {
            Button(loc.t("uninst.confirm.ok"), role: .destructive) { model.uninstall() }
            Button(loc.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("uninst.confirm.msg", model.selectedResidues.count, humanBytes(model.selectedBytes)))
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(
                get: { model.listMode },
                set: { model.listMode = $0 }
            )) {
                Text("\(loc.t("uninst.apps")) (\(model.apps.count))").tag(0)
                Text("\(loc.t("uninst.cli")) (\(model.cliTools.count))").tag(1)
                Text("\(loc.t("uninst.hidden")) (\(model.dotItems.count))").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            TextField(loc.t("common.search"), text: $model.searchText)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 10).padding(.bottom, 8)
            Divider()
            List(model.filteredApps, selection: Binding(
                get: { model.selectedApp?.id },
                set: { id in if let a = model.filteredApps.first(where: { $0.id == id }) { model.inspect(a) } }
            )) { app in
                HStack(spacing: 8) {
                    switch app.kind {
                    case .app:
                        AppIcon(path: app.path)
                    case .cli:
                        Image(systemName: "terminal.fill")
                            .font(.title3).foregroundStyle(.secondary).frame(width: 32)
                    case .dotfile:
                        Image(systemName: "eye.slash.fill")
                            .font(.title3).foregroundStyle(.secondary).frame(width: 32)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(app.name).font(.callout.weight(.medium)).lineLimit(1)
                            if !app.aliases.isEmpty {
                                Text("+ \(app.aliases.joined(separator: ", "))")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue).clipShape(Capsule())
                            }
                        }
                        Text(app.kind == .app
                             ? app.bundleID
                             : (app.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(humanBytes(app.bytes)).font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .tag(app.id)
                .padding(.vertical, 2)
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var residuePanel: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    switch app.kind {
                    case .app:
                        AppIcon(path: app.path, size: 48)
                    case .cli:
                        Image(systemName: "terminal.fill").font(.system(size: 40))
                            .foregroundStyle(.secondary).frame(width: 48, height: 48)
                    case .dotfile:
                        Image(systemName: "eye.slash.fill").font(.system(size: 36))
                            .foregroundStyle(.secondary).frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title3.weight(.semibold))
                        switch app.kind {
                        case .app:
                            Text(app.bundleID.isEmpty ? app.path : app.bundleID)
                                .font(.caption).foregroundStyle(.secondary)
                        case .cli:
                            Text(loc.t("uninst.cliTool")
                                 + (app.aliases.isEmpty ? "" : " · " + loc.t("uninst.aliases", app.aliases.joined(separator: ", "))))
                                .font(.caption).foregroundStyle(.secondary)
                        case .dotfile:
                            Text(loc.t("uninst.hiddenItem", (app.path as NSString).abbreviatingWithTildeInPath))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if model.findingResidues { ProgressView().controlSize(.small) }
                }
                .padding(12)
                Divider()

                if model.residues.isEmpty && !model.findingResidues {
                    Spacer(); Text(loc.t("uninst.noResidue")).foregroundStyle(.secondary); Spacer()
                } else {
                    List {
                        Section {
                            ForEach(model.residues) { r in ResidueRow(residue: r, model: model) }
                        } header: {
                            HStack {
                                Text(loc.t("uninst.detected", model.residues.count))
                                Spacer()
                                Button(loc.t("uninst.all")) {
                                    model.selectedResidues = Set(model.residues.map(\.id))
                                }.buttonStyle(.link).font(.caption)
                                Button(loc.t("uninst.highConf")) {
                                    model.selectedResidues = Set(model.residues.filter(\.highConfidence).map(\.id))
                                }.buttonStyle(.link).font(.caption)
                                Button(loc.t("uninst.none")) { model.selectedResidues = [] }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }

                Divider()
                HStack {
                    Image(systemName: "trash.fill").foregroundStyle(.red)
                    Text(loc.t("uninst.footer"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button {
                        model.confirm = true
                    } label: {
                        Text(loc.t("uninst.btn", humanBytes(model.selectedBytes)))
                    }
                    .buttonStyle(DarkButton(accent: MTColor.rouge))
                    .disabled(model.busy || model.selectedResidues.isEmpty)
                }
                .padding(12)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "trash.square.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                Text(loc.t("uninst.selectApp")).font(.title3).foregroundStyle(.secondary)
                Text(loc.t("uninst.selectHint"))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                if let r = model.lastResult {
                    Label(loc.t("uninst.done", r.app, r.count, humanBytes(r.freed)),
                          systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.green).padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

