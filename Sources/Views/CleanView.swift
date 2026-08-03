//
//  CleanView.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Hub nettoyage : catégories, langues et journal regroupés

/// Regroupe les trois volets liés au nettoyage sous un seul onglet, avec un
/// sélecteur segmenté. Évite de surcharger la barre d'onglets principale.
struct CleanupHubView: View {
    @ObservedObject var model: CleanModel
    @EnvironmentObject var loc: L10n

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { model.section }, set: { model.section = $0 })) {
                Text(loc.t("clean.hub.cats")).tag(0)
                Text(loc.t("tab.languages")).tag(1)
                Text(loc.t("tab.log")).tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(MTColor.nuit)
            Divider()
            switch model.section {
            case 1:  LanguagesView()
            case 2:  LogView()
            default: CleanView(model: model)
            }
        }
    }
}

// MARK: - Vues : nettoyage (grille de cartes)

private func chip(_ text: String, _ color: Color) -> some View {
    Text(text)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.16))
        .foregroundStyle(color)
        .clipShape(Capsule())
}

/// Carte d'une catégorie : clic pour sélectionner, bouton Détails pour la fiche.
struct CleanCard: View {
    let category: CleanCategory
    @ObservedObject var model: CleanModel
    @EnvironmentObject var loc: L10n

    private var bytes: Int64 { model.categoryBytes(category.id) }
    private var isEmpty: Bool { bytes == 0 }
    private var selected: Bool { model.selected.contains(category.id) }
    private var selectable: Bool { model.hasScanned && !isEmpty && !model.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundStyle(isEmpty && model.hasScanned ? Color.secondary : MTColor.mac)
                    .frame(width: 20, alignment: .leading)
                if category.needsAdmin {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(MTColor.ambre)
                        .help(loc.t("clean.adminBadge"))
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(selected ? MTColor.bleu : Color.secondary.opacity(0.45))
            }
            Text(category.name.current)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(category.what.current)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(category.risk.color).frame(width: 6, height: 6)
                Text(model.hasScanned ? humanBytes(bytes) : "·")
                    .font(.system(size: 11, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isEmpty ? .secondary : .primary)
                    .contentTransition(.numericText())
                    .animation(.default, value: bytes)
                Spacer(minLength: 0)
                Button(loc.t("feat.details")) { model.detailCategory = category }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MTColor.mac)
            }
            .padding(.top, 1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(selected ? MTColor.bleu.opacity(0.10) : MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(selected ? MTColor.bleu.opacity(0.6) : MTColor.ligne, lineWidth: 1))
        .opacity(model.hasScanned && isEmpty ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard selectable else { return }
            if selected { model.selected.remove(category.id) }
            else { model.selected.insert(category.id) }
        }
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

/// Fiche d'une catégorie : rôle, précautions et chemins réellement analysés.
struct CleanDetailSheet: View {
    let category: CleanCategory
    @ObservedObject var model: CleanModel
    @EnvironmentObject var loc: L10n

    private var pathStats: [PathStat] { model.stats[category.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: category.icon).font(.title2).foregroundStyle(MTColor.mac)
                Text(category.name.current).font(.title3.weight(.semibold))
                chip(category.risk.label.current, category.risk.color)
                Spacer()
                Text(model.hasScanned ? humanBytes(model.categoryBytes(category.id)) : "·")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.blue).frame(width: 18)
                        Text(category.what.current).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MTColor.ambre).frame(width: 18)
                        Text(category.warn.current).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !pathStats.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(pathStats) { stat in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(stat.exists ? (stat.bytes > 0 ? MTColor.ambre : Color.green)
                                                          : Color.gray.opacity(0.4))
                                        .frame(width: 7, height: 7)
                                    Text(stat.id).font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(stat.exists ? humanBytes(stat.bytes) : "absent")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let first = pathStats.first(where: { $0.exists }) {
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: first.fullPath)
                        } label: {
                            Label(loc.t("common.finder"), systemImage: "folder")
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            HStack {
                Spacer()
                Button(loc.t("common.close")) { model.detailCategory = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 460)
    }
}

/// Fenêtre de progression du nettoyage : barre réelle et chemin en cours,
/// puis bilan avec coche.
struct CleaningSheet: View {
    @ObservedObject var model: CleanModel
    @EnvironmentObject var loc: L10n
    private var done: Bool { !model.busy }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.teal.opacity(0.12)).frame(width: 96, height: 96)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48)).foregroundStyle(.green)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 40)).foregroundStyle(.teal)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: done)

            Text(done ? loc.t("clean.progress.done") : loc.t("clean.progress.title"))
                .font(.headline)

            if done {
                if let freed = model.lastFreed {
                    Text(loc.t("clean.progress.freed", humanBytes(freed)))
                        .font(.title3.weight(.bold)).foregroundStyle(.green)
                }
                Button(loc.t("common.close")) { model.cleaningActive = false }
                    .buttonStyle(DarkButton())
                    .keyboardShortcut(.defaultAction)
            } else {
                ProgressView(value: model.cleanProgress)
                    .progressViewStyle(.linear)
                    .tint(MTColor.bleu)
                    .frame(width: 330)
                Text(model.currentTarget.isEmpty
                     ? "…" : (model.currentTarget as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(width: 350)
                Text("\(Int(model.cleanProgress * 100)) %")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: Int(model.cleanProgress * 100))
            }
        }
        .padding(28)
        .frame(width: 430)
        .interactiveDismissDisabled(model.busy)
    }
}

struct CleanView: View {
    @ObservedObject var model: CleanModel
    @EnvironmentObject var loc: L10n

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "trash.fill", title: loc.t("clean.title"),
                      subtitle: model.hasScanned
                        ? loc.t("clean.detected", humanBytes(model.totalBytes))
                        : loc.t("clean.scanPrompt")) {
                if let freed = model.lastFreed {
                    Label(loc.t("clean.freed", humanBytes(freed)), systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.green)
                }
                if model.hasScanned && !model.selectableIDs.isEmpty {
                    Button {
                        model.toggleSelectAll()
                    } label: {
                        Label(model.allSelectableSelected ? loc.t("clean.deselectAll") : loc.t("clean.selectAll"),
                              systemImage: model.allSelectableSelected ? "circle" : "checkmark.circle.fill")
                    }
                    .disabled(model.busy)
                }
                Button {
                    model.lastFreed = nil
                    model.scan()
                } label: {
                    Label(model.hasScanned ? loc.t("clean.rescan") : loc.t("clean.scan"), systemImage: "magnifyingglass")
                }
                .disabled(model.busy)
            }
            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cleanCategories.filter { $0.id != "languages" }) { cat in
                        CleanCard(category: cat, model: model)
                    }
                }
                .tabContent()
            }
            .background(MTColor.fond)

            Divider()
            HStack {
                Image(systemName: "hand.raised.fill").foregroundStyle(MTColor.ambre)
                Text(loc.t("clean.safeNote"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button {
                    model.confirmClean = true
                } label: {
                    Text(model.selected.isEmpty
                         ? loc.t("clean.cleanBtn")
                         : loc.t("clean.cleanBtnSize", humanBytes(model.selectedBytes)))
                }
                .buttonStyle(DarkButton(accent: MTColor.rouge))
                .disabled(model.busy || model.selected.isEmpty)
            }
            .padding(12)
        }
        .sheet(isPresented: $model.cleaningActive) {
            CleaningSheet(model: model).environmentObject(loc)
        }
        .sheet(item: $model.detailCategory) { cat in
            CleanDetailSheet(category: cat, model: model).environmentObject(loc)
        }
        .alert(loc.t("clean.confirm"), isPresented: $model.confirmClean) {
            Button(loc.t("clean.confirm.ok"), role: .destructive) { model.cleanSelected() }
            Button(loc.t("common.cancel"), role: .cancel) {}
        } message: {
            let names = cleanCategories.filter { model.selected.contains($0.id) }
                .map { $0.name.current }.joined(separator: ", ")
            let base = loc.t("clean.confirm.msg", names, humanBytes(model.selectedBytes))
            // Avertissement renforcé, spécifique au nettoyage des langues (signatures
            // d'app invalidées, restauration seulement par réinstallation).
            let extra = model.selected.contains("languages") ? "\n\n" + loc.t("clean.confirm.langs") : ""
            Text(base + extra)
        }
    }
}
