//
//  DiskView.swift · MacTuner
//
import SwiftUI
import AppKit

// MARK: - Modèle : espace disque

@MainActor
final class DiskModel: ObservableObject {
    enum Mode: Int, CaseIterable, Identifiable {
        case large, duplicates, installers, breakdown
        var id: Int { rawValue }
    }

    @Published var mode: Mode = .large
    @Published var busy = false
    @Published var scanned: Set<Mode> = []
    @Published var large: [DiskEngine.FileItem] = []
    @Published var dupes: [[DiskEngine.FileItem]] = []
    @Published var installers: [DiskEngine.FileItem] = []
    @Published var breakdown: [DiskEngine.FileItem] = []
    @Published var selected: Set<String> = []
    @Published var lastFreed: Int64?
    @Published var minMB = 100
    @Published var confirm = false

    /// Éléments plats de la liste courante (hors doublons et répartition).
    var flatItems: [DiskEngine.FileItem] {
        switch mode {
        case .large: return large
        case .installers: return installers
        default: return []
        }
    }

    var selectedBytes: Int64 {
        var total: Int64 = 0
        let all = large + installers + dupes.flatMap { $0 }
        for f in all where selected.contains(f.id) { total += f.bytes }
        return total
    }

    var canClean: Bool { mode != .breakdown && !selected.isEmpty }

    func scan() {
        busy = true
        lastFreed = nil
        let m = mode
        let minBytes = Int64(minMB) * 1024 * 1024
        Task.detached(priority: .userInitiated) {
            switch m {
            case .large:
                let r = DiskEngine.largeFiles(minBytes: minBytes)
                await MainActor.run { self.large = r; self.finish(m) }
            case .installers:
                let r = DiskEngine.oldInstallers()
                await MainActor.run { self.installers = r; self.finish(m) }
            case .duplicates:
                let r = DiskEngine.duplicates(root: DiskEngine.home + "/Downloads")
                await MainActor.run {
                    self.dupes = r
                    // Présélection : garder le premier de chaque groupe, cocher les autres.
                    self.selected = Set(r.flatMap { $0.dropFirst() }.map(\.id))
                    self.finish(m)
                }
            case .breakdown:
                let r = DiskEngine.folderBreakdown()
                await MainActor.run { self.breakdown = r; self.finish(m) }
            }
        }
    }

    private func finish(_ m: Mode) {
        busy = false
        scanned.insert(m)
        if m != .duplicates { selected = [] }
    }

    func clean() {
        busy = true
        let paths = Array(selected)
        Task.detached(priority: .userInitiated) {
            let freed = DiskEngine.trash(paths)
            await MainActor.run {
                self.lastFreed = freed
                self.selected = []
                self.busy = false
                self.scan()
            }
        }
    }
}

// MARK: - Vue : espace disque

struct DiskView: View {
    @StateObject private var model = DiskModel()
    @EnvironmentObject var loc: L10n

    private func modeLabel(_ m: DiskModel.Mode) -> String {
        switch m {
        case .large: return loc.t("disk.mode.large")
        case .duplicates: return loc.t("disk.mode.dupes")
        case .installers: return loc.t("disk.mode.install")
        case .breakdown: return loc.t("disk.mode.breakdown")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "internaldrive.fill", tint: MTColor.mac,
                      title: loc.t("disk.title"), subtitle: loc.t("disk.subtitle")) {
                if let freed = model.lastFreed {
                    Label(loc.t("clean.freed", humanBytes(freed)), systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.green)
                }
                if model.mode == .large {
                    Picker("", selection: Binding(get: { model.minMB }, set: { model.minMB = $0 })) {
                        Text("≥ 100 MB").tag(100)
                        Text("≥ 500 MB").tag(500)
                        Text("≥ 1 GB").tag(1000)
                    }.labelsHidden().fixedSize().disabled(model.busy)
                }
                Button { model.scan() } label: {
                    Label(loc.t("clean.scan"), systemImage: "magnifyingglass")
                }.disabled(model.busy)
            }
            Divider()

            Picker("", selection: Binding(get: { model.mode }, set: { model.mode = $0; model.selected = [] })) {
                ForEach(DiskModel.Mode.allCases) { m in Text(modeLabel(m)).tag(m) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 16).padding(.top, 10)

            content
                .background(MTColor.fond)

            if model.mode != .breakdown {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "trash.fill").foregroundStyle(MTColor.ambre)
                    Text(loc.t("disk.footer")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button { model.confirm = true } label: {
                        Text(model.selected.isEmpty ? loc.t("disk.trashBtn")
                                                    : loc.t("disk.trashBtnSize", humanBytes(model.selectedBytes)))
                    }
                    .buttonStyle(DarkButton(accent: MTColor.rouge))
                    .disabled(model.busy || !model.canClean)
                }
                .padding(12)
            }
        }
        .onAppear { if !model.scanned.contains(model.mode) { model.scan() } }
        .onChange(of: model.mode) { _, m in if !model.scanned.contains(m) { model.scan() } }
        .alert(loc.t("disk.confirm"), isPresented: $model.confirm) {
            Button(loc.t("disk.confirm.ok"), role: .destructive) { model.clean() }
            Button(loc.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("disk.confirm.msg", model.selected.count, humanBytes(model.selectedBytes)))
        }
    }

    @ViewBuilder private var content: some View {
        if model.busy && !model.scanned.contains(model.mode) {
            Spacer(); ProgressView().controlSize(.large); Spacer()
        } else {
            switch model.mode {
            case .large: fileList(model.large, empty: "disk.empty.large")
            case .installers: fileList(model.installers, empty: "disk.empty.install")
            case .duplicates: dupesList
            case .breakdown: breakdownList
            }
        }
    }

    private func fileList(_ items: [DiskEngine.FileItem], empty: String) -> some View {
        Group {
            if items.isEmpty {
                infoBox("checkmark.seal.fill", loc.t(empty))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { f in fileRow(f) }
                    }.tabContent()
                }
            }
        }
    }

    private var dupesList: some View {
        Group {
            if model.dupes.isEmpty {
                infoBox("checkmark.seal.fill", loc.t("disk.empty.dupes"))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(model.dupes.enumerated()), id: \.offset) { _, group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t("disk.dupeGroup", group.count, humanBytes(group.first?.bytes ?? 0)))
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(group) { f in fileRow(f) }
                            }
                        }
                    }.tabContent()
                }
            }
        }
    }

    private var breakdownList: some View {
        let maxB = model.breakdown.first?.bytes ?? 1
        return ScrollView {
            VStack(spacing: 8) {
                ForEach(model.breakdown) { f in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").foregroundStyle(MTColor.mac).frame(width: 22)
                        Text(f.name).font(.callout.weight(.medium)).frame(width: 150, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MTColor.surface)
                                Capsule().fill(MTColor.bleu.opacity(0.7))
                                    .frame(width: max(6, geo.size.width * CGFloat(Double(f.bytes) / Double(max(maxB, 1)))))
                            }
                        }.frame(height: 10)
                        Text(humanBytes(f.bytes)).font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: f.path)
                        } label: { Image(systemName: "folder").font(.caption) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MTColor.carte))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MTColor.ligne, lineWidth: 1))
                }
            }.tabContent()
        }
    }

    private func fileRow(_ f: DiskEngine.FileItem) -> some View {
        let on = model.selected.contains(f.id)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { on }, set: { v in
                if v { model.selected.insert(f.id) } else { model.selected.remove(f.id) }
            })).toggleStyle(.checkbox).labelsHidden()
            Image(systemName: nsIconSymbol(f)).foregroundStyle(MTColor.mac).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text((f.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(humanBytes(f.bytes)).font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(.secondary)
            Button { NSWorkspace.shared.selectFile(f.path, inFileViewerRootedAtPath: "") } label: {
                Image(systemName: "magnifyingglass").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(on ? MTColor.bleu.opacity(0.10) : MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(on ? MTColor.bleu.opacity(0.5) : MTColor.ligne, lineWidth: 1))
    }

    private func nsIconSymbol(_ f: DiskEngine.FileItem) -> String {
        switch (f.name as NSString).pathExtension.lowercased() {
        case "dmg", "pkg", "iso", "xip", "cdr": return "shippingbox.fill"
        case "zip", "gz", "tar", "rar", "7z": return "doc.zipper"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "jpg", "jpeg", "png", "heic", "gif": return "photo.fill"
        case "mp3", "wav", "aac", "flac": return "music.note"
        default: return "doc.fill"
        }
    }

    private func infoBox(_ icon: String, _ text: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(MTColor.mac)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}
