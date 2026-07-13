//
//  DashboardView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : Dashboard

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @EnvironmentObject var loc: L10n
    private var s: SysSnapshot { model.snap }

    private let statHeight: CGFloat = 236

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                systemCard.riseIn()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                          spacing: 16) {
                    cpuCard.riseIn(0.06)
                    memCard.riseIn(0.12)
                    diskCard.riseIn(0.18)
                    netCard.riseIn(0.24)
                }
                if model.fanCount > 0 { fanCard.riseIn(0.30) }
            }
            .tabContent()
        }
        .background(dashboardBackground)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// En-tête uniforme pour chaque carte statistique.
    private func statHeader(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }

    private var dashboardBackground: some View {
        MTColor.fond.ignoresSafeArea()
    }

    private var systemCard: some View {
        Card {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(AppInfo.name).font(.title2.weight(.bold))
                        Text("v\(AppInfo.version)").font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    Text("\(SysInfo.chip)  ·  \(SysInfo.totalCores) \(loc.t("dash.cpu.cores"))  ·  \(humanBytesShort(s.memTotal))")
                        .font(.callout).foregroundStyle(.secondary)
                    TricoloreBar(width: 72).padding(.top, 3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Label("macOS \(SysCompat.macOSMajor)", systemImage: "apple.logo")
                        .font(.callout.weight(.medium))
                    HStack(spacing: 10) {
                        if s.hasBattery {
                            Label("\(s.batteryPercent)%",
                                  systemImage: batteryIcon(s.batteryPercent, s.batteryCharging))
                                .font(.caption).foregroundStyle(batteryColor(s.batteryPercent))
                        }
                        Text(SysInfo.uptime).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func batteryIcon(_ pct: Int, _ charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch pct {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<70: return "battery.50"
        case ..<90: return "battery.75"
        default:    return "battery.100"
        }
    }
    private func batteryColor(_ pct: Int) -> Color {
        pct < 20 ? MTColor.rouge : (pct < 40 ? MTColor.ambre : .green)
    }

    private var cpuCard: some View {
        Card(minHeight: statHeight) {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(loc.t("dash.cpu"), "cpu", MTColor.ambre)
                RingGauge(value: s.cpuTotal, gradient: [.green, .yellow, .orange, .red],
                          center: "\(Int(s.cpuTotal * 100))%", sub: loc.t("dash.cpu.load"), size: 108)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(s.cpuPerCore.enumerated()), id: \.offset) { _, v in
                        MiniBar(value: v, color: .accentColor).frame(maxWidth: .infinity, maxHeight: 28)
                    }
                }
                HStack {
                    Text("\(s.cpuPerCore.count) \(loc.t("dash.cpu.cores"))").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if s.cpuTemp > 0 {
                        Label("\(Int(s.cpuTemp)) °C", systemImage: "thermometer.medium")
                            .font(.caption2).foregroundStyle(tempColor(s.cpuTemp))
                    }
                }
            }
        }
    }
    private func tempColor(_ t: Float) -> Color {
        t < 60 ? .green : (t < 85 ? MTColor.ambre : MTColor.rouge)
    }

    private var memCard: some View {
        Card(minHeight: statHeight) {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(loc.t("dash.mem"), "memorychip", .purple)
                RingGauge(value: s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0,
                          gradient: [.blue, .purple, .pink],
                          center: humanBytesShort(s.memUsed), sub: "\(loc.t("dash.mem.on")) \(humanBytesShort(s.memTotal))", size: 108)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    memRow(loc.t("dash.mem.wired"), s.memWired, .purple)
                    memRow(loc.t("dash.mem.comp"), s.memCompressed, .pink)
                    memRow(loc.t("dash.mem.apps"), s.memApp, .blue)
                }
            }
        }
    }
    private func memRow(_ label: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(humanBytesShort(bytes)).font(.caption2.monospacedDigit())
        }
    }

    private var diskCard: some View {
        Card(minHeight: statHeight) {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(loc.t("dash.disk"), "internaldrive", .teal)
                RingGauge(value: s.diskTotal > 0 ? Double(s.diskUsed) / Double(s.diskTotal) : 0,
                          gradient: [.teal, .green],
                          center: humanBytesShort(s.diskUsed), sub: "\(loc.t("dash.mem.on")) \(humanBytesShort(s.diskTotal))", size: 108)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    ioRow(loc.t("dash.disk.read"), s.diskReadRate, "arrow.down.circle.fill", .green)
                    ioRow(loc.t("dash.disk.write"), s.diskWriteRate, "arrow.up.circle.fill", MTColor.ambre)
                }
                Label("\(humanBytesShort(s.diskTotal - s.diskUsed)) \(loc.t("dash.disk.free"))", systemImage: "checkmark.circle")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Débit disque compact (lecture ou écriture) : icône qui pulse quand ça transfère.
    private func ioRow(_ label: String, _ rate: Double, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(rateString(rate)).font(.caption2.monospacedDigit())
                .contentTransition(.numericText())
                .animation(.default, value: rateString(rate))
        }
    }

    private var netCard: some View {
        Card(minHeight: statHeight) {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(loc.t("dash.net"), "network", .blue)
                Spacer(minLength: 0)
                netRow(loc.t("dash.net.down"), s.netInRate, "arrow.down.circle.fill", .green)
                Divider()
                netRow(loc.t("dash.net.up"), s.netOutRate, "arrow.up.circle.fill", .blue)
                Spacer(minLength: 0)
                Divider()
                HStack(spacing: 8) {
                    if model.speedTesting {
                        ProgressView().controlSize(.small)
                        Text(loc.t("net.testing")).font(.caption2).foregroundStyle(.secondary)
                    } else if let mbps = model.speedMbps {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.caption).foregroundStyle(MTColor.bleu)
                        Text(loc.t("net.result", String(format: "%.0f", mbps)))
                            .font(.caption.weight(.semibold)).monospacedDigit()
                    } else {
                        Text(loc.t("dash.net.live")).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(loc.t("net.test")) { model.runSpeedTest() }
                        .controlSize(.small)
                        .disabled(model.speedTesting)
                }
            }
        }
    }
    private func netRow(_ label: String, _ rate: Double, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(rateString(rate)).font(.callout.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.default, value: rateString(rate))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var fanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(loc.t("fan.title"), systemImage: "fanblades.fill")
                        .font(.headline).foregroundStyle(.cyan)
                    Spacer()
                    Text(model.manualMode ? loc.t("fan.modeManual") : loc.t("fan.modeAuto"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background((model.manualMode ? MTColor.ambre : Color.green).opacity(0.18))
                        .foregroundStyle(model.manualMode ? MTColor.ambre : .green)
                        .clipShape(Capsule())
                    if model.applying { ProgressView().controlSize(.small) }
                }
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 12) {
                        RingGauge(value: fanFraction, gradient: [.cyan, .blue, .indigo],
                                  center: "\(Int(s.fanRPM))", sub: loc.t("fan.rpm"), size: 140,
                                  spinRPM: Double(s.fanRPM))
                        FanScale(rpm: Double(s.fanRPM), minRPM: Double(s.fanMin),
                                 maxRPM: Double(s.fanMax),
                                 target: model.manualMode ? model.targetRPM : nil,
                                 minLabel: loc.t("fan.silent"), maxLabel: loc.t("fan.max"))
                            .frame(width: 160)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        if SysCompat.fanControlAllowed {
                            Toggle(isOn: Binding(get: { model.manualMode },
                                                 set: { model.applyManual($0) })) {
                                Text(loc.t("fan.manualToggle")).font(.callout.weight(.medium))
                            }
                            .toggleStyle(.switch)

                            if model.manualMode {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(loc.t("fan.target")) : \(Int(model.targetRPM)) \(loc.t("fan.rpm"))")
                                        .font(.callout.weight(.semibold)).monospacedDigit()
                                        .contentTransition(.numericText())
                                        .animation(.default, value: Int(model.targetRPM))
                                    Slider(value: $model.targetRPM,
                                           in: Double(max(s.fanMin, 1))...Double(max(s.fanMax, s.fanMin + 1)))
                                    .tint(MTColor.bleu)
                                    HStack(spacing: 8) {
                                        ForEach([(loc.t("fan.preset.silent"), s.fanMin),
                                                 (loc.t("fan.preset.medium"), (s.fanMin + s.fanMax) / 2),
                                                 (loc.t("fan.preset.max"), s.fanMax)], id: \.0) { preset in
                                            Button(preset.0) {
                                                model.targetRPM = Double(preset.1)
                                            }.buttonStyle(.bordered).controlSize(.small)
                                        }
                                        Spacer()
                                        Button(loc.t("fan.apply")) { model.commitRPM() }
                                            .buttonStyle(DarkButton())
                                            .disabled(model.applying
                                                      || Int(model.targetRPM) == Int(model.appliedRPM))
                                    }
                                }
                                Toggle(isOn: Binding(get: { model.startupOn },
                                                     set: { model.toggleStartup($0) })) {
                                    Label(loc.t("fan.startup"), systemImage: "power")
                                        .font(.callout)
                                }
                                .toggleStyle(.switch)
                            }
                            Label(model.manualMode ? loc.t("fan.safe.manual") : loc.t("fan.safe.auto"),
                                  systemImage: "checkmark.shield.fill")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Label(loc.t("fan.blocked"), systemImage: "exclamationmark.triangle.fill")
                                .font(.callout.weight(.medium)).foregroundStyle(MTColor.ambre)
                            Text(loc.t("fan.blocked.desc"))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private var fanFraction: Double {
        let range = Double(s.fanMax - s.fanMin)
        guard range > 0 else { return 0 }
        return Double(s.fanRPM - s.fanMin) / range
    }
}

