//
//  DiskEngine.swift · MacTuner
//
import Foundation
import CryptoKit
import AppKit

// MARK: - Moteur : espace disque (volumineux, doublons, installeurs, répartition)

enum DiskEngine {
    struct FileItem: Identifiable, Hashable {
        let id: String
        let path: String
        let name: String
        let bytes: Int64
        var isDir: Bool = false
    }

    static var home: String { NSHomeDirectory() }

    /// Dossiers personnels analysés. On évite ~/Library (système, très volumineux).
    static let scanRoots = ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"]

    private static func enumerateFiles(_ root: String) -> [FileItem] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let en = fm.enumerator(at: URL(fileURLWithPath: root),
                                     includingPropertiesForKeys: Array(keys),
                                     options: [.skipsHiddenFiles]) else { return [] }
        var items = [FileItem]()
        for case let f as URL in en {
            let v = try? f.resourceValues(forKeys: keys)
            if v?.isSymbolicLink == true || v?.isDirectory == true { continue }
            items.append(FileItem(id: f.path, path: f.path,
                                  name: f.lastPathComponent, bytes: Int64(v?.fileSize ?? 0)))
        }
        return items
    }

    static func largeFiles(minBytes: Int64) -> [FileItem] {
        var result = [FileItem]()
        for r in scanRoots {
            let full = "\(home)/\(r)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue
            else { continue }
            result += enumerateFiles(full).filter { $0.bytes >= minBytes }
        }
        return result.sorted { $0.bytes > $1.bytes }
    }

    static func oldInstallers(days: Int = 30) -> [FileItem] {
        let exts: Set<String> = ["dmg", "pkg", "iso", "zip", "xip", "cdr", "tar", "gz"]
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let fm = FileManager.default
        var result = [FileItem]()
        // Téléchargements ET Bureau : les installeurs finissent aussi souvent là.
        for dir in ["\(home)/Downloads", "\(home)/Desktop"] {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for e in entries where exts.contains((e as NSString).pathExtension.lowercased()) {
                let p = "\(dir)/\(e)"
                let attr = try? fm.attributesOfItem(atPath: p)
                let mdate = (attr?[.modificationDate] as? Date) ?? Date()
                guard mdate < cutoff else { continue }
                let size = (attr?[.size] as? NSNumber)?.int64Value ?? 0
                result.append(FileItem(id: p, path: p, name: e, bytes: size))
            }
        }
        return result.sorted { $0.bytes > $1.bytes }
    }

    /// Empreinte rapide : taille + échantillons début/fin. Suffit pour repérer des
    /// doublons sans lire des fichiers entiers de plusieurs Go.
    private static func quickHash(_ path: String, size: Int64) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let sample = 262_144
        var hasher = SHA256()
        hasher.update(data: withUnsafeBytes(of: size.littleEndian) { Data($0) })
        if let head = try? fh.read(upToCount: sample) { hasher.update(data: head) }
        if size > Int64(sample) * 2 {
            try? fh.seek(toOffset: UInt64(size - Int64(sample)))
            if let tail = try? fh.read(upToCount: sample) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Groupes de fichiers identiques (taille puis empreinte) sous un dossier.
    static func duplicates(root: String) -> [[FileItem]] {
        let files = enumerateFiles(root).filter { $0.bytes > 4096 }
        var bySize = [Int64: [FileItem]]()
        for f in files { bySize[f.bytes, default: []].append(f) }
        var groups = [[FileItem]]()
        for (_, group) in bySize where group.count > 1 {
            var byHash = [String: [FileItem]]()
            for f in group {
                guard let h = quickHash(f.path, size: f.bytes) else { continue }
                byHash[h, default: []].append(f)
            }
            for (_, g) in byHash where g.count > 1 { groups.append(g.sorted { $0.path < $1.path }) }
        }
        return groups.sorted { ($0.first?.bytes ?? 0) > ($1.first?.bytes ?? 0) }
    }

    /// Répartition : poids de chaque dossier de premier niveau du dossier personnel.
    static func folderBreakdown() -> [FileItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: home) else { return [] }
        var result = [FileItem]()
        for e in entries where !e.hasPrefix(".") {
            let p = "\(home)/\(e)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
            let out = Shell.run("/usr/bin/du", ["-sk", p])
            let kb = Int64(out.split(separator: "\t").first ?? "") ?? 0
            result.append(FileItem(id: p, path: p, name: e, bytes: kb * 1024, isDir: true))
        }
        return result.sorted { $0.bytes > $1.bytes }
    }

    /// Envoie les chemins à la Corbeille. Filtre dédié `isSelectedFileDeletable` :
    /// ici l'utilisateur coche chaque FICHIER un par un après l'avoir vu, donc les
    /// dossiers personnels (Téléchargements, Bureau, Documents…) sont admis — ce que
    /// `isDeletable`, taillé pour le nettoyage en masse par catégorie, refuse. Sans ce
    /// filtre, l'onglet Espace ne pouvait supprimer aucun des fichiers qu'il listait.
    @discardableResult
    static func trash(_ paths: [String]) -> Int64 {
        var freed: Int64 = 0
        let fm = FileManager.default
        var journal = [DeletionRecord]()
        for p in paths where SafetyGuard.isSelectedFileDeletable(p) {
            let attr = try? fm.attributesOfItem(atPath: p)
            let size = (attr?[.size] as? NSNumber)?.int64Value ?? 0
            if (try? fm.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)) != nil {
                freed += size
                journal.append(DeletionRecord(date: Date(), path: p, bytes: size, source: "disk"))
            }
        }
        ActionLog.append(journal)
        return freed
    }
}
