//
//  SMC.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - SMC : lecture des capteurs, écriture (root) du ventilateur

enum SMC {
    private static var conn: io_connect_t = 0
    private static var opened = false

    @discardableResult
    static func open() -> Bool {
        if opened { return conn != 0 }
        opened = true
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return false }
        let r = IOServiceOpen(svc, mach_task_self_, 0, &conn)
        IOObjectRelease(svc)
        return r == kIOReturnSuccess
    }

    private static func fourCC(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for c in s.utf8 { r = (r << 8) + UInt32(c) }
        return r
    }

    private static func call(_ input: inout SMCParamStruct, _ output: inout SMCParamStruct) -> kern_return_t {
        let size = MemoryLayout<SMCParamStruct>.stride
        var outSize = size
        return IOConnectCallStructMethod(conn, 2, &input, size, &output, &outSize)
    }

    private static func keyInfo(_ key: String) -> (size: UInt32, type: UInt32)? {
        guard open() else { return nil }
        var i = SMCParamStruct(); i.key = fourCC(key); i.data8 = 9
        var o = SMCParamStruct()
        guard call(&i, &o) == kIOReturnSuccess else { return nil }
        return (o.keyInfo.dataSize, o.keyInfo.dataType)
    }

    private static func bytesTuple(_ o: SMCParamStruct) -> [UInt8] {
        var b = o.bytes
        return withUnsafeBytes(of: &b) { Array($0) }
    }

    static func readBytes(_ key: String) -> [UInt8]? {
        guard let ki = keyInfo(key), ki.size > 0 else { return nil }
        var i = SMCParamStruct(); i.key = fourCC(key); i.keyInfo.dataSize = ki.size; i.data8 = 5
        var o = SMCParamStruct()
        guard call(&i, &o) == kIOReturnSuccess else { return nil }
        return Array(bytesTuple(o).prefix(Int(ki.size)))
    }

    static func readFloat(_ key: String) -> Float? {
        guard let b = readBytes(key), b.count >= 4 else { return nil }
        return [b[0], b[1], b[2], b[3]].withUnsafeBytes { $0.load(as: Float.self) }
    }

    static func readUInt8(_ key: String) -> UInt8? { readBytes(key)?.first }

    /// Écrit des octets (nécessite root). Renvoie true si accepté par le SMC.
    @discardableResult
    static func writeBytes(_ key: String, _ data: [UInt8]) -> Bool {
        guard let ki = keyInfo(key), Int(ki.size) == data.count else { return false }
        var i = SMCParamStruct(); i.key = fourCC(key); i.keyInfo.dataSize = ki.size; i.data8 = 6
        withUnsafeMutableBytes(of: &i.bytes) { raw in
            for (n, byte) in data.enumerated() where n < 32 { raw[n] = byte }
        }
        var o = SMCParamStruct()
        return call(&i, &o) == kIOReturnSuccess
    }

    static func writeFloat(_ key: String, _ value: Float) -> Bool {
        var v = value
        let bytes = withUnsafeBytes(of: &v) { Array($0) }
        return writeBytes(key, bytes)
    }

    // — Ventilateurs —
    static func fanCount() -> Int { Int(readUInt8("FNum") ?? 0) }
    static func fanRPM(_ i: Int) -> Float? { readFloat("F\(i)Ac") }
    static func fanMin(_ i: Int) -> Float? { readFloat("F\(i)Mn") }
    static func fanMax(_ i: Int) -> Float? { readFloat("F\(i)Mx") }
    static func fanTarget(_ i: Int) -> Float? { readFloat("F\(i)Tg") }
    static func fanForced(_ i: Int) -> Bool { (readUInt8("F\(i)Md") ?? 0) != 0 }

    /// Applique un réglage ventilateur (root requis). mode 1 = forcé, 0 = auto.
    static func applyFan(index: Int, mode: UInt8, rpm: Float) {
        if mode == 0 {
            _ = writeBytes("F\(index)Md", [0])          // retour au contrôle automatique
            // Filet de sécurité : si le SMC ne relâche pas tout de suite la cible
            // forcée, on la ramène au minimum constructeur (la ventilation redescend
            // au lieu de rester bloquée sur l'ancienne consigne).
            if let mn = fanMin(index) { _ = writeFloat("F\(index)Tg", mn) }
        } else {
            _ = writeBytes("F\(index)Md", [1])          // mode forcé
            _ = writeFloat("F\(index)Tg", rpm)          // vitesse cible
        }
    }

    // — Températures (moyenne des capteurs die CPU Apple Silicon) —
    static func cpuTemperature() -> Float? {
        // Clés de température des cœurs sur Apple Silicon (Tp0x/Tg0x selon puce).
        let keys = (1...16).flatMap { ["Tp0\(String($0, radix: 16))", "Tg0\(String($0, radix: 16))"] }
            + ["TC0P", "Tp09", "Tp01", "Tp05"]
        var vals = [Float]()
        for k in keys {
            if let t = readFloat(k), t > 10, t < 120 { vals.append(t) }
        }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Float(vals.count)
    }
}

