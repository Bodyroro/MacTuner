#!/usr/bin/env python3
"""
Vérifie que chaque service référencé par TweakCatalog.swift existe RÉELLEMENT
sur cette machine, dans le bon domaine launchd.

Pourquoi c'est indispensable : `launchctl disable gui/<uid>/<label>` réussit
(code 0) même pour un label inexistant. Le drapeau est écrit, aucun processus
n'est trouvé, et l'application conclut « désactivé » alors que rien n'a été fait.
Une simple faute de casse suffit — c'est exactement ainsi que la Bibliothèque
musicale iCloud (« iTunesCloudd » au lieu de « itunescloudd ») n'a jamais agi.

Le LABEL fait foi, pas le nom de fichier : les deux diffèrent pour plusieurs
services d'Apple (corespeechd.system.plist déclare « com.apple.corespeechd_system »).
"""
import glob
import plistlib
import re
import subprocess
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Sources/Features/TweakCatalog.swift")
ALLOWLIST = os.path.join(ROOT, "Sources/Core/Shell.swift")
ROLES = os.path.join(ROOT, "Sources/Features/ServiceCatalog.swift")
DIRS = [("/System/Library/LaunchAgents", "agent"),
        ("/System/Library/LaunchDaemons", "daemon")]


def real_services():
    """Index (label, domaine) -> plist, d'après la clé Label déclarée."""
    found = {}
    for directory, domain in DIRS:
        for path in glob.glob(directory + "/*.plist"):
            label = None
            try:
                with open(path, "rb") as fh:
                    label = plistlib.load(fh).get("Label")
            except Exception:
                # Quelques plists ne sont pas lisibles par plistlib : PlistBuddy sait.
                out = subprocess.run(["/usr/libexec/PlistBuddy", "-c", "print Label", path],
                                     capture_output=True, text=True)
                if out.returncode == 0:
                    label = out.stdout.strip()
            if label:
                found.setdefault((label, domain), path)
    return found


def catalog_services():
    src = open(CATALOG, encoding="utf-8").read()
    refs = []
    for block in re.split(r'\n    Tweak\(id: "', src)[1:]:
        tid = block.split('"')[0]
        mech = block[block.index("mechanisms:"):]
        for domain, pattern in (("agent", r'\.agents\(\[(.*?)\]\)'),
                                ("daemon", r'\.systemDaemons\(\[(.*?)\]\)')):
            for group in re.finditer(pattern, mech, re.S):
                for label in re.findall(r'"([^"]+)"', group.group(1)):
                    refs.append((tid, label, domain))
    return refs


def roles():
    """Libellés décrits dans serviceRoles (onglet Services)."""
    src = open(ROLES, encoding="utf-8").read()
    return set(re.findall(r'^    "([^"]+)":', src, re.M))


def allowlist():
    src = open(ALLOWLIST, encoding="utf-8").read()
    block = re.search(r'static let allowed: Set<String> = \[(.*?)\n    \]', src, re.S)
    return set(re.findall(r'"([^"]+)"', block.group(1))) if block else set()


def main():
    real = real_services()
    refs = catalog_services()
    problems = []

    for tid, label, domain in refs:
        if (label, domain) in real:
            continue
        other = "daemon" if domain == "agent" else "agent"
        if (label, other) in real:
            problems.append(f"MAUVAIS DOMAINE  [{tid}] {label} — existe comme {other}")
            continue
        near = [lb for (lb, d) in real if lb.lower() == label.lower() and d == domain]
        hint = f" — casse ? {near[0]}" if near else ""
        problems.append(f"INTROUVABLE      [{tid}] {label} ({domain}){hint}")

    # La liste blanche root doit correspondre EXACTEMENT aux démons du catalogue :
    # un démon oublié ne serait jamais désactivé, un démon en trop élargirait
    # inutilement ce que le helper root accepte de toucher.
    cat_daemons = {l for _, l, d in refs if d == "daemon"}
    allowed = allowlist()
    for extra in sorted(allowed - cat_daemons):
        problems.append(f"LISTE BLANCHE    {extra} autorisé mais absent du catalogue")
    for missing in sorted(cat_daemons - allowed):
        problems.append(f"LISTE BLANCHE    {missing} utilisé mais absent de SystemDaemons.allowed")

    # Chaque service référencé doit avoir un rôle décrit, sinon l'onglet Services
    # afficherait une ligne muette. L'inverse aussi : un rôle sans service est mort.
    described = roles()
    cat_labels = {l for _, l, _ in refs}
    for missing in sorted(cat_labels - described):
        problems.append(f"RÔLE MANQUANT    {missing} n'est pas décrit dans serviceRoles")
    for orphan in sorted(described - cat_labels):
        problems.append(f"RÔLE ORPHELIN    {orphan} décrit mais référencé par aucune fiche")

    agents = len([r for r in refs if r[2] == "agent"])
    daemons = len(refs) - agents
    if problems:
        print(f"✗ {len(problems)} problème(s) sur {len(refs)} services référencés :")
        for p in problems:
            print("   " + p)
        return 1
    print(f"✓ {len(refs)} services vérifiés ({agents} agents · {daemons} démons), "
          f"{len(described)} rôles décrits, liste blanche root cohérente")
    return 0


if __name__ == "__main__":
    sys.exit(main())
