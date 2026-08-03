//
//  SystemInfoView.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Données système + accès rapides

/// Un raccourci : soit un volet de Réglages Système (schéma x-apple.systempreferences),
/// soit une app utilitaire à ouvrir par son chemin.
private struct QuickItem: Identifiable {
    let id = UUID()
    let label: LStr
    let icon: String
    let tint: Color
    let action: () -> Void

    static func pane(_ label: LStr, _ icon: String, _ tint: Color, _ anchor: String) -> QuickItem {
        QuickItem(label: label, icon: icon, tint: tint) {
            if let url = URL(string: "x-apple.systempreferences:\(anchor)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    static func app(_ label: LStr, _ icon: String, _ tint: Color, _ path: String) -> QuickItem {
        QuickItem(label: label, icon: icon, tint: tint) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

struct DisplayInfo: Identifiable {
    let id = UUID()
    let name: String
    let pixels: String
    let scale: String
}

struct SystemInfoView: View {
    @EnvironmentObject var loc: L10n

    private let quickCols = [GridItem(.adaptive(minimum: 210), spacing: 12)]
    private let quickHeight: CGFloat = 58

    // Volets de Réglages Système que l'on cherche souvent longtemps (macOS 26/27).
    private var settingsPanes: [QuickItem] {
        [
            .pane(LStr("Ouverture au login", "Login items"), "person.badge.clock.fill", .orange, "com.apple.LoginItems-Settings.extension"),
            .pane(LStr("Accès complet au disque", "Full Disk Access"), "externaldrive.badge.checkmark", .green, "com.apple.preference.security?Privacy_AllFiles"),
            .pane(LStr("Confidentialité & sécurité", "Privacy & Security"), "hand.raised.fill", .blue, "com.apple.settings.PrivacySecurity.extension"),
            .pane(LStr("Moniteurs", "Displays"), "display", .cyan, "com.apple.Displays-Settings.extension"),
            .pane(LStr("Stockage", "Storage"), "internaldrive.fill", .purple, "com.apple.settings.Storage"),
            .pane(LStr("Batterie", "Battery"), "battery.100.bolt", .green, "com.apple.Battery-Settings.extension"),
            .pane(LStr("Réseau", "Network"), "network", .blue, "com.apple.Network-Settings.extension"),
            .pane(LStr("Bluetooth", "Bluetooth"), "dot.radiowaves.right", .blue, "com.apple.BluetoothSettings"),
            .pane(LStr("Son", "Sound"), "speaker.wave.2.fill", .pink, "com.apple.Sound-Settings.extension"),
            .pane(LStr("Notifications", "Notifications"), "bell.badge.fill", .red, "com.apple.Notifications-Settings.extension"),
            .pane(LStr("Mise à jour logicielle", "Software Update"), "arrow.triangle.2.circlepath", .indigo, "com.apple.Software-Update-Settings.extension"),
            .pane(LStr("Date & heure", "Date & Time"), "clock.fill", .orange, "com.apple.Date-Time-Settings.extension"),
            .pane(LStr("Partage", "Sharing"), "square.and.arrow.up.on.square.fill", .teal, "com.apple.Sharing-Settings.extension"),
            .pane(LStr("Clavier", "Keyboard"), "keyboard.fill", .gray, "com.apple.Keyboard-Settings.extension"),
        ]
    }

    // Utilitaires macOS d'ordinaire enfouis dans /Applications/Utilities.
    private var utilities: [QuickItem] {
        let u = "/System/Applications/Utilities/"
        return [
            .app(LStr("Moniteur d'activité", "Activity Monitor"), "waveform.path.ecg", .green, u + "Activity Monitor.app"),
            .app(LStr("Utilitaire de disque", "Disk Utility"), "internaldrive", .blue, u + "Disk Utility.app"),
            .app(LStr("Informations système", "System Information"), "info.circle.fill", .cyan, u + "System Information.app"),
            .app(LStr("Console", "Console"), "terminal.fill", .purple, u + "Console.app"),
            .app(LStr("Terminal", "Terminal"), "chevron.left.forwardslash.chevron.right", .gray, u + "Terminal.app"),
            .app(LStr("Trousseau d'accès", "Keychain Access"), "key.fill", .orange, u + "Keychain Access.app"),
            .app(LStr("Capture d'écran", "Screenshot"), "camera.viewfinder", .pink, u + "Screenshot.app"),
            .app(LStr("Éditeur de script", "Script Editor"), "applescript.fill", .indigo, u + "Script Editor.app"),
        ]
    }

    private func diskInfo() -> (free: Int64, total: Int64) {
        let v = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (Int64(v?.volumeAvailableCapacityForImportantUsage ?? 0),
                Int64(v?.volumeTotalCapacity ?? 0))
    }

    private var displays: [DisplayInfo] {
        NSScreen.screens.map { s in
            let px = "\(Int(s.frame.width * s.backingScaleFactor)) × \(Int(s.frame.height * s.backingScaleFactor))"
            return DisplayInfo(name: s.localizedName,
                               pixels: px,
                               scale: s.backingScaleFactor > 1.5 ? "Retina @\(Int(s.backingScaleFactor))x" : "@\(Int(s.backingScaleFactor))x")
        }
    }

    /// Caractéristiques principales, façon « À propos de ce Mac ».
    private var specRows: [(String, String)] {
        let mem = Int64(SysInfo.int("hw.memsize"))
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        var rows: [(String, String)] = [
            (loc.t("info.host"), host),
            (loc.t("info.chip"), SysInfo.chip),
            (loc.t("info.cores"), "\(SysInfo.totalCores) (\(SysInfo.pCores)P + \(SysInfo.eCores)E)"),
            (loc.t("info.gpu"),
             GPUInfo.cores > 0 ? "\(GPUInfo.name) · \(GPUInfo.cores) \(loc.t("dash.cpu.cores"))" : GPUInfo.name),
            (loc.t("info.memory"), humanBytesShort(mem)),
        ]
        if !HardwareInfo.serial.isEmpty { rows.append((loc.t("info.serial"), HardwareInfo.serial)) }
        rows.append((loc.t("info.os"), SysCompat.osName))
        rows.append((loc.t("info.uptime"), SysInfo.uptime))
        let bat = BatteryHealth.read()
        if bat.present {
            rows.append((loc.t("info.battery"), "\(bat.healthPct)% · \(bat.condition)"))
            rows.append((loc.t("info.cycles"), "\(bat.cycles)"))
        }
        return rows
    }

    private var monitorRows: [(String, String)] {
        displays.enumerated().map { i, d in
            let name = displays.count > 1 ? "\(loc.t("info.display")) \(i + 1)" : d.name
            return (name, "\(d.pixels) · \(d.scale)")
        }
    }

    private var storageRows: [(String, String)] {
        let disk = diskInfo()
        return [(loc.t("info.disk"), loc.t("info.disk.val", humanBytes(disk.free), humanBytes(disk.total)))]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "info.circle.fill", tint: MTColor.mac,
                      title: loc.t("info.title"), subtitle: loc.t("info.subtitle")) {
                Text(SysCompat.isAppleSilicon ? "Apple Silicon" : "Intel")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background((SysCompat.isAppleSilicon ? Color.green : Color.red).opacity(0.16))
                    .foregroundStyle(SysCompat.isAppleSilicon ? Color.green : .red)
                    .clipShape(Capsule())
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Colonne « À propos de ce Mac » centrée, comme le panneau d'Apple.
                    VStack(alignment: .leading, spacing: 14) {
                        appleHeader
                        listCard(specRows)
                        if !monitorRows.isEmpty {
                            labeledCard(loc.t("info.sec.monitors"), monitorRows)
                        }
                        labeledCard(loc.t("info.sec.storage"), storageRows)
                    }
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 6)

                    section(loc.t("info.sec.panes"))
                    LazyVGrid(columns: quickCols, spacing: 12) {
                        ForEach(settingsPanes) { quickTile($0) }
                    }

                    section(loc.t("info.sec.utils"))
                    LazyVGrid(columns: quickCols, spacing: 12) {
                        ForEach(utilities) { quickTile($0) }
                    }

                    StartupSection()
                }
                .tabContent()
            }
            .background(MTColor.fond)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
    }

    /// En-tête façon Apple : image du modèle (symbole SF), nom marketing, puce.
    private var appleHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: HardwareInfo.symbol)
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(MTColor.mac.gradient)
                .frame(height: 76)
            Text(HardwareInfo.modelName).font(.title.weight(.semibold))
            Text(SysInfo.chip).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 2)
    }

    /// Petit titre de section suivi d'une carte-liste (pour Moniteurs, Stockage).
    private func labeledCard(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            listCard(rows)
        }
    }

    /// Liste de paires libellé/valeur dans une carte, séparées par des filets, le
    /// même rendu que les tableaux de « À propos de ce Mac ».
    private func listCard(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Text(row.1).font(.callout.weight(.medium))
                        .multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .padding(.vertical, 11).padding(.horizontal, 16)
                if i < rows.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MTColor.ligne, lineWidth: 1))
    }

    private func quickTile(_ item: QuickItem) -> some View {
        Button(action: item.action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon).font(.body).foregroundStyle(item.tint).frame(width: 24)
                Text(item.label.current).font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: quickHeight, maxHeight: quickHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MTColor.ligne, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
