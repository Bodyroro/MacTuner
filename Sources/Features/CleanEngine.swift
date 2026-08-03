//
//  CleanEngine.swift · MacTuner
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

    /// Caches à l'intérieur des « Group Containers » (~/Library/Group Containers/<x>/Library/Caches).
    static func groupContainerCaches() -> [String] {
        let fm = FileManager.default
        let root = NSHomeDirectory() + "/Library/Group Containers"
        guard let items = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var result = [String]()
        for grp in items.sorted() {
            let cache = "\(root)/\(grp)/Library/Caches"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: cache, isDirectory: &isDir), isDir.boolValue {
                result.append(cache)
            }
        }
        return result
    }

    /// true si le volume monté à ce chemin est le disque de démarrage (jamais ciblé).
    static func isRootVolume(_ volPath: String) -> Bool {
        let vals = try? URL(fileURLWithPath: volPath)
            .resourceValues(forKeys: [.volumeIsRootFileSystemKey])
        return vals?.volumeIsRootFileSystem ?? false
    }

    /// Corbeilles cachées (.Trashes/<uid>) sur les volumes externes montés, jamais
    /// le disque de démarrage. Suppression réservée au helper privilégié.
    static func externalTrashes() -> [String] {
        let fm = FileManager.default
        guard let vols = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return [] }
        var result = [String]()
        let uid = String(getuid())
        for vol in vols.sorted() {
            let volPath = "/Volumes/\(vol)"
            if isRootVolume(volPath) { continue }
            let trash = "\(volPath)/.Trashes/\(uid)"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: trash, isDirectory: &isDir), isDir.boolValue {
                result.append(trash)
            }
        }
        return result
    }

    /// Sous-dossiers de cache régénérables communs aux apps Electron/Chromium
    /// (VS Code, Slack, Discord, Notion, Obsidian, Teams, Codex…). Tous se
    /// reconstruisent au lancement ; ni réglages ni données ne s'y trouvent.
    static let electronCacheSubdirs = [
        "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "CachedData", "Application Cache", "Service Worker/CacheStorage", "blob_storage",
    ]
    /// Apps déjà couvertes par des catégories dédiées (editorcaches / chatapps) :
    /// exclues du scan Electron pour ne pas compter deux fois le même espace.
    static let electronSkipApps: Set<String> = ["Code", "Cursor", "Slack", "discord",
                                                 "Microsoft", "Spotify"]

    /// Caches Electron/Chromium à l'intérieur de ~/Library/Application Support/<app>.
    static func electronCaches() -> [String] {
        let fm = FileManager.default
        let root = NSHomeDirectory() + "/Library/Application Support"
        guard let apps = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var result = [String]()
        for app in apps.sorted() where !electronSkipApps.contains(app) {
            for sub in electronCacheSubdirs {
                let path = "\(root)/\(app)/\(sub)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    result.append(path)
                }
            }
        }
        return result
    }

    // MARK: Artefacts de projets de développement

    /// Dossiers de premier niveau exclus de la recherche de projets : ~/Library et les
    /// médiathèques (rien à y trouver), et les caches d'outils déjà couverts par la
    /// catégorie « Caches de développement » — les compter ici ferait double emploi.
    /// Tout le reste du dossier personnel est parcouru : les projets ne sont pas
    /// toujours rangés dans un dossier au nom convenu.
    static let projectSkipTop: Set<String> = [
        "Library", "Applications", "Public", "Movies", "Music", "Pictures", "Parallels",
        ".Trash", ".cache", ".npm", ".cargo", ".rustup", ".nvm", ".pyenv", ".rbenv",
        ".m2", ".ivy2", ".gradle", ".docker", ".local", ".config", ".bun", ".deno",
        ".conda", "miniconda3", "anaconda3", "miniforge3", "go",
    ]

    /// Profondeur maximale de recherche sous chaque racine. Quatre niveaux couvrent
    /// « <racine>/<client>/<projet>/<module>/node_modules » sans parcourir tout le disque.
    private static let projectMaxDepth = 4

    /// Dossiers d'artefacts de build trouvés dans les projets de l'utilisateur.
    /// La descente s'arrête dès qu'un artefact est trouvé (inutile de parcourir les
    /// 40 000 fichiers d'un node_modules) et ignore les bundles (.app, .xcodeproj…).
    static func devArtifacts() -> [String] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var result = [String]()

        func walk(_ dir: String, depth: Int) {
            guard depth <= projectMaxDepth,
                  let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for item in items.sorted() {
                let full = (dir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue,
                      (try? fm.destinationOfSymbolicLink(atPath: full)) == nil else { continue }
                if SafetyGuard.buildArtifactNames.contains(item) {
                    if SafetyGuard.isBuildArtifactDeletable(full) { result.append(full) }
                    continue   // on ne descend pas DANS l'artefact
                }
                // Les bundles (.app, .xcodeproj, .photoslibrary…) ne sont pas des dossiers
                // de projet : y descendre ne ferait que ralentir l'analyse.
                if item.contains(".") && (item as NSString).pathExtension.count >= 2 { continue }
                walk(full, depth: depth + 1)
            }
        }
        let tops = (try? fm.contentsOfDirectory(atPath: home))?.sorted() ?? []
        for top in tops where !projectSkipTop.contains(top) {
            let full = "\(home)/\(top)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue,
                  (try? fm.destinationOfSymbolicLink(atPath: full)) == nil else { continue }
            walk(full, depth: 1)
        }
        return result
    }

    // MARK: Installeurs téléchargés

    /// Installeurs (.dmg/.pkg/.xip/.iso) posés dans Téléchargements ou sur le Bureau
    /// depuis plus de `days` jours. Chacun repasse par SafetyGuard à la suppression.
    static func oldInstallerFiles(days: Int = 30) -> [String] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var result = [String]()
        for dir in ["\(home)/Downloads", "\(home)/Desktop"] {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items.sorted() {
                let full = (dir as NSString).appendingPathComponent(item)
                guard SafetyGuard.isInstallerDeletable(full) else { continue }
                let attr = try? fm.attributesOfItem(atPath: full)
                let mdate = (attr?[.modificationDate] as? Date) ?? Date()
                if mdate < cutoff { result.append(full) }
            }
        }
        return result
    }

    // MARK: Résidus d'apps disparues

    /// Premiers composants admis pour un identifiant en DNS inversé. Sans ce filtre,
    /// des noms internes de macOS (« group.… », « tvappservices.container ») passaient
    /// pour des identifiants d'app et étaient signalés comme orphelins.
    private static let reverseDNSTLDs: Set<String> = [
        "com", "org", "net", "io", "co", "dev", "app", "me", "ai", "xyz", "cc", "tv", "ly", "sh",
        "fr", "uk", "de", "es", "it", "nl", "se", "no", "pl", "ru", "jp", "cn", "br", "ca",
        "eu", "us", "in", "at", "ch", "be", "dk", "fi", "cz",
    ]

    /// Espaces de noms appartenant à Apple qui ne commencent pas par « com.apple ».
    private static let appleOwnedPrefixes = ["com.apple", "is.workflow"]

    /// Ramène un nom de fichier à un identifiant de bundle exploitable, ou nil si ce
    /// n'en est pas un. Retire le préfixe « group. » et un éventuel identifiant
    /// d'équipe (10 caractères), puis exige la forme DNS inversée.
    private static func normalizedBundleID(_ raw: String) -> String? {
        var id = raw
        if id.hasPrefix("group.") { id = String(id.dropFirst(6)) }
        var parts = id.split(separator: ".").map(String.init)
        if let first = parts.first, first.count == 10, first == first.uppercased(),
           first.allSatisfy({ $0.isLetter || $0.isNumber }) {
            parts.removeFirst()
        }
        guard parts.count >= 3, let tld = parts.first, reverseDNSTLDs.contains(tld),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 40 }) else { return nil }
        return parts.joined(separator: ".")
    }

    /// Préfixes « éditeur » (deux premiers composants) des apps encore installées :
    /// sert à ne JAMAIS proposer les fichiers d'un éditeur dont une app reste présente
    /// (ex. com.microsoft.autoupdate n'est pas une app, mais Word l'est).
    private static func installedVendorPrefixes() -> Set<String> {
        var prefixes = Set<String>(["com.apple", "local.rodolphe"])
        for bid in UninstallEngine.installedBundleIDs() {
            let parts = bid.split(separator: ".")
            if parts.count >= 2 { prefixes.insert(parts.prefix(2).joined(separator: ".")) }
        }
        return prefixes
    }

    /// Fichiers et dossiers nommés d'après une app qui n'est plus installée.
    static func orphanLeftovers() -> [String] {
        let fm = FileManager.default
        let h = NSHomeDirectory()
        let vendors = installedVendorPrefixes()
        // Les conteneurs sandbox ont déjà leur propre catégorie : pas de double compte.
        // Les « Group Containers » sont exclus : leur nom est préfixé par un identifiant
        // d'équipe (« group. », « ABCD1234.com.x »), impossible à rattacher de façon sûre
        // à une app installée. Idem pour les conteneurs sandbox, qui ont leur catégorie.
        let dirs = ["\(h)/Library/Preferences", "\(h)/Library/Application Support",
                    "\(h)/Library/Caches", "\(h)/Library/Saved Application State",
                    "\(h)/Library/HTTPStorages", "\(h)/Library/WebKit",
                    "\(h)/Library/Application Scripts"]
        var result = [String]()
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items.sorted() {
                // « com.editeur.app.plist » / « .savedState » → l'identifiant seul.
                var raw = item
                for suffix in [".plist", ".savedState", ".binarycookies"] where raw.hasSuffix(suffix) {
                    raw = String(raw.dropLast(suffix.count))
                }
                guard let bid = normalizedBundleID(raw) else { continue }
                guard !appleOwnedPrefixes.contains(where: { bid == $0 || bid.hasPrefix($0 + ".") })
                else { continue }
                let vendor = bid.split(separator: ".").prefix(2).joined(separator: ".")
                guard !vendors.contains(vendor) else { continue }
                // Deux interrogations : sur l'identifiant normalisé ET sur le nom brut,
                // pour ne rien proposer dont LaunchServices connaît encore une app.
                guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) == nil,
                      NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) == nil
                else { continue }
                let full = (dir as NSString).appendingPathComponent(item)
                if SafetyGuard.isDeletable(full) { result.append(full) }
            }
        }
        return result
    }

    /// Dossiers de langue (.lproj) supprimables des apps installées, hors langues
    /// conservées (FR/EN/Base) et hors MacTuner. Chaque dossier passe par SafetyGuard.
    static func appLanguageFiles() -> [String] {
        let fm = FileManager.default
        let bases = ["/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var result = [String]()
        for base in bases {
            guard let apps = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for app in apps.sorted() where app.hasSuffix(".app") {
                let appPath = "\(base)/\(app)"
                // Les apps Apple (com.apple.*) vivent sur le volume système scellé :
                // leurs .lproj ne peuvent pas être supprimées (échec silencieux) et
                // fausseraient l'espace « récupérable ». On les ignore.
                if UninstallEngine.bundleID(ofApp: appPath).hasPrefix("com.apple.") { continue }
                let res = "\(appPath)/Contents/Resources"
                guard let items = try? fm.contentsOfDirectory(atPath: res) else { continue }
                for it in items where it.hasSuffix(".lproj") {
                    let p = "\(res)/\(it)"
                    if SafetyGuard.isLanguageDeletable(p) { result.append(p) }
                }
            }
        }
        return result
    }

    /// Taille d'un dossier calculée en interne (sans processus `du`). Adaptée aux
    /// nombreux petits dossiers (ex. .lproj) où lancer un `du` par cible serait lent.
    static func fastDirBytes(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            let v = try? f.resourceValues(forKeys: keys)
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func resolvedPaths(_ cat: CleanCategory) -> [String] {
        switch cat.dynamicSource {
        case "orphancontainers":      return orphanedContainers()
        case "containercaches":       return containerCaches()
        case "groupcontainercaches":  return groupContainerCaches()
        case "electroncaches":        return electronCaches()
        case "devartifacts":          return devArtifacts()
        case "installers":            return oldInstallerFiles()
        case "orphanleftovers":       return orphanLeftovers()
        case "languages":             return appLanguageFiles()
        case "externaltrash":         return externalTrashes()
        default:                      return cat.paths
        }
    }

    /// Taille d'un chemin. Pour les cibles système (droits admin), on privilégie
    /// `sudo -n du` quand la règle sudoers de nettoyage est en place ; sinon on
    /// tente `du` en simple utilisateur (beaucoup de dossiers de logs sont lisibles).
    static func pathBytes(_ full: String, admin: Bool) -> Int64 {
        if admin && Permissions.hasCleanAuth() {
            let out = Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/du", "-sk", full])
            if let first = out.split(separator: "\t").first, let kb = Int64(first) { return kb * 1024 }
        }
        let out = Shell.run("/usr/bin/du", ["-sk", full])
        if let first = out.split(separator: "\t").first, let kb = Int64(first) { return kb * 1024 }
        return 0
    }

    static func scan() -> [String: [PathStat]] {
        var result = [String: [PathStat]]()
        let fm = FileManager.default
        // `languages` a son propre onglet (analyse et nettoyage dédiés) : on ne le
        // scanne pas ici pour ne pas relancer PlistBuddy sur chaque app inutilement.
        for cat in cleanCategories where cat.id != "languages" {
            var stats = [PathStat]()
            let isLang = cat.dynamicSource == "languages"
            for p in resolvedPaths(cat) {
                let full = expand(p)
                let exists = fm.fileExists(atPath: full)
                let bytes = exists ? (isLang ? fastDirBytes(full) : pathBytes(full, admin: cat.needsAdmin)) : 0
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

        let selectedCats = cleanCategories.filter { categoryIDs.contains($0.id) }
        let adminCats = selectedCats.filter(\.needsAdmin)
        let targets: [(cat: CleanCategory, stat: PathStat)] = selectedCats
            .filter { !$0.needsAdmin }
            .flatMap { cat in (stats[cat.id] ?? []).filter(\.exists).map { (cat, $0) } }
        let total = Double(max(targets.count + adminCats.count, 1))

        // Catégories système : déléguées au helper privilégié `--clean-system`,
        // qui applique la même liste blanche (SafetyGuard.isSystemDeletable).
        for (k, cat) in adminCats.enumerated() {
            let existing = (stats[cat.id] ?? []).filter(\.exists)
            onProgress?(Double(k) / total, existing.first?.fullPath ?? cat.id)
            guard !existing.isEmpty else { continue }
            SystemClean.invoke(categoryID: cat.id)
            for stat in existing {
                freed += stat.bytes
                journal.append(DeletionRecord(date: Date(), path: stat.fullPath,
                                              bytes: stat.bytes, source: cat.id))
            }
        }

        for (i, entry) in targets.enumerated() {
            let idx = i + adminCats.count
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

// MARK: - Helper privilégié : nettoyage niveau système

/// Nettoyage des zones système. Deux rôles :
///  • côté interface, `invoke` relance le binaire MacTuner en root (`--clean-system`)
///    via la règle sudoers dédiée, ou à défaut via l'invite admin de macOS ;
///  • côté helper root, `run` supprime le CONTENU des racines système autorisées.
/// La liste blanche est compilée (SafetyGuard.isSystemDeletable) : même exécuté en
/// root, `--clean-system` ne peut jamais toucher autre chose que ces racines.
enum SystemClean {

    /// Racines système à vider pour une catégorie (contenu supprimé, jamais la racine).
    static func targetRoots(_ cat: CleanCategory) -> [String] {
        if cat.dynamicSource == "externaltrash" {
            // Toutes les corbeilles cachées des volumes montés (tous uid).
            let fm = FileManager.default
            guard let vols = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return [] }
            var roots = [String]()
            for vol in vols.sorted() {
                let volPath = "/Volumes/\(vol)"
                if CleanEngine.isRootVolume(volPath) { continue }
                let base = "\(volPath)/.Trashes"
                if let uids = try? fm.contentsOfDirectory(atPath: base) {
                    for u in uids { roots.append("\(base)/\(u)") }
                }
            }
            return roots
        }
        return cat.paths
    }

    /// Exécuté EN ROOT par le helper : vide le contenu des racines de la catégorie.
    static func run(categoryID: String) {
        guard let cat = cleanCategories.first(where: { $0.id == categoryID }), cat.needsAdmin
        else { return }
        let fm = FileManager.default
        // Nettoyage des langues : on supprime les dossiers .lproj eux-mêmes (jamais
        // leur seul contenu), chacun validé par la liste blanche des langues.
        if cat.dynamicSource == "languages" {
            for p in CleanEngine.appLanguageFiles() where SafetyGuard.isLanguageDeletable(p) {
                try? fm.removeItem(atPath: p)
            }
            return
        }
        for root in targetRoots(cat) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items {
                let target = (root as NSString).appendingPathComponent(item)
                guard SafetyGuard.isSystemDeletable(target) else { continue }
                try? fm.removeItem(atPath: target)
            }
        }
    }

    private static var binaryPath: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    /// Côté interface : déclenche le nettoyage système en root pour une catégorie.
    static func invoke(categoryID: String) {
        let arg = "--clean-system \(categoryID)"
        if Permissions.hasCleanAuth() {
            let r = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(binaryPath)' \(arg)"])
            if r.ok { return }
            // La règle vise peut-être un autre exemplaire du binaire : on la répare
            // (un seul mot de passe) puis on réessaie sans invite.
            _ = Permissions.installCleanAuth()
            let retry = Shell.runResult("/bin/sh", ["-c", "/usr/bin/sudo -n '\(binaryPath)' \(arg)"])
            if retry.ok { return }
        }
        Shell.admin("'\(binaryPath)' \(arg)")
    }
}
