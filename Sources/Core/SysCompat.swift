//
//  SysCompat.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Identité & compatibilité

enum AppInfo {
    // Lues depuis Info.plist : une seule source de vérité pour la version.
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3"
    static let name = "MacTuner"
    static let tagline = "Centre de contrôle, réglages et entretien pour Mac Apple Silicon."
    static let website = "https://bodyroro.github.io"
    static let repo = "https://github.com/Bodyroro/MacTuner"
    static let author = "Rodolphe Vandaele"
}

/// MacTuner cible Apple Silicon sous macOS 26 (Tahoe) et 27 (Golden Gate).
/// Les mécanismes utilisés (launchctl, defaults, SMC via IOKit) sont identiques
/// sur ces deux versions ; on bloque le contrôle SMC hors de ce périmètre pour
/// ne rien casser sur du matériel/OS non validé.
enum SysCompat {
    static var isAppleSilicon: Bool { SysInfo.int("hw.optional.arm64") == 1 }
    static var macOSMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }
    static var supportedOSRange: ClosedRange<Int> { 26...27 }
    static var isSupportedOS: Bool { supportedOSRange.contains(macOSMajor) }

    /// Le contrôle du ventilateur écrit dans le SMC : réservé au matériel/OS validé.
    static var fanControlAllowed: Bool { isAppleSilicon && isSupportedOS }

    static var osName: String {
        switch macOSMajor {
        case 26: return "macOS 26 Tahoe"
        case 27: return "macOS 27 Golden Gate"
        default: return SysInfo.macOS
        }
    }
    static var summary: String {
        (isAppleSilicon ? "Apple Silicon" : "Intel") + " · " + osName
            + (isSupportedOS ? "" : " (non validé)")
    }
}

