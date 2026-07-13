//
//  SystemStats.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Statistiques système temps réel

struct SysSnapshot {
    var cpuTotal: Double = 0          // 0…1
    var cpuPerCore: [Double] = []
    var memUsed: Int64 = 0
    var memTotal: Int64 = 0
    var memWired: Int64 = 0
    var memCompressed: Int64 = 0
    var memApp: Int64 = 0
    var swapUsed: Int64 = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var diskReadRate: Double = 0      // octets/s
    var diskWriteRate: Double = 0
    var netInRate: Double = 0         // octets/s
    var netOutRate: Double = 0
    var load: [Double] = [0, 0, 0]
    var fanRPM: Float = 0
    var fanMin: Float = 0
    var fanMax: Float = 0
    var fanForced = false
    var cpuTemp: Float = 0
    var hasBattery = false
    var batteryPercent = 0
    var batteryCharging = false
}

final class SysSampler {
    private var prevCPUTicks: [(sys: UInt32, user: UInt32, nice: UInt32, idle: UInt32)] = []
    private var prevNet: (inB: UInt64, outB: UInt64, time: CFTimeInterval)?
    private var prevDiskIO: (read: UInt64, written: UInt64, time: CFTimeInterval)?

    func sample() -> SysSnapshot {
        var s = SysSnapshot()
        sampleCPU(&s)
        sampleMem(&s)
        sampleDisk(&s)
        sampleDiskIO(&s)
        sampleNet(&s)
        var la = [Double](repeating: 0, count: 3)
        getloadavg(&la, 3); s.load = la
        if SMC.fanCount() > 0 {
            s.fanRPM = SMC.fanRPM(0) ?? 0
            s.fanMin = SMC.fanMin(0) ?? 0
            s.fanMax = SMC.fanMax(0) ?? 0
            s.fanForced = SMC.fanForced(0)
        }
        s.cpuTemp = SMC.cpuTemperature() ?? 0
        if let bat = Battery.info() {
            s.hasBattery = true
            s.batteryPercent = bat.percent
            s.batteryCharging = bat.charging
        }
        return s
    }

    private func sampleCPU(_ s: inout SysSnapshot) {
        var count = mach_msg_type_number_t()
        var info: processor_info_array_t?
        var ncpu: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count)
                == KERN_SUCCESS, let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                              vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var cur: [(sys: UInt32, user: UInt32, nice: UInt32, idle: UInt32)] = []
        for i in 0..<Int(ncpu) {
            let base = i * Int(CPU_STATE_MAX)
            cur.append((UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                        UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                        UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]),
                        UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])))
        }
        if prevCPUTicks.count == cur.count {
            var per = [Double](); var busySum = 0.0; var totSum = 0.0
            for i in 0..<cur.count {
                let dSys = Double(cur[i].sys &- prevCPUTicks[i].sys)
                let dUser = Double(cur[i].user &- prevCPUTicks[i].user)
                let dNice = Double(cur[i].nice &- prevCPUTicks[i].nice)
                let dIdle = Double(cur[i].idle &- prevCPUTicks[i].idle)
                let busy = dSys + dUser + dNice
                let tot = busy + dIdle
                per.append(tot > 0 ? busy / tot : 0)
                busySum += busy; totSum += tot
            }
            s.cpuPerCore = per
            s.cpuTotal = totSum > 0 ? busySum / totSum : 0
        }
        prevCPUTicks = cur
    }

    private func sampleMem(_ s: inout SysSnapshot) {
        var total: UInt64 = 0; var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        s.memTotal = Int64(total)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let page = Int64(vm_kernel_page_size)
        s.memWired = Int64(stats.wire_count) * page
        s.memCompressed = Int64(stats.compressor_page_count) * page
        let active = Int64(stats.active_count) * page
        s.memApp = active + Int64(stats.inactive_count) * page
        s.memUsed = s.memWired + s.memCompressed + active
    }

    private func sampleDisk(_ s: inout SysSnapshot) {
        var st = statfs()
        guard statfs("/", &st) == 0 else { return }
        let bs = Int64(st.f_bsize)
        s.diskTotal = Int64(st.f_blocks) * bs
        s.diskUsed = s.diskTotal - Int64(st.f_bavail) * bs
    }

    /// Débits disque (lecture/écriture) : cumul des statistiques de tous les
    /// pilotes de stockage IOKit, converti en octets/s par delta entre échantillons.
    private func sampleDiskIO(_ s: inout SysSnapshot) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var read: UInt64 = 0
        var written: UInt64 = 0
        var drive = IOIteratorNext(iter)
        while drive != 0 {
            if let cf = IORegistryEntryCreateCFProperty(drive, "Statistics" as CFString,
                                                        kCFAllocatorDefault, 0),
               let stats = cf.takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(drive)
            drive = IOIteratorNext(iter)
        }
        let now = CACurrentMediaTime()
        if let prev = prevDiskIO {
            let dt = now - prev.time
            if dt > 0 {
                s.diskReadRate = Double(read &- prev.read) / dt
                s.diskWriteRate = Double(written &- prev.written) / dt
            }
        }
        prevDiskIO = (read, written, now)
    }

    private func sampleNet(_ s: inout SysSnapshot) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return }
        defer { freeifaddrs(ifap) }
        var inB: UInt64 = 0; var outB: UInt64 = 0
        var p = ifap
        while let cur = p {
            if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                inB += UInt64(d.ifi_ibytes); outB += UInt64(d.ifi_obytes)
            }
            p = cur.pointee.ifa_next
        }
        let now = CACurrentMediaTime()
        if let prev = prevNet {
            let dt = now - prev.time
            if dt > 0 {
                s.netInRate = Double(inB &- prev.inB) / dt
                s.netOutRate = Double(outB &- prev.outB) / dt
            }
        }
        prevNet = (inB, outB, now)
    }
}

enum SysInfo {
    static func str(_ name: String) -> String {
        var size = 0; sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }
    static func int(_ name: String) -> Int {
        var v: Int = 0; var size = MemoryLayout<Int>.size
        sysctlbyname(name, &v, &size, nil, 0); return v
    }
    static var model: String { str("hw.model") }
    static var chip: String {
        let b = str("machdep.cpu.brand_string"); return b.isEmpty ? "Apple Silicon" : b
    }
    static var pCores: Int { int("hw.perflevel0.logicalcpu") }
    static var eCores: Int { int("hw.perflevel1.logicalcpu") }
    static var totalCores: Int { int("hw.ncpu") }
    static var uptime: String {
        var tv = timeval(); var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        let secs = Int(Date().timeIntervalSince1970) - tv.tv_sec
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d) j \(h) h" }
        if h > 0 { return "\(h) h \(m) min" }
        return "\(m) min"
    }
    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

