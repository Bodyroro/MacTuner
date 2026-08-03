//
//  StartupView.swift · MacTuner
//
import SwiftUI
import AppKit
import Darwin

// MARK: - Moteur : agents de démarrage (LaunchAgents)

enum StartupEngine {
    struct Agent: Identifiable {
        let id: String        // chemin du plist
        let label: String
        let path: String
        let system: Bool      // /Library/LaunchAgents (installé pour tous)
        var enabled: Bool
    }

    static var domain: String { "gui/\(getuid())" }

    private static func label(ofPlist path: String) -> String {
        let out = Shell.run("/usr/libexec/PlistBuddy", ["-c", "print Label", path])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || out.contains("Does Not Exist") {
            return (path as NSString).lastPathComponent.replacingOccurrences(of: ".plist", with: "")
        }
        return out
    }

    static func scan() -> [Agent] {
        let disabled = LaunchCtl.disabledServices()
        let fm = FileManager.default
        let dirs: [(String, Bool)] = [
            (NSHomeDirectory() + "/Library/LaunchAgents", false),
            ("/Library/LaunchAgents", true),
        ]
        var result = [Agent]()
        for (dir, system) in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in items.sorted() where f.hasSuffix(".plist") {
                let path = "\(dir)/\(f)"
                let lbl = label(ofPlist: path)
                result.append(Agent(id: path, label: lbl, path: path,
                                    system: system, enabled: !disabled.contains(lbl)))
            }
        }
        return result
    }

    static func setEnabled(_ agent: Agent, _ enabled: Bool) {
        if enabled {
            Shell.run("/bin/launchctl", ["enable", "\(domain)/\(agent.label)"])
            Shell.run("/bin/launchctl", ["bootstrap", domain, agent.path])
        } else {
            Shell.runResult("/bin/launchctl", ["bootout", "\(domain)/\(agent.label)"])
            Shell.run("/bin/launchctl", ["disable", "\(domain)/\(agent.label)"])
        }
    }
}

@MainActor
final class StartupModel: ObservableObject {
    @Published var agents: [StartupEngine.Agent] = []
    @Published var busy = false
    @Published var scanned = false

    var userAgents: [StartupEngine.Agent] { agents.filter { !$0.system } }
    var systemAgents: [StartupEngine.Agent] { agents.filter { $0.system } }

    func scan() {
        busy = true
        Task.detached(priority: .userInitiated) {
            let a = StartupEngine.scan()
            await MainActor.run { self.agents = a; self.busy = false; self.scanned = true }
        }
    }

    func toggle(_ agent: StartupEngine.Agent, _ enabled: Bool) {
        Task.detached(priority: .userInitiated) {
            StartupEngine.setEnabled(agent, enabled)
            let a = StartupEngine.scan()
            await MainActor.run { self.agents = a }
        }
    }
}

// MARK: - Section : démarrage (intégrée à l'onglet Système)

struct StartupSection: View {
    @StateObject private var model = StartupModel()
    @EnvironmentObject var loc: L10n

    private let columns = [GridItem(.adaptive(minimum: 420), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc.t("startup.title")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { model.scan() } label: {
                    Label(loc.t("common.refresh"), systemImage: "arrow.clockwise").font(.caption)
                }.buttonStyle(.plain).foregroundStyle(MTColor.mac).disabled(model.busy)
            }
            if model.scanned && model.agents.isEmpty {
                infoBox("checkmark.seal.fill", loc.t("startup.empty"))
            } else {
                if !model.userAgents.isEmpty { group(loc.t("startup.user"), model.userAgents) }
                if !model.systemAgents.isEmpty { group(loc.t("startup.system"), model.systemAgents) }
            }
        }
        .onAppear { if !model.scanned { model.scan() } }
    }

    private func group(_ title: String, _ agents: [StartupEngine.Agent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(agents) { agent in row(agent) }
            }
        }
    }

    private func row(_ agent: StartupEngine.Agent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: agent.enabled ? "bolt.circle.fill" : "bolt.slash.circle")
                .font(.title3).foregroundStyle(agent.enabled ? MTColor.mac : Color.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.label).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    if agent.system {
                        Text(loc.t("common.admin")).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15)).foregroundStyle(.purple).clipShape(Capsule())
                    }
                }
                Text((agent.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { agent.enabled }, set: { model.toggle(agent, $0) }))
                .labelsHidden().toggleStyle(.switch)
        }
        .padding(12)
        .frame(minHeight: 60)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MTColor.ligne, lineWidth: 1))
    }

    private func infoBox(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(MTColor.mac)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MTColor.ligne, lineWidth: 1))
    }
}
