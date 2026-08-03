//
//  LanguagesView.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Modèle : nettoyage des langues

@MainActor
final class LanguagesModel: ObservableObject {
    struct LangApp: Identifiable {
        let id: String          // chemin du bundle .app
        let name: String        // nom affiché (sans .app)
        let langs: [String]     // langues supprimables (ex. "de", "zh_CN")
        let bytes: Int64
    }

    @Published var apps: [LangApp] = []
    @Published var stats: [PathStat] = []   // à plat, pour le moteur
    @Published var busy = false
    @Published var hasScanned = false
    @Published var confirm = false
    @Published var cleaning = false
    @Published var lastFreed: Int64?

    var totalBytes: Int64 { apps.reduce(0) { $0 + $1.bytes } }
    var totalLangs: Int { apps.reduce(0) { $0 + $1.langs.count } }

    func scan() {
        busy = true
        lastFreed = nil
        Task.detached(priority: .userInitiated) {
            let files = CleanEngine.appLanguageFiles()
            var groups = [String: [String]]()   // appPath -> [lprojPath]
            for f in files {
                guard let r = f.range(of: ".app/") else { continue }
                let appPath = String(f[..<r.lowerBound]) + ".app"
                groups[appPath, default: []].append(f)
            }
            var apps = [LangApp]()
            var flat = [PathStat]()
            for (appPath, lprojs) in groups {
                var total: Int64 = 0
                var langs = [String]()
                for p in lprojs.sorted() {
                    let b = CleanEngine.fastDirBytes(p)
                    total += b
                    langs.append(((p as NSString).lastPathComponent as NSString).deletingPathExtension)
                    flat.append(PathStat(id: p, fullPath: p, bytes: b, exists: true))
                }
                let name = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
                apps.append(LangApp(id: appPath, name: name, langs: langs, bytes: total))
            }
            apps.sort { $0.bytes > $1.bytes }
            let finalApps = apps, finalFlat = flat
            await MainActor.run {
                self.apps = finalApps
                self.stats = finalFlat
                self.busy = false
                self.hasScanned = true
            }
        }
    }

    func clean() {
        busy = true
        cleaning = true
        let snapshot = stats
        Task.detached(priority: .userInitiated) {
            // Une seule invite si l'autorisation durable n'est pas déjà en place.
            if !Permissions.hasCleanAuth() { _ = Permissions.installCleanAuth() }
            let freed = CleanEngine.clean(categoryIDs: ["languages"],
                                          stats: ["languages": snapshot])
            await MainActor.run {
                self.lastFreed = freed
                self.cleaning = false
                self.busy = false
                self.scan()   // réanalyse pour refléter l'état réel
            }
        }
    }
}

// MARK: - Vue : nettoyage des langues

struct LanguagesView: View {
    @StateObject private var model = LanguagesModel()
    @EnvironmentObject var loc: L10n

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "character.bubble.fill", tint: MTColor.mac,
                      title: loc.t("lang.title"),
                      subtitle: model.hasScanned
                        ? loc.t("lang.found", model.totalLangs, model.apps.count, humanBytes(model.totalBytes))
                        : loc.t("lang.subtitle")) {
                HStack(spacing: 8) {
                    if let freed = model.lastFreed {
                        Label(loc.t("clean.freed", humanBytes(freed)), systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(.green)
                    }
                    Button {
                        model.scan()
                    } label: {
                        Label(model.hasScanned ? loc.t("clean.rescan") : loc.t("clean.scan"),
                              systemImage: "magnifyingglass")
                    }
                    .disabled(model.busy)
                }
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    warningBanner

                    if model.busy && !model.hasScanned {
                        HStack { Spacer(); ProgressView().controlSize(.large); Spacer() }
                            .padding(.top, 40)
                    } else if model.hasScanned && model.apps.isEmpty {
                        emptyState
                    } else if model.hasScanned {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(model.apps) { app in appCard(app) }
                        }
                    } else {
                        promptState
                    }
                }
                .tabContent()
            }
            .background(MTColor.fond)

            Divider()
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(MTColor.ambre)
                Text(loc.t("lang.adminNote")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.cleaning { ProgressView().controlSize(.small) }
                Button {
                    model.confirm = true
                } label: {
                    Text(model.totalBytes > 0
                         ? loc.t("lang.cleanBtnSize", humanBytes(model.totalBytes))
                         : loc.t("lang.cleanBtn"))
                }
                .buttonStyle(DarkButton(accent: MTColor.rouge))
                .disabled(model.busy || !model.hasScanned || model.apps.isEmpty)
            }
            .padding(12)
        }
        .onAppear { if !model.hasScanned { model.scan() } }
        .alert(loc.t("lang.confirm"), isPresented: $model.confirm) {
            Button(loc.t("lang.confirm.ok"), role: .destructive) { model.clean() }
            Button(loc.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("lang.confirm.msg", model.totalLangs, model.apps.count))
        }
    }

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundStyle(MTColor.ambre)
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("lang.warn.title")).font(.callout.weight(.semibold))
                Text(loc.t("lang.warn.body")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(MTColor.ambre.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(MTColor.ambre.opacity(0.35), lineWidth: 1))
    }

    private func appCard(_ app: LanguagesModel.LangApp) -> some View {
        Card(minHeight: 104) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.id))
                        .resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(loc.t("lang.count", app.langs.count))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(humanBytes(app.bytes))
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(MTColor.mac)
                }
                langChips(app.langs)
            }
        }
    }

    /// Pastilles de langue, tronquées au-delà de 12 pour rester lisibles.
    private func langChips(_ langs: [String]) -> some View {
        let shown = Array(langs.prefix(12))
        let extra = langs.count - shown.count
        return FlexWrap(shown.map { $0 } + (extra > 0 ? ["+\(extra)"] : [])) { tag in
            Text(tag)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(MTColor.surface))
                .foregroundStyle(.secondary)
        }
    }

    private var promptState: some View {
        infoBox(icon: "globe", text: loc.t("lang.prompt"))
    }
    private var emptyState: some View {
        infoBox(icon: "checkmark.seal.fill", text: loc.t("lang.empty"))
    }
    private func infoBox(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(MTColor.mac)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MTColor.ligne, lineWidth: 1))
    }
}

/// Disposition « qui passe à la ligne » pour un lot d'étiquettes de largeur variable.
struct FlexWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    init(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items; self.content = content
    }
    var body: some View {
        // Grille adaptative simple : suffisante pour de courtes pastilles.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 90), spacing: 4)],
                  alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}
