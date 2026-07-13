//
//  LogView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : journal des suppressions

@MainActor
final class LogModel: ObservableObject {
    @Published var records: [DeletionRecord] = []
    @Published var search = ""
    @Published var confirmClear = false

    func reload() { records = ActionLog.load() }

    func clearAll() {
        ActionLog.clear()
        records = []
    }

    var totalBytes: Int64 { records.reduce(0) { $0 + max($1.bytes, 0) } }
}

struct LogView: View {
    @StateObject private var model = LogModel()
    @EnvironmentObject var loc: L10n

    /// Nom lisible de l'origine : catégorie de nettoyage ou app désinstallée.
    private func sourceLabel(_ r: DeletionRecord) -> String {
        if r.source.hasPrefix("app:") {
            return "\(loc.t("tab.uninstall")) · \(r.source.dropFirst(4))"
        }
        return cleanCategories.first { $0.id == r.source }?.name.current ?? r.source
    }

    private var filtered: [DeletionRecord] {
        let q = model.search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.records }
        return model.records.filter {
            $0.path.lowercased().contains(q) || sourceLabel($0).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.t("log.title")).font(.headline)
                    Text(model.records.isEmpty
                         ? loc.t("log.subtitle")
                         : loc.t("log.count", model.records.count, humanBytes(model.totalBytes)))
                        .font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: model.records.count)
                }
                Spacer()
                TextField(loc.t("log.search"), text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Button {
                    model.reload()
                } label: {
                    Label(loc.t("common.refresh"), systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    model.confirmClear = true
                } label: {
                    Label(loc.t("log.clear"), systemImage: "trash")
                }
                .disabled(model.records.isEmpty)
            }
            .padding(12)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 42)).foregroundStyle(.quaternary)
                    Text(model.records.isEmpty ? loc.t("log.empty") : loc.t("log.noMatch"))
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filtered) { rec in
                    HStack(spacing: 10) {
                        Image(systemName: rec.source.hasPrefix("app:")
                              ? "xmark.bin.fill" : "trash.circle.fill")
                            .foregroundStyle(rec.source.hasPrefix("app:") ? Color.red : .teal)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((rec.path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Text("\(sourceLabel(rec)) · \(rec.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rec.bytes >= 0 ? humanBytes(rec.bytes) : "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(MTColor.fond.ignoresSafeArea())
        .onAppear { model.reload() }
        .alert(loc.t("log.clear.confirm"), isPresented: $model.confirmClear) {
            Button(loc.t("log.clear"), role: .destructive) { model.clearAll() }
            Button(loc.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("log.clear.msg"))
        }
    }
}
