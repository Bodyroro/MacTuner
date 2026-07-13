//
//  Maintenance.swift — MacTuner
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
    ]
}

