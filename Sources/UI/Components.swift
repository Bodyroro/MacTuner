//
//  Components.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Sélecteur de langue

/// Choix de langue élégant : deux pastilles drapeau + nom, la sélection remplie en accent.
struct LanguagePicker: View {
    @ObservedObject var loc: L10n
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Lang.allCases) { l in
                let selected = loc.lang == l
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { loc.set(l) }
                } label: {
                    HStack(spacing: 7) {
                        Text(l.flag).font(.title3)
                        Text(l.displayName).font(.callout.weight(.medium))
                        if selected {
                            Image(systemName: "checkmark.circle.fill").font(.caption)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(minWidth: 128)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.secondary.opacity(0.10))
                    )
                    .foregroundStyle(selected ? .white : .primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Animations partagées

/// Apparition « montée en fondu » façon site web (mt-item-in) : opacité + glissement,
/// avec un délai pour les entrées en cascade.
struct RiseIn: ViewModifier {
    var delay: Double = 0
    // State(initialValue:) direct : la toolchain CLI n'a pas la macro @State.
    private var shown = State(initialValue: false)
    init(delay: Double = 0) { self.delay = delay }
    func body(content: Content) -> some View {
        content
            .opacity(shown.wrappedValue ? 1 : 0)
            .offset(y: shown.wrappedValue ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                    shown.wrappedValue = true
                }
            }
    }
}

extension View {
    func riseIn(_ delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }
}

/// Hélice de ventilateur qui tourne réellement, à une vitesse visuelle
/// proportionnelle au régime (0 tr/min = à l'arrêt).
struct SpinningFan: View {
    let rpm: Double
    var size: CGFloat = 22
    var color: Color = .cyan

    var body: some View {
        Group {
            if rpm > 0 {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    // 0,25 → 2,5 tours/s visuels entre 0 et 6000 tr/min réels.
                    let turnsPerSec = 0.25 + min(rpm / 6000, 1) * 2.25
                    blades.rotationEffect(.degrees((t * turnsPerSec * 360)
                        .truncatingRemainder(dividingBy: 360)))
                }
            } else {
                blades
            }
        }
        .frame(width: size, height: size)
    }

    private var blades: some View {
        Image(systemName: "fanblades.fill")
            .font(.system(size: size))
            .foregroundStyle(color)
    }
}

// MARK: - Palette du site (bodyroro.github.io) : encre de nuit + tricolore

/// Couleurs reprises de assets/site.css — sombre biaisé bleu, jamais gris neutre.
enum MTColor {
    static let bleu = Color(red: 0.302, green: 0.490, blue: 1.0)        // #4d7dff
    static let rouge = Color(red: 0.961, green: 0.282, blue: 0.235)     // #f5483c
    static let blanc = Color(red: 0.949, green: 0.961, blue: 0.992)     // #f2f5fd
    static let nuit = Color(red: 0.039, green: 0.055, blue: 0.102)      // #0a0e1a
    static let nuitHaute = Color(red: 0.063, green: 0.086, blue: 0.165) // #10162a
    static let mac = Color(red: 0.557, green: 0.722, blue: 1.0)         // #8eb8ff
    // Ambre franc pour les avertissements : assez saturé et clair pour rester
    // « or » sur l'encre de nuit, là où un orange translucide virait au marron.
    static let ambre = Color(red: 1.0, green: 0.78, blue: 0.36)         // #ffc75c
    static let ligne = Color(red: 0.592, green: 0.678, blue: 1.0).opacity(0.14)
    static let surface = Color.white.opacity(0.045)
    // Fond de carte SOLIDE (bleu nuit élevé). Remplace .ultraThinMaterial, qui
    // se désaturait en gris-marron sur le dégradé de fond.
    static let carte = Color(red: 0.075, green: 0.098, blue: 0.176)        // #131928
    // Surfaces de bouton, élevées sur l'encre de nuit : sombres et cohérentes,
    // là où .borderedProminent grisait en brun quand un bouton était désactivé.
    static let bouton = Color(red: 0.102, green: 0.133, blue: 0.216)       // #1a2237
    static let boutonPresse = Color(red: 0.149, green: 0.188, blue: 0.294) // #26304b

    /// Fond « encre de nuit » commun aux vues à fond libre.
    static var fond: LinearGradient {
        LinearGradient(colors: [nuitHaute, nuit], startPoint: .top, endPoint: .bottom)
    }
}

/// Bouton d'action sombre et homogène pour toute l'app. Seul le texte/l'icône
/// porte l'accent (bleu par défaut, rouge pour les actions destructives) ; le
/// fond reste sombre dans tous les états, désactivé compris (fini le brun).
struct DarkButton: ButtonStyle {
    var accent: Color = MTColor.mac
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(configuration.isPressed ? MTColor.boutonPresse : MTColor.bouton))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(accent.opacity(configuration.isPressed ? 0.55 : 0.30), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Signature tricolore du site — volontairement rare : une seule par page.
struct TricoloreBar: View {
    var width: CGFloat = 64
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(MTColor.bleu)
            Rectangle().fill(MTColor.blanc)
            Rectangle().fill(MTColor.rouge)
        }
        .frame(width: width, height: 3)
        .clipShape(Capsule())
    }
}

// MARK: - Gabarit commun des onglets

/// En-tête d'onglet unique pour toute l'app : icône teintée, titre, sous-titre,
/// actions à droite. Toujours suivi d'un Divider par l'appelant.
struct TabHeader<Trailing: View>: View {
    let icon: String
    var tint: Color = MTColor.mac
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(12)
    }
}

/// Largeur et marge de contenu communes à tous les onglets.
enum TabLayout {
    static let maxWidth: CGFloat = 1400
    static let padding: CGFloat = 16
}

extension View {
    /// Applique le gabarit de contenu standard (padding + largeur maximale centrée).
    func tabContent() -> some View {
        self.padding(TabLayout.padding)
            .frame(maxWidth: TabLayout.maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Dashboard : composants

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var minHeight: CGFloat? = nil
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MTColor.ligne, lineWidth: 1))
    }
}

struct RingGauge: View {
    let value: Double            // 0…1
    let gradient: [Color]
    let center: String
    let sub: String
    var size: CGFloat = 118
    /// Régime réel : affiche une hélice qui tourne au-dessus de la valeur.
    var spinRPM: Double? = nil

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0.001, min(value, 1)))
                .stroke(AngularGradient(colors: gradient, center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: value)
            VStack(spacing: 2) {
                if let rpm = spinRPM {
                    SpinningFan(rpm: rpm, size: size * 0.16)
                }
                Text(center).font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                    .contentTransition(.numericText())
                    .animation(.default, value: center)
                Text(sub).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: size, height: size)
    }
}

struct MiniBar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.15))
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(height: max(2, geo.size.height * min(value, 1)))
                    .animation(.easeOut(duration: 0.4), value: value)
            }
        }
    }
}

/// Échelle de vitesse du ventilateur : piste dégradée, graduations, curseur de la
/// vitesse actuelle et, si présent, marqueur de la cible.
struct FanScale: View {
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double
    let target: Double?
    let minLabel: String
    let maxLabel: String

    private func frac(_ v: Double) -> Double {
        let range = maxRPM - minRPM
        guard range > 0 else { return 0 }
        return min(max((v - minRPM) / range, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Piste dégradée silencieux → rapide
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .cyan, .blue, .indigo],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                        .opacity(0.85)
                    // Graduations
                    HStack(spacing: 0) {
                        ForEach(0..<11) { i in
                            Rectangle().fill(.white.opacity(0.35))
                                .frame(width: 1, height: i % 5 == 0 ? 8 : 5)
                            if i < 10 { Spacer() }
                        }
                    }
                    .frame(height: 8)
                    // Marqueur de la cible (mode manuel)
                    if let t = target {
                        Circle().strokeBorder(.primary.opacity(0.5), lineWidth: 2)
                            .background(Circle().fill(.white))
                            .frame(width: 12, height: 12)
                            .offset(x: frac(t) * (w - 12))
                    }
                    // Curseur de la vitesse actuelle
                    Circle()
                        .fill(.white)
                        .overlay(Circle().fill(Color.blue).frame(width: 8, height: 8))
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .offset(x: frac(rpm) * (w - 16))
                        .animation(.easeOut(duration: 0.5), value: rpm)
                }
            }
            .frame(height: 16)
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(minRPM))").font(.caption2.weight(.semibold)).monospacedDigit()
                    Text(minLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(maxRPM))").font(.caption2.weight(.semibold)).monospacedDigit()
                    Text(maxLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

func rateString(_ bytesPerSec: Double) -> String {
    let b = Int64(max(0, bytesPerSec))
    if b < 1 { return "0 o/s" }
    return "\(ByteCountFormatter.string(fromByteCount: b, countStyle: .binary))/s"
}

