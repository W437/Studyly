#!/usr/bin/env python3
"""Prints "<profile UUID> <certificate SHA-1>" for the team's wildcard development profile that names the given phone and whose
signing certificate this Mac holds (and that has not expired), or exits 1. Used by device_isolated.sh (ported from the Dozen repo).

A wildcard profile (`6XH75DGC66.*`) allows only the application identifier, the team, get-task-allow and keychain groups, so an
app signed with it cannot have an App Group, iCloud or push entitlement: the phone would refuse the install.

    python3 -I scripts/device_profile.py <device-udid>
"""
import datetime
import glob
import hashlib
import os
import plistlib
import re
import subprocess
import sys

TEAM_WILDCARD = "6XH75DGC66.*"


def main() -> int:
    udid = sys.argv[1]
    found = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
    local = {m.group(1) for m in re.finditer(r"\d+\) ([0-9A-F]{40}) \"", found)}
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    pattern = os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision")
    candidates = []
    for path in glob.glob(pattern):
        try:
            profile = plistlib.loads(subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True).stdout)
        except Exception:
            continue
        if profile["Entitlements"].get("application-identifier") != TEAM_WILDCARD:
            continue
        if udid not in profile.get("ProvisionedDevices", []) or profile["ExpirationDate"] <= now:
            continue
        for der in profile["DeveloperCertificates"]:
            sha = hashlib.sha1(der).hexdigest().upper()
            if sha in local:
                # Manual signing takes only a manually managed profile: Xcode refuses its own managed ones ("is Xcode managed, but
                # signing settings require a manually managed profile").
                candidates.append((profile["Name"].startswith("iOS Team Provisioning Profile"), profile["Name"], profile["UUID"], sha))
                break
    if not candidates:
        return 1
    _, _, uuid, sha = sorted(candidates)[0]
    print(uuid, sha)
    return 0


if __name__ == "__main__":
    sys.exit(main())
