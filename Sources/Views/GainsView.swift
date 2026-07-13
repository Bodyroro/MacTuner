//
//  GainsView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : gains (bilan mesuré)

/// Tuile de statistique sobre, style « surface » du site : valeur en grand,
/// libellé dessous, icône discrète. Aucun effet de survol.
struct GainStat: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon).font(.callout).foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: value)
            Text(label)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MTColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(MTColor.ligne, lineWidth: 1))
    }
}

struct GainsView: View {
    @ObservedObject var tuner: TunerModel
    @ObservedObject var clean: CleanModel
    @ObservedObject var uninstall: UninstallModel
    @EnvironmentObject var loc: L10n

    private var activeUsage: [(tweak: Tweak, usage: TweakUsage)] {
        allTweaks
            .compactMap { t in tuner.tweakUsage[t.id].map { (tweak: t, usage: $0) } }
            .filter { $0.usage.procs > 0 }
            .sorted { $0.usage.rssBytes > $1.usage.rssBytes }
    }
    private var liveRSS: Int64 { activeUsage.reduce(0) { $0 + $1.usage.rssBytes } }
    private var liveCPU: Double { activeUsage.reduce(0) { $0 + $1.usage.cpuSeconds } }
    private var liveProcs: Int { activeUsage.reduce(0) { $0 + $1.usage.procs } }
    private var maxRSS: Int64 { max(activeUsage.first?.usage.rssBytes ?? 1, 1) }

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "speedometer",
                      title: loc.t("gains.title"),
                      subtitle: loc.t("gains.subtitle")) {
                if tuner.busy { ProgressView().controlSize(.small) }
                Button(loc.t("gains.refresh")) { tuner.refresh() }
                    .disabled(tuner.busy)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                // Bilan réalisé : ce que MacTuner a déjà libéré.
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc.t("gains.yours")).font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                  spacing: 10) {
                            GainStat(icon: "memorychip.fill", color: MTColor.bleu,
                                     value: humanBytes(tuner.freedMemBytes),
                                     label: loc.t("gains.ramFreed"))
                            GainStat(icon: "xmark.octagon.fill", color: MTColor.rouge,
                                     value: "\(tuner.freedProcs)",
                                     label: loc.t("gains.procs"))
                            GainStat(icon: "internaldrive.fill", color: .teal,
                                     value: humanBytes(clean.totalFreedEver),
                                     label: loc.t("gains.diskFreed"))
                            GainStat(icon: "xmark.bin.fill", color: MTColor.mac,
                                     value: humanBytes(uninstall.totalUninstalledEver),
                                     label: loc.t("gains.appsFreed"))
                        }
                    }
                }
                .riseIn(0.06)

                // Encore récupérable : mesures en direct.
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc.t("gains.potential")).font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                                  spacing: 10) {
                            GainStat(icon: "memorychip", color: MTColor.bleu,
                                     value: humanBytes(liveRSS),
                                     label: loc.t("gains.liveRAM", liveProcs))
                            GainStat(icon: "timer", color: MTColor.ambre,
                                     value: humanCPU(liveCPU),
                                     label: loc.t("gains.liveCPU"))
                            GainStat(icon: "sparkles", color: .teal,
                                     value: clean.hasScanned ? humanBytes(clean.totalBytes) : "—",
                                     label: clean.hasScanned ? loc.t("gains.reclaimable")
                                                             : loc.t("gains.reclaimHint"))
                        }
                    }
                }
                .riseIn(0.12)

                // Services Apple encore actifs, du plus gourmand au plus discret.
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc.t("gains.activeServices")).font(.headline)
                        if activeUsage.isEmpty {
                            Text(tuner.busy ? loc.t("gains.measuring") : loc.t("gains.noData"))
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(activeUsage, id: \.tweak.id) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Image(systemName: entry.tweak.icon)
                                                .font(.callout)
                                                .foregroundStyle(MTColor.mac)
                                                .frame(width: 20)
                                            Text(entry.tweak.name.current)
                                                .font(.callout.weight(.medium))
                                            Spacer()
                                            Text(loc.t("gains.procShort", entry.usage.procs,
                                                       humanBytes(entry.usage.rssBytes),
                                                       humanCPU(entry.usage.cpuSeconds)))
                                                .font(.caption).monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(MTColor.surface)
                                                Capsule().fill(MTColor.bleu.opacity(0.75))
                                                    .frame(width: max(4, geo.size.width
                                                        * CGFloat(Double(entry.usage.rssBytes) / Double(maxRSS))))
                                            }
                                        }
                                        .frame(height: 5)
                                        .padding(.leading, 28)
                                    }
                                }
                            }
                        }
                    }
                }
                .riseIn(0.18)

                Label(loc.t("gains.note"), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .tabContent()
            }
            .background(MTColor.fond)
        }
        .onAppear { tuner.refresh() }
    }
}
