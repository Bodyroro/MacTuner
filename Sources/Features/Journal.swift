//
//  Journal.swift — MacTuner
//
import Foundation

// MARK: - Journal des suppressions

/// Une suppression réellement effectuée par MacTuner (nettoyage ou désinstallation).
struct DeletionRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let path: String
    /// Taille en octets ; -1 si inconnue (élément d'un dossier vidé en bloc).
    let bytes: Int64
    /// Origine : id d'une catégorie de nettoyage, ou "app:<nom>" pour une désinstallation.
    let source: String
}

/// Persistance du journal : un fichier JSON dans Application Support, borné
/// aux 5 000 entrées les plus récentes (les plus récentes en tête).
enum ActionLog {
    static let maxEntries = 5000
    static var fileURL: URL { URL(fileURLWithPath: ReapplyAgent.supportDir + "/journal.json") }

    static func append(_ records: [DeletionRecord]) {
        guard !records.isEmpty else { return }
        var all = load()
        all.insert(contentsOf: records, at: 0)
        if all.count > maxEntries { all.removeLast(all.count - maxEntries) }
        save(all)
    }

    static func load() -> [DeletionRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let recs = try? JSONDecoder().decode([DeletionRecord].self, from: data) else { return [] }
        return recs
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func save(_ recs: [DeletionRecord]) {
        try? FileManager.default.createDirectory(atPath: ReapplyAgent.supportDir,
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(recs) {
            try? data.write(to: fileURL)
        }
    }
}
