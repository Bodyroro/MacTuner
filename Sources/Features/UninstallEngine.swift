//
//  UninstallEngine.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Moteur : désinstallation

enum UninstallEngine {

    static func dirSize(_ path: String) -> Int64 {
        let out = Shell.run("/usr/bin/du", ["-sk", path])
        if let first = out.split(separator: "\t").first, let kb = Int64(first) { return kb * 1024 }
        return 0
    }

    static func bundleID(ofApp path: String) -> String {
        let plist = path + "/Contents/Info.plist"
        // Lecture directe du plist (texte comme binaire) : appelée pour chaque app
        // installée, lancer un processus PlistBuddy à chaque fois coûterait des secondes.
        if let dict = NSDictionary(contentsOfFile: plist),
           let bid = dict["CFBundleIdentifier"] as? String, !bid.isEmpty {
            return bid
        }
        let out = Shell.run("/usr/libexec/PlistBuddy",
                            ["-c", "print CFBundleIdentifier", plist])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.contains("Does Not Exist") || out.isEmpty ? "" : out
    }

    /// Identifiants de toutes les apps installées, sans calcul de taille : sert à
    /// reconnaître les résidus d'apps disparues sans payer un `du` par application.
    static func installedBundleIDs() -> Set<String> {
        let fm = FileManager.default
        var ids = Set<String>()
        for root in ["/Applications", "/Applications/Utilities",
                     NSHomeDirectory() + "/Applications", "/System/Applications"] {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") {
                let bid = bundleID(ofApp: (root as NSString).appendingPathComponent(item))
                if !bid.isEmpty { ids.insert(bid) }
            }
        }
        return ids
    }

    /// Liste les apps de /Applications, /Applications/Utilities et ~/Applications.
    static func scanApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        var apps = [InstalledApp]()
        var seen = Set<String>()
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") {
                let full = (root as NSString).appendingPathComponent(item)
                guard !seen.contains(full) else { continue }
                seen.insert(full)
                // Les apps protégées par SIP (Safari, apps intégrées, cryptexes) ne sont
                // pas désinstallables : non listées. En revanche les apps Apple simplement
                // TÉLÉCHARGÉES — Xcode, Xcode Beta, Apple Configurator, les apps Pro… —
                // ne portent pas ce drapeau et se désinstallent comme les autres : ce sont
                // souvent les plus volumineuses du Mac.
                guard !SafetyGuard.isSIPProtected(full) else { continue }
                let bid = bundleID(ofApp: full)
                let name = (item as NSString).deletingPathExtension
                apps.append(InstalledApp(id: full, name: name, path: full,
                                         bundleID: bid,
                                         bytes: quickFootprint(name: name, bundleID: bid, bundlePath: full)))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Outils en ligne de commande

    /// Répertoires de binaires installés par l'utilisateur (jamais /usr/bin, protégé par le système).
    private static func binDirs() -> [String] {
        let h = NSHomeDirectory()
        return ["/usr/local/bin", "/usr/local/sbin", "/opt/homebrew/bin", "/opt/homebrew/sbin",
                h + "/.local/bin", h + "/.cargo/bin", h + "/go/bin", h + "/.deno/bin",
                h + "/.bun/bin", h + "/.npm-global/bin", h + "/.yarn/bin"]
    }

    /// Début d'un script shell (si c'en est un), pour détecter alias et chemins de données.
    private static func scriptHead(_ path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path),
              let data = try? fh.read(upToCount: 4096),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("#!") else { return nil }
        return text
    }

    static func scanCLITools() -> [InstalledApp] {
        let fm = FileManager.default
        struct RawTool { let name: String; let path: String }
        var raws = [RawTool]()
        var seenPaths = Set<String>()
        var seenNames = Set<String>()
        for dir in binDirs() {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items.sorted() {
                let full = (dir as NSString).appendingPathComponent(item)
                guard fm.isExecutableFile(atPath: full),
                      !seenPaths.contains(full), !seenNames.contains(item) else { continue }
                seenPaths.insert(full)
                seenNames.insert(item)
                raws.append(RawTool(name: item, path: full))
            }
        }
        // Détection d'alias : symlink vers un autre outil du lot, ou script
        // wrapper qui `exec` un autre outil (ex. « mo » → exec …/mole).
        let names = Set(raws.map(\.name))
        var aliasOf = [String: String]()   // chemin de l'alias → nom de l'outil principal
        for raw in raws {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: raw.path) {
                let target = (dest as NSString).lastPathComponent
                if target != raw.name && names.contains(target) {
                    aliasOf[raw.path] = target
                    continue
                }
            }
            if let head = scriptHead(raw.path), head.contains("exec") {
                for other in names where other != raw.name && other.count >= 3 {
                    if head.contains("/\(other)\"") || head.contains("/\(other) ") {
                        aliasOf[raw.path] = other
                        break
                    }
                }
            }
        }
        var aliasesFor = [String: [RawTool]]()
        for raw in raws {
            if let primary = aliasOf[raw.path] { aliasesFor[primary, default: []].append(raw) }
        }
        var tools = [InstalledApp]()
        for raw in raws where aliasOf[raw.path] == nil {
            let aliases = aliasesFor[raw.name] ?? []
            var bytes = dirSize(raw.path) + aliases.reduce(0) { $0 + dirSize($1.path) }
            for p in cliDataPaths(name: raw.name, binary: raw.path) { bytes += dirSize(p) }
            tools.append(InstalledApp(id: raw.path, name: raw.name, path: raw.path,
                                      bundleID: "", bytes: bytes, kind: .cli,
                                      extraExecutables: aliases.map(\.path),
                                      aliases: aliases.map(\.name)))
        }
        return tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Dossiers de données d'un outil CLI, via deux résolutions :
    /// 1. symlink remonté jusqu'au dossier portant le nom de l'outil
    ///    (ex. ~/.local/bin/claude → …/share/claude/versions/x → ~/.local/share/claude) ;
    /// 2. chemins référencés dans le script wrapper (ex. mole → SCRIPT_DIR=~/.config/mole).
    private static func cliDataPaths(name: String, binary: String) -> [String] {
        let fm = FileManager.default
        var result = [String]()
        if let link = try? fm.destinationOfSymbolicLink(atPath: binary) {
            let real = link.hasPrefix("/") ? link
                : ((binary as NSString).deletingLastPathComponent as NSString).appendingPathComponent(link)
            var comps = (real as NSString).pathComponents
            if let idx = comps.lastIndex(of: name), idx >= 1 {
                comps = Array(comps[0...idx])
                let root = NSString.path(withComponents: comps)
                if root != binary { result.append(root) }
            }
        }
        if let head = scriptHead(binary) {
            let h = NSHomeDirectory()
            for cand in ["\(h)/.config/\(name)", "\(h)/.\(name)", "\(h)/.local/share/\(name)"] {
                if head.contains(cand) || head.contains("$HOME/.config/\(name)")
                    || head.contains("$HOME/.\(name)") {
                    result.append(cand)
                }
            }
        }
        return result.filter { fm.fileExists(atPath: $0) }
    }

    /// Éléments cachés (~/.xxx) à la racine du dossier personnel, les outils installés
    /// « en dotfile ». Les fichiers vitaux (shell, clés SSH…) ne sont jamais listés.
    static let protectedDotItems: Set<String> = [
        ".DS_Store", ".ssh", ".gnupg", ".Trash", ".local", ".config", ".cache",
        ".zshrc", ".zprofile", ".zshenv", ".zsh_history", ".zsh_sessions",
        ".bashrc", ".bash_profile", ".bash_history", ".profile",
        ".gitconfig", ".gitignore_global", ".CFUserTextEncoding", ".TemporaryItems",
    ]

    static func scanDotItems() -> [InstalledApp] {
        let fm = FileManager.default
        let h = NSHomeDirectory()
        guard let items = try? fm.contentsOfDirectory(atPath: h) else { return [] }
        var result = [InstalledApp]()
        var seenNames = Set<String>()
        for item in items.sorted() where item.hasPrefix(".") && !protectedDotItems.contains(item) {
            let full = (h as NSString).appendingPathComponent(item)
            // « .claude.json » → « claude » : regroupe les fichiers d'un même outil.
            let cleaned = String(item.dropFirst()).split(separator: ".").first.map(String.init) ?? ""
            guard cleaned.count >= 2, !seenNames.contains(cleaned) else { continue }
            seenNames.insert(cleaned)
            result.append(InstalledApp(id: full, name: cleaned, path: full,
                                       bundleID: "", bytes: dirSize(full), kind: .dotfile))
        }
        return result
    }

    static func findCLIResidues(for tool: InstalledApp) -> [Residue] {
        let fm = FileManager.default
        let h = NSHomeDirectory()
        let name = tool.name
        var residues = [Residue]()
        var seen = Set<String>()

        func add(_ path: String, _ kind: Residue.Kind, high: Bool) {
            guard fm.fileExists(atPath: path), !seen.contains(path) else { return }
            seen.insert(path)
            residues.append(Residue(id: path, kind: kind, path: path, bytes: dirSize(path),
                                    system: !path.hasPrefix(h), highConfidence: high))
        }

        // 1. Le binaire (ou l'élément caché) lui-même, puis ses alias (ex. « mo » avec mole).
        add(tool.path, tool.kind == .dotfile ? .config : .executable, high: true)
        for extra in tool.extraExecutables { add(extra, .executable, high: true) }
        // 2. Dossiers de données résolus via symlink ou script wrapper (ex. ~/.local/share/claude).
        if tool.kind == .cli {
            for p in cliDataPaths(name: name, binary: tool.path) { add(p, .data, high: true) }
        }
        // 3. Emplacements standards de config et de données, par nom exact.
        let configs = [".\(name)", ".\(name).json", ".\(name)rc", ".\(name).yaml",
                       ".\(name).yml", ".\(name).toml", ".config/\(name)"]
        for c in configs { add((h as NSString).appendingPathComponent(c), .config, high: true) }
        let datas = [".local/share/\(name)", ".local/state/\(name)", ".cache/\(name)",
                     "Library/Application Support/\(name)", "Library/Caches/\(name)",
                     "Library/Logs/\(name)", "Library/Preferences/\(name).plist"]
        for d in datas { add((h as NSString).appendingPathComponent(d), .data, high: true) }
        // 4. Agents de lancement éventuels référençant l'outil.
        if let agents = try? fm.contentsOfDirectory(atPath: h + "/Library/LaunchAgents") {
            for a in agents where normalize((a as NSString).deletingPathExtension).contains(normalize(name))
                && normalize(name).count >= 4 {
                add(h + "/Library/LaunchAgents/" + a, .launchAgent, high: false)
            }
        }
        // Même invariant que pour les apps : rien d'affiché qui ne soit supprimable.
        return residues.filter { SafetyGuard.isDeletable($0.path) }.sorted {
            if $0.kind == .executable { return true }
            if $1.kind == .executable { return false }
            return $0.bytes > $1.bytes
        }
    }

    /// Empreinte disque rapide d'une app : bundle + principaux dossiers de données,
    /// pour que la taille listée reflète le VRAI poids (ex. les 1 Go de PrismLauncher),
    /// pas seulement le .app. Vérifications de chemins exacts → rapide même sur 200 apps.
    static func quickFootprint(name: String, bundleID: String, bundlePath: String) -> Int64 {
        let fm = FileManager.default
        let h = NSHomeDirectory()
        var total = dirSize(bundlePath)
        var names = Set([name, name.replacingOccurrences(of: " ", with: "")])
        if let last = bundleID.split(separator: ".").last { names.insert(String(last)) }
        var counted = Set<String>()
        func addIfExists(_ p: String) {
            guard !counted.contains(p), fm.fileExists(atPath: p) else { return }
            counted.insert(p); total += dirSize(p)
        }
        for base in ["Library/Application Support", "Library/Caches", "Library/Logs",
                     "Library/HTTPStorages", "Library/WebKit"] {
            for n in names where n.count >= 2 { addIfExists("\(h)/\(base)/\(n)") }
        }
        if !bundleID.isEmpty {
            addIfExists("\(h)/Library/Containers/\(bundleID)")
            addIfExists("\(h)/Library/Caches/\(bundleID)")
            addIfExists("\(h)/Library/Application Support/\(bundleID)")
            addIfExists("\(h)/Library/Preferences/\(bundleID).plist")
            addIfExists("\(h)/Library/Saved Application State/\(bundleID).savedState")
        }
        return total
    }

    private struct SearchDir {
        let path: String
        let kind: Residue.Kind
        let system: Bool
        let allowNameMatch: Bool
        /// true = dossier partagé : on inspecte les fichiers À L'INTÉRIEUR (jamais le dossier lui-même).
        let shared: Bool
        /// true = seule une correspondance EXACTE compte. Réservé aux racines très
        /// fréquentées (~/, ~/Library, /Library) où une sous-chaîne ferait n'importe quoi.
        var exactOnly: Bool = false
        /// true = jamais coché d'avance. Pour les dossiers susceptibles de contenir le
        /// travail de l'utilisateur (ex. ~/Parallels et ses machines virtuelles).
        var neverPreselect: Bool = false
    }

    private static func searchDirs() -> [SearchDir] {
        let h = NSHomeDirectory()
        return [
            SearchDir(path: h + "/Library/Preferences", kind: .preferences, system: false, allowNameMatch: false, shared: false),
            SearchDir(path: h + "/Library/Preferences/ByHost", kind: .preferences, system: false, allowNameMatch: false, shared: false),
            SearchDir(path: h + "/Library/Application Support", kind: .appSupport, system: false, allowNameMatch: true, shared: false),
            SearchDir(path: h + "/Library/Application Support/CrashReporter", kind: .logs, system: false, allowNameMatch: true, shared: true),
            SearchDir(path: h + "/Library/Caches", kind: .caches, system: false, allowNameMatch: true, shared: false),
            SearchDir(path: h + "/Library/Containers", kind: .container, system: false, allowNameMatch: true, shared: false),
            SearchDir(path: h + "/Library/Group Containers", kind: .groupContainer, system: false, allowNameMatch: false, shared: false),
            SearchDir(path: h + "/Library/Saved Application State", kind: .savedState, system: false, allowNameMatch: false, shared: false),
            SearchDir(path: h + "/Library/Logs", kind: .logs, system: false, allowNameMatch: true, shared: false),
            SearchDir(path: h + "/Library/Logs/DiagnosticReports", kind: .logs, system: false, allowNameMatch: true, shared: true),
            SearchDir(path: h + "/Library/HTTPStorages", kind: .httpStorage, system: false, allowNameMatch: false, shared: false),
            SearchDir(path: h + "/Library/Cookies", kind: .httpStorage, system: false, allowNameMatch: false, shared: true),
            SearchDir(path: h + "/Library/WebKit", kind: .webkit, system: false, allowNameMatch: false, shared: false),
            SearchDir(path: h + "/Library/Application Scripts", kind: .scripts, system: false, allowNameMatch: false, shared: false),
            SearchDir(path: h + "/Library/LaunchAgents", kind: .launchAgent, system: false, allowNameMatch: false, shared: false),
            // Racine du dossier personnel : dossiers cachés (.minecraft…) ET dossiers
            // visibles portant le nom de l'éditeur (~/Parallels et ses machines
            // virtuelles, souvent des dizaines de Go). Jamais cochés d'avance.
            SearchDir(path: h, kind: .appSupport, system: false, allowNameMatch: true, shared: false,
                      exactOnly: true, neverPreselect: true),
            SearchDir(path: h + "/.config", kind: .appSupport, system: false, allowNameMatch: true, shared: false),
            // Racine de ~/Library : beaucoup d'éditeurs y posent leur propre dossier
            // (~/Library/Parallels), hors des emplacements standards balayés ci-dessus.
            SearchDir(path: h + "/Library", kind: .appSupport, system: false, allowNameMatch: true,
                      shared: false, exactOnly: true),
            // Racine de /Library, même raison côté système (/Library/Parallels).
            SearchDir(path: "/Library", kind: .appSupport, system: true, allowNameMatch: true,
                      shared: false, exactOnly: true),
            SearchDir(path: "/Library/Logs", kind: .logs, system: true, allowNameMatch: true, shared: false),
            SearchDir(path: "/Library/Application Support", kind: .appSupport, system: true, allowNameMatch: true, shared: false),
            SearchDir(path: "/Library/Caches", kind: .caches, system: true, allowNameMatch: false, shared: false),
            SearchDir(path: "/Library/Preferences", kind: .preferences, system: true, allowNameMatch: false, shared: false),
            SearchDir(path: "/Library/LaunchAgents", kind: .launchAgent, system: true, allowNameMatch: false, shared: false),
            SearchDir(path: "/Library/LaunchDaemons", kind: .launchDaemon, system: true, allowNameMatch: false, shared: false),
            SearchDir(path: "/Library/PrivilegedHelperTools", kind: .helper, system: true, allowNameMatch: false, shared: false),
            SearchDir(path: "/Library/Logs/DiagnosticReports", kind: .logs, system: true, allowNameMatch: true, shared: true),
        ]
    }

    /// Jeux de « tokens » servant à reconnaître les fichiers d'une app.
    struct AppTokens {
        let bundleID: String
        let bundleTokens: [String]   // tokens distinctifs issus du bundle id (normalisés)
        let nameToken: String        // nom d'app normalisé (sans espaces/ponctuation)
    }

    private static let genericParts: Set<String> = [
        "com", "org", "net", "io", "co", "app", "apps", "inc", "ltd", "llc", "gmbh",
        "software", "dev", "github", "sourceforge", "www", "me", "xyz", "macos", "osx",
        "apple", "team", "group", "the", "get", "my", "labs", "studio", "studios", "sarl",
        // Mots de rôle : présents dans des centaines d'identifiants, ils ne désignent
        // jamais un éditeur. Sans eux, « com.parallels.desktop.console » produisait le
        // token « desktop », qui attrapait com.apple.desktopservices, Desktop-Settings…
        "desktop", "console", "client", "server", "helper", "agent", "daemon", "service",
        "services", "updater", "update", "installer", "launcher", "manager", "player",
        "viewer", "editor", "tools", "utility", "support", "main", "ui", "local",
    ]

    /// Tokens à écarter en plus : le nom de session et le nom de la machine. Un
    /// identifiant du type « local.rodolphe.montruc » produisait le token « rodolphe »,
    /// qui reconnaissait tous les rapports de plantage nommés d'après le Mac.
    private static var personalTokens: Set<String> {
        var s = Set([normalize(NSUserName()), normalize(NSFullUserName())])
        s.insert(normalize(ProcessInfo.processInfo.hostName))
        return s.filter { !$0.isEmpty }
    }

    static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9")
        })
    }

    static func tokens(for app: InstalledApp) -> AppTokens {
        var toks = [String]()
        let personal = personalTokens
        for part in app.bundleID.split(separator: ".") {
            let n = normalize(String(part))
            if n.count >= 4 && !genericParts.contains(n) && !personal.contains(n) { toks.append(n) }
        }
        let name = normalize(app.name)
        // Déduplication en conservant l'ordre.
        var seen = Set<String>()
        let bundleTokens = toks.filter { seen.insert($0).inserted }
        return AppTokens(bundleID: app.bundleID, bundleTokens: bundleTokens,
                         nameToken: name.count >= 4 ? name : "")
    }

    /// (correspond, confiance élevée). Confiance élevée = bundle id exact ou token distinctif exact.
    private static func match(child: String, tokens t: AppTokens, allowNameMatch: Bool,
                              exactOnly: Bool = false) -> (Bool, Bool) {
        let base = (child as NSString).deletingPathExtension
        let lowerChild = child.lowercased()
        let normBase = normalize(base)

        // 1. Bundle id : exact, préfixe, suffixe (group containers), ou contenu.
        if !t.bundleID.isEmpty {
            let bid = t.bundleID.lowercased()
            if lowerChild == bid || base.lowercased() == bid
                || lowerChild.hasPrefix(bid + ".") || lowerChild.hasSuffix("." + bid)
                || lowerChild.contains(bid) {
                return (true, true)
            }
        }
        // 2. Token distinctif == nom de base normalisé → confiance élevée
        //    (ex. dossier « PrismLauncher » ↔ token « prismlauncher »).
        for tok in t.bundleTokens where normBase == tok { return (true, true) }
        if allowNameMatch && !t.nameToken.isEmpty && normBase == t.nameToken { return (true, true) }

        // 2 bis. Un COMPOSANT du nom (découpé sur les points) égale un token distinctif
        //    → confiance élevée. Sans ça, « com.parallels.Parallels Desktop.plist » —
        //    dont l'identifiant diffère de celui de l'app — restait décoché.
        let parts = base.split(separator: ".").map { normalize(String($0)) }
        for tok in t.bundleTokens where parts.contains(tok) { return (true, true) }
        if allowNameMatch && !t.nameToken.isEmpty && parts.contains(t.nameToken) { return (true, true) }

        // 3. Token distinctif contenu dans le nom (sous-chaîne) → confiance faible
        //    (ex. « prismlauncher_UUID.plist » dans CrashReporter).
        if exactOnly { return (false, false) }
        let candidates = t.bundleTokens + (allowNameMatch ? [t.nameToken] : [])
        for tok in candidates where tok.count >= 5 && normBase.contains(tok) {
            return (true, false)
        }
        return (false, false)
    }

    /// Résidus propres à Xcode (et Xcode Beta), introuvables par correspondance de nom :
    /// tout vit sous ~/Library/Developer. Les dossiers purement régénérables sont
    /// proposés cochés ; ceux qui contiennent du travail personnel (archives, réglages,
    /// simulateurs et leurs données) sont proposés DÉCOCHÉS, à l'appréciation de l'utilisateur.
    private static func xcodeResidues(for app: InstalledApp) -> [Residue] {
        guard app.bundleID.hasPrefix("com.apple.dt.Xcode") else { return [] }
        let fm = FileManager.default
        // Xcode et Xcode Beta partagent le même identifiant et les mêmes dossiers de
        // données : tant qu'un autre exemplaire est installé, on ne propose que le bundle.
        let others = ["/Applications", NSHomeDirectory() + "/Applications"].flatMap { root -> [String] in
            (try? fm.contentsOfDirectory(atPath: root))?
                .filter { $0.hasSuffix(".app") }
                .map { (root as NSString).appendingPathComponent($0) } ?? []
        }.filter { $0 != app.path && bundleID(ofApp: $0).hasPrefix("com.apple.dt.Xcode") }
        guard others.isEmpty else { return [] }

        let h = NSHomeDirectory()
        // (chemin, type, régénérable → proposé coché)
        let targets: [(String, Residue.Kind, Bool)] = [
            ("\(h)/Library/Developer/Xcode/DerivedData", .caches, true),
            ("\(h)/Library/Developer/Xcode/iOS DeviceSupport", .caches, true),
            ("\(h)/Library/Developer/Xcode/watchOS DeviceSupport", .caches, true),
            ("\(h)/Library/Developer/Xcode/tvOS DeviceSupport", .caches, true),
            ("\(h)/Library/Developer/Xcode/DocumentationCache", .caches, true),
            ("\(h)/Library/Developer/Xcode/Products", .caches, true),
            ("\(h)/Library/Developer/CoreSimulator/Caches", .caches, true),
            ("\(h)/Library/Developer/XCTestDevices", .caches, true),
            ("\(h)/Library/Developer/DVTDownloads", .caches, true),
            ("\(h)/Library/Caches/com.apple.dt.Xcode", .caches, true),
            ("\(h)/Library/Caches/org.swift.swiftpm", .caches, true),
            ("\(h)/Library/org.swift.swiftpm", .data, true),
            // Contiennent du travail personnel : jamais préselectionnés.
            ("\(h)/Library/Developer/Xcode/Archives", .data, false),
            ("\(h)/Library/Developer/Xcode/UserData", .data, false),
            ("\(h)/Library/Developer/CoreSimulator/Devices", .data, false),
            ("\(h)/Library/Developer/CoreDevice", .data, false),
            ("\(h)/Library/MobileDevice", .data, false),
        ]
        return targets.compactMap { path, kind, high in
            guard fm.fileExists(atPath: path) else { return nil }
            return Residue(id: path, kind: kind, path: path, bytes: dirSize(path),
                           system: false, highConfidence: high)
        }
    }

    /// Dossiers de la racine du dossier personnel qui appartiennent à macOS : jamais
    /// des résidus d'app, quel que soit le nom qui semble correspondre.
    private static let homeRootNeverResidue: Set<String> = [
        "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies",
        "Music", "Pictures", "Public", "Sites", "Bureau", "Documents publics",
        // Racines partagées par des dizaines d'outils : jamais celles d'une seule app.
        ".local", ".config", ".cache", ".ssh", ".gnupg", ".Trash",
    ]

    /// Exécutables en ligne de commande installés par l'app : un lien symbolique de
    /// /usr/local/bin (ou équivalent) qui pointe À L'INTÉRIEUR du bundle. C'est la
    /// seule détection fiable — rien dans « prlctl » ne rappelle « Parallels ».
    private static func linkedBinaries(of app: InstalledApp) -> [Residue] {
        let fm = FileManager.default
        let bundle = (app.path as NSString).standardizingPath
        var result = [Residue]()
        for dir in binDirs() {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items.sorted() {
                let full = (dir as NSString).appendingPathComponent(item)
                guard let dest = try? fm.destinationOfSymbolicLink(atPath: full) else { continue }
                let target = dest.hasPrefix("/") ? dest
                    : ((full as NSString).deletingLastPathComponent as NSString)
                        .appendingPathComponent(dest)
                let std = (target as NSString).standardizingPath
                guard std == bundle || std.hasPrefix(bundle + "/") else { continue }
                result.append(Residue(id: full, kind: .executable, path: full,
                                      bytes: dirSize(full),
                                      system: !full.hasPrefix(NSHomeDirectory()),
                                      highConfidence: true))
            }
        }
        return result
    }

    static func findResidues(for app: InstalledApp) -> [Residue] {
        let fm = FileManager.default
        let t = tokens(for: app)
        let appIsApple = app.bundleID.hasPrefix("com.apple.")
        var residues = [Residue]()

        // 1. Le bundle lui-même.
        residues.append(Residue(id: app.path, kind: .appBundle, path: app.path,
                                bytes: app.bytes,
                                system: !app.path.hasPrefix(NSHomeDirectory()),
                                highConfidence: true))

        // 1 bis. Xcode : l'essentiel de son poids (souvent des dizaines de Go) est dans
        // ~/Library/Developer, que le nom du bundle ne permet pas de retrouver.
        residues += xcodeResidues(for: app)

        // 1 ter. Commandes en ligne installées par l'app (liens vers le bundle) :
        // les huit « prl* » de Parallels, par exemple, qu'aucun nom ne trahit.
        residues += linkedBinaries(of: app)

        // 2. Résidus dans les dossiers connus (+ scan interne des dossiers partagés).
        var seen = Set<String>(residues.map(\.id))
        for dir in searchDirs() {
            guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            let isHomeRoot = dir.path == NSHomeDirectory()
            for item in items {
                // À la racine du dossier perso, les dossiers macOS standards ne sont
                // jamais des résidus — et le token « desktop » d'un éditeur ne doit
                // surtout pas désigner ~/Desktop.
                if isHomeRoot && homeRootNeverResidue.contains(item) { continue }
                let candidateName = (isHomeRoot && item.hasPrefix("."))
                    ? String(item.dropFirst()) : item
                let (ok, high) = match(child: candidateName, tokens: t,
                                       allowNameMatch: dir.allowNameMatch,
                                       exactOnly: dir.exactOnly)
                guard ok else { continue }
                // Un résidu Apple n'appartient jamais à une app tierce : le nom a beau
                // correspondre, c'est un faux positif (com.apple.desktopservices…).
                if !appIsApple && candidateName.lowercased().hasPrefix("com.apple.") { continue }
                let full = (dir.path as NSString).appendingPathComponent(item)
                guard !seen.contains(full) else { continue }
                seen.insert(full)
                residues.append(Residue(id: full, kind: dir.kind, path: full,
                                        bytes: dirSize(full), system: dir.system,
                                        highConfidence: high && !dir.neverPreselect))
            }
        }
        // Invariant : ne jamais afficher un résidu que le garde-fou refusera à la
        // suppression. Sinon l'utilisateur coche une ligne (parfois plusieurs centaines
        // de Mo) qui serait écartée en silence au moment du nettoyage.
        return residues.filter { SafetyGuard.isDeletable($0.path) }.sorted {
            if $0.kind == .appBundle { return true }
            if $1.kind == .appBundle { return false }
            return $0.bytes > $1.bytes
        }
    }

    /// Décharge les agents/démons launchd correspondant à un fichier plist résidu.
    private static func unloadLaunch(_ path: String) {
        let label = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        Shell.run("/bin/launchctl", ["bootout", "\(LaunchCtl.domain)/\(label)"])
        Shell.run("/bin/launchctl", ["disable", "\(LaunchCtl.domain)/\(label)"])
    }

    private static func removeLoginItem(_ appName: String) {
        Shell.run("/usr/bin/osascript",
                  ["-e", "tell application \"System Events\" to delete login item \"\(appName)\""])
    }

    /// Supprime les résidus sélectionnés. Items personnels → Corbeille (récupérables) ;
    /// items système → suppression admin en un seul appel (un mot de passe).
    static func uninstall(app: InstalledApp, residues: [Residue]) -> (freed: Int64, systemPaths: [String]) {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var freed: Int64 = 0
        var systemPaths = [String]()

        // Garde-fou final : tout chemin non explicitement autorisé est écarté,
        // quelle que soit la façon dont il est arrivé dans la sélection.
        let residues = residues.filter { SafetyGuard.isDeletable($0.path) }

        ActionLog.append(residues.map {
            DeletionRecord(date: Date(), path: $0.path, bytes: $0.bytes, source: "app:\(app.name)")
        })

        removeLoginItem(app.name)

        for r in residues {
            if r.kind == .launchAgent || r.kind == .launchDaemon { unloadLaunch(r.path) }

            if r.system || !r.path.hasPrefix(home) {
                systemPaths.append(r.path)          // regroupés pour une seule invite admin
                freed += r.bytes
            } else {
                let url = URL(fileURLWithPath: r.path)
                if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                    freed += r.bytes
                } else {
                    // Repli : suppression admin si le déplacement en Corbeille échoue.
                    systemPaths.append(r.path)
                    freed += r.bytes
                }
            }
        }

        if !systemPaths.isEmpty {
            // rm système : invite de mot de passe directe (hors périmètre de la règle sudoers).
            let quoted = systemPaths.map { "'\($0)'" }.joined(separator: " ")
            Shell.admin("/bin/rm -rf \(quoted)")
        }
        return (freed, systemPaths)
    }
}
