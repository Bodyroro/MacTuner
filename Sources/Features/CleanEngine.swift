//
//  CleanEngine.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Moteur : nettoyage

enum CleanEngine {

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Conteneurs sandbox dont l'app n'existe plus sur le Mac (jamais ceux d'Apple).
    static func orphanedContainers() -> [String] {
        let fm = FileManager.default
        let root = NSHomeDirectory() + "/Library/Containers"
        guard let items = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var result = [String]()
        for bid in items.sorted() {
            guard !bid.hasPrefix("com.apple."), bid.contains(".") else { continue }
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) == nil {
                result.append((root as NSString).appendingPathComponent(bid))
            }
        }
        return result
    }

    /// Caches À L'INTÉRIEUR des conteneurs sandbox (~/Library/Containers/<x>/Data/Library/Caches).
    /// Espace régénérable que le nettoyage classique de ~/Library/Caches ne touche pas.
    static func containerCaches() -> [String] {
        let fm = FileManager.default
        let root = NSHomeDirectory() + "/Library/Containers"
        guard let items = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var result = [String]()
        for bid in items.sorted() {
            let cache = "\(root)/\(bid)/Data/Library/Caches"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: cache, isDirectory: &isDir), isDir.boolValue {
                result.append(cache)
            }
        }
        return result
    }

    static func resolvedPaths(_ cat: CleanCategory) -> [String] {
        switch cat.dynamicSource {
        case "orphancontainers": return orphanedContainers()
        case "containercaches":  return containerCaches()
        default:                 return cat.paths
        }
    }

    static func scan() -> [String: [PathStat]] {
        var result = [String: [PathStat]]()
        let fm = FileManager.default
        for cat in cleanCategories {
            var stats = [PathStat]()
            for p in resolvedPaths(cat) {
                let full = expand(p)
                let exists = fm.fileExists(atPath: full)
                var bytes: Int64 = 0
                if exists {
                    let out = Shell.run("/usr/bin/du", ["-sk", full])
                    if let first = out.split(separator: "\t").first, let kb = Int64(first) {
                        bytes = kb * 1024
                    }
                }
                stats.append(PathStat(id: p, fullPath: full, bytes: bytes, exists: exists))
            }
            result[cat.id] = stats
        }
        return result
    }

    /// Supprime le CONTENU de chaque chemin (ou l'élément lui-même pour les catégories
    /// `removeItems`, via la Corbeille). Chaque cible passe par SafetyGuard.
    /// `onProgress` reçoit la fraction 0…1 et le chemin en cours ; chaque
    /// suppression effective est consignée dans le journal (ActionLog).
    static func clean(categoryIDs: Set<String>, stats: [String: [PathStat]],
                      onProgress: ((Double, String) -> Void)? = nil) -> Int64 {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var freed: Int64 = 0
        var journal = [DeletionRecord]()

        let targets: [(cat: CleanCategory, stat: PathStat)] = cleanCategories
            .filter { categoryIDs.contains($0.id) }
            .flatMap { cat in (stats[cat.id] ?? []).filter(\.exists).map { (cat, $0) } }
        let total = Double(max(targets.count, 1))

        for (idx, entry) in targets.enumerated() {
            let (cat, stat) = entry
            onProgress?(Double(idx) / total, stat.fullPath)
            guard stat.fullPath.hasPrefix(home) else { continue }
            if cat.removeItems {
                guard SafetyGuard.isDeletable(stat.fullPath) else { continue }
                let url = URL(fileURLWithPath: stat.fullPath)
                if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil
                    || (try? fm.removeItem(atPath: stat.fullPath)) != nil {
                    freed += stat.bytes
                    journal.append(DeletionRecord(date: Date(), path: stat.fullPath,
                                                  bytes: stat.bytes, source: cat.id))
                }
            } else {
                guard let items = try? fm.contentsOfDirectory(atPath: stat.fullPath) else { continue }
                for (j, item) in items.enumerated() {
                    let target = (stat.fullPath as NSString).appendingPathComponent(item)
                    guard SafetyGuard.isDeletable(target) else { continue }
                    if j % 20 == 0 {
                        onProgress?((Double(idx) + Double(j) / Double(max(items.count, 1))) / total,
                                    target)
                    }
                    do { try fm.removeItem(atPath: target) } catch { continue }
                    journal.append(DeletionRecord(date: Date(), path: target,
                                                  bytes: -1, source: cat.id))
                }
                freed += stat.bytes
            }
        }
        onProgress?(1, "")
        ActionLog.append(journal)
        return freed
    }
}

