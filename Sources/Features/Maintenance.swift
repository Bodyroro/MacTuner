//
//  Maintenance.swift · MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Maintenance système

struct MaintenanceAction: Identifiable {
    let id: String
    let nameKey: String
    let icon: String
    let whatKey: String
    let needsAdmin: Bool
    let run: () -> Void
    var name: String { T(nameKey) }
    var what: String { T(whatKey) }
}

enum Maintenance {
    static let actions: [MaintenanceAction] = [
        MaintenanceAction(id: "dns", nameKey: "maint.dns.name", icon: "network",
            whatKey: "maint.dns.what", needsAdmin: true) {
            Shell.admin("dscacheutil -flushcache; killall -HUP mDNSResponder")
        },
        MaintenanceAction(id: "purge", nameKey: "maint.purge.name", icon: "memorychip",
            whatKey: "maint.purge.what", needsAdmin: true) {
            Shell.admin("purge")
        },
        MaintenanceAction(id: "spotlight", nameKey: "maint.spot.name", icon: "magnifyingglass",
            whatKey: "maint.spot.what", needsAdmin: true) {
            Shell.admin("mdutil -E /")
        },
        MaintenanceAction(id: "tmsnap", nameKey: "maint.tm.name", icon: "clock.arrow.circlepath",
            whatKey: "maint.tm.what", needsAdmin: true) {
            Shell.admin("for d in $(tmutil listlocalsnapshotdates / | grep -E '^[0-9]'); do tmutil deletelocalsnapshots $d; done")
        },
        MaintenanceAction(id: "iconcache", nameKey: "maint.icon.name", icon: "app.dashed",
            whatKey: "maint.icon.what", needsAdmin: true) {
            Shell.admin("rm -rf /Library/Caches/com.apple.iconservices.store; "
                + "find /private/var/folders -name com.apple.dock.iconcache -delete 2>/dev/null; "
                + "find /private/var/folders -name com.apple.iconservices -type d -exec rm -rf {} + 2>/dev/null; true")
            Shell.sh("rm -rf ~/Library/Caches/com.apple.iconservices* 2>/dev/null; killall Dock; killall Finder")
        },
        MaintenanceAction(id: "launchservices", nameKey: "maint.ls.name", icon: "app.badge",
            whatKey: "maint.ls.what", needsAdmin: false) {
            Shell.sh("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user")
        },
        MaintenanceAction(id: "dock", nameKey: "maint.dock.name", icon: "menubar.dock.rectangle",
            whatKey: "maint.dock.what", needsAdmin: false) {
            Shell.sh("killall Dock; killall Finder; killall SystemUIServer")
        },
        MaintenanceAction(id: "sqlite", nameKey: "maint.sqlite.name", icon: "cylinder.split.1x2.fill",
            whatKey: "maint.sqlite.what", needsAdmin: false) {
            // Compacte (VACUUM) les bases SQLite de Mail, Safari et Messages, mais
            // seulement quand l'app correspondante est fermée (sinon la base est
            // verrouillée). Aucune donnée supprimée : uniquement l'espace libéré.
            Shell.sh("""
            command -v sqlite3 >/dev/null 2>&1 || exit 0
            pgrep -x Safari >/dev/null 2>&1 || for db in "$HOME/Library/Safari/History.db" "$HOME/Library/Safari/TopSites.db"; do [ -f "$db" ] && sqlite3 "$db" 'VACUUM;' 2>/dev/null; done
            pgrep -x Messages >/dev/null 2>&1 || { [ -f "$HOME/Library/Messages/chat.db" ] && sqlite3 "$HOME/Library/Messages/chat.db" 'VACUUM;' 2>/dev/null; }
            pgrep -x Mail >/dev/null 2>&1 || for db in "$HOME"/Library/Mail/V*/MailData/Envelope\\ Index; do [ -f "$db" ] && sqlite3 "$db" 'VACUUM;' 2>/dev/null; done
            true
            """)
        },
        MaintenanceAction(id: "quarantine", nameKey: "maint.quar.name", icon: "shield.lefthalf.filled",
            whatKey: "maint.quar.what", needsAdmin: false) {
            // Efface l'historique de téléchargements suivi par Gatekeeper (la liste
            // « téléchargé depuis Internet »). N'affecte pas les drapeaux de
            // quarantaine des fichiers eux-mêmes ; la base est recréée par macOS.
            Shell.sh("""
            command -v sqlite3 >/dev/null 2>&1 || exit 0
            db="$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
            [ -f "$db" ] && sqlite3 "$db" 'DELETE FROM LSQuarantineEvent; VACUUM;' 2>/dev/null
            true
            """)
        },
        MaintenanceAction(id: "simulators", nameKey: "maint.sim.name", icon: "iphone.gen3.slash",
            whatKey: "maint.sim.what", needsAdmin: false) {
            // Voie officielle Apple : simctl supprime les simulateurs devenus
            // indisponibles (runtime iOS retiré, Xcode mis à jour), souvent plusieurs
            // Go dormants. Les simulateurs utilisables ne sont jamais touchés.
            Shell.sh("xcode-select -p >/dev/null 2>&1 || exit 0; "
                + "xcrun simctl delete unavailable >/dev/null 2>&1; true")
        },
        MaintenanceAction(id: "overrides", nameKey: "maint.over.name", icon: "list.bullet.rectangle.portrait",
            whatKey: "maint.over.what", needsAdmin: true) {
            // Passe par le mode helper root : la base d'overrides appartient à root.
            // Seules les entrées « activé » — donc sans effet — sont retirées.
            Shell.admin("'\(Permissions.cleanBinaryPath)' --prune-overrides")
        },
        MaintenanceAction(id: "fontcache", nameKey: "maint.font.name", icon: "textformat",
            whatKey: "maint.font.what", needsAdmin: false) {
            // Vide la base de caches de polices de la session : corrige les glyphes
            // manquants ou mal rendus. Les caches se reconstruisent automatiquement.
            Shell.sh("command -v atsutil >/dev/null 2>&1 && atsutil databases -removeUser >/dev/null 2>&1; true")
        },
    ]
}
