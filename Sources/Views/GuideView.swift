//
//  GuideView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : guide

struct GuideCard: View {
    let icon: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(color.opacity(0.22), lineWidth: 1))
    }
}

struct GuideSection: View {
    let number: Int
    let title: String
    let subtitle: String
    let cards: [(String, Color, String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.callout.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(cards, id: \.0) { c in
                GuideCard(icon: c.0, color: c.1, title: c.2, text: c.3)
            }
        }
    }
}

struct GuideView: View {
    @EnvironmentObject var loc: L10n
    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "book.closed.fill",
                      title: loc.t("guide.title"),
                      subtitle: loc.t("guide.intro")) { EmptyView() }
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GuideSection(number: 1, title: loc.t("guide.s1"), subtitle: loc.t("guide.s1.sub"), cards: [
                    ("gauge.with.dots.needle.67percent", .cyan, loc.t("guide.dash.t"), loc.t("guide.dash.d")),
                    ("fanblades.fill", .blue, loc.t("guide.fan.t"), loc.t("guide.fan.d")),
                    ("speedometer", MTColor.ambre, loc.t("guide.gains.t"), loc.t("guide.gains.d")),
                ])

                GuideSection(number: 2, title: loc.t("guide.s2"), subtitle: loc.t("guide.s2.sub"), cards: [
                    ("switch.2", .blue, loc.t("guide.feat.t"), loc.t("guide.feat.d")),
                    ("wrench.and.screwdriver", .indigo, loc.t("guide.maint.t"), loc.t("guide.maint.d")),
                ])

                GuideSection(number: 3, title: loc.t("guide.s3"), subtitle: loc.t("guide.s3.sub"), cards: [
                    ("trash", .teal, loc.t("guide.clean.t"), loc.t("guide.clean.d")),
                    ("xmark.bin.fill", .red, loc.t("guide.uninst.t"), loc.t("guide.uninst.d")),
                ])

                GuideSection(number: 4, title: loc.t("guide.s4"), subtitle: loc.t("guide.s4.sub"), cards: [
                    ("shield.lefthalf.filled", .green, loc.t("guide.guard.t"), loc.t("guide.guard.d")),
                    ("checkmark.seal.fill", .mint, loc.t("guide.compat.t"), loc.t("guide.compat.d")),
                ])
            }
            .tabContent()
            }
            .background(MTColor.fond)
        }
    }
}

