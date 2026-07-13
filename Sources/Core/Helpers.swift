//
//  Helpers.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

/// Format compact pour les jauges : peu de décimales, tient sur une ligne.
func humanBytesShort(_ b: Int64) -> String {
    let units = ["o", "KB", "MB", "GB", "TB"]
    var v = Double(max(b, 0)); var i = 0
    while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
    let num: String
    if i <= 1 || v >= 100 { num = String(format: "%.0f", v) }
    else { num = String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
    return "\(num) \(units[i])"
}

/// Batterie : nil sur un Mac de bureau (aucune source d'alimentation interne).
enum Battery {
    static func info() -> (percent: Int, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            if let cur = d[kIOPSCurrentCapacityKey as String] as? Int,
               let mx = d[kIOPSMaxCapacityKey as String] as? Int, mx > 0 {
                let state = d[kIOPSPowerSourceStateKey as String] as? String
                let charging = state == (kIOPSACPowerValue as String)
                return (Int((Double(cur) / Double(mx)) * 100), charging)
            }
        }
        return nil
    }
}

