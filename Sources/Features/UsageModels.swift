//
//  UsageModels.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Mesures de consommation

struct ProcUsage {
    let pid: Int32
    let rssBytes: Int64
    let cpuSeconds: Double
}

struct TweakUsage {
    let procs: Int
    let rssBytes: Int64
    let cpuSeconds: Double
}

