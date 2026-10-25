#!/bin/bash
# Builds Cramless (Debug) for a connected phone WITHOUT its App Group, Sign in with Apple and Declared Age Range
# entitlements, installs it, and optionally launches it. Ported from the Dozen repo's script of the same name.
#
#   scripts/device_isolated.sh <device-udid> [--launch]      (BUILD_ONLY=1 builds and checks the signing, installs nothing)
#
# It signs with the team's WILDCARD development profile that names the phone (scripts/device_profile.py), so no capability can
# be requested and the developer account is never contacted (no -allowProvisioningUpdates). The app falls back to its own
# sandbox: widgets get no snapshot (no App Group), Sign in with Apple and the age range are unavailable; everything else (the
# camera scanner, Foundation Models, speech, haptics, Live Activities, notifications) is the real thing. Delete the app on the
# phone to undo it.
set -u
udid=${1:?usage: scripts/device_isolated.sh <device-udid> [--launch]}
launch=${2:-}
cd "$(dirname "$0")/.." || exit 1

state=$(xcrun devicectl list devices 2>/dev/null | grep "$udid" | head -1)
echo "device: ${state:-not listed}"
case "$state" in *"available"*|*"connected"*) ;; *) echo "the device is not connected; nothing was built"; exit 2 ;; esac

mkdir -p build
read -r profile identity < <(python3 -I scripts/device_profile.py "$udid")
[ -n "${profile:-}" ] || { echo "no valid wildcard development profile for this phone and a certificate on this Mac; nothing was built"; exit 4; }
echo "signing with the wildcard profile $profile and certificate ${identity:0:12}"
profile_file="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$profile.mobileprovision"
[ -f "$profile_file" ] || profile_file="$HOME/Library/MobileDevice/Provisioning Profiles/$profile.mobileprovision"

if [ ! -f Secrets.xcconfig ]; then
  printf '%s\n' 'CRAMLESS_SUPABASE_HOST =' 'CRAMLESS_SUPABASE_ANON_KEY =' > Secrets.xcconfig
fi
/opt/homebrew/bin/xcodegen generate --quiet || exit 1

# Built unsigned, then signed here: works for both Xcode-managed and manual wildcard profiles.
xcodebuild -project Cramless.xcodeproj -scheme Cramless -configuration Debug \
  -destination "id=$udid" -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > build/xc-device.log 2>&1
status=$?
grep -E ":[0-9]+:[0-9]+: error:|BUILD (SUCCEEDED|FAILED)" build/xc-device.log | tail -8
[ $status -eq 0 ] || { echo "the build failed; nothing was installed (log: build/xc-device.log)"; exit $status; }

app=build/device/Build/Products/Debug-iphoneos/Cramless.app
team=6XH75DGC66
sign_bundle() {
  local bundle=$1 bid ents
  bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")
  ents="build/device-resign-$bid.entitlements"
  cat > "$ents" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>application-identifier</key><string>$team.$bid</string>
  <key>com.apple.developer.team-identifier</key><string>$team</string>
  <key>get-task-allow</key><true/>
</dict>
</plist>
PLIST
  cp "$profile_file" "$bundle/embedded.mobileprovision" || return 1
  /usr/bin/codesign --force --sign "$identity" --entitlements "$ents" --generate-entitlement-der "$bundle" 2>&1 | grep -v "replacing existing signature" || true
}
# Nested code first (Debug builds put a <Name>.debug.dylib and __preview.dylib beside each executable), then the
# extensions, then the app.
for dylib in "$app"/*.dylib "$app"/Frameworks/* "$app"/PlugIns/*.appex/*.dylib "$app"/PlugIns/*.appex/Frameworks/*; do
  [ -e "$dylib" ] && /usr/bin/codesign --force --sign "$identity" "$dylib" 2>&1 | grep -v "replacing existing signature"
done
for ext in "$app"/PlugIns/*.appex; do sign_bundle "$ext" || { echo "signing $ext failed; nothing was installed"; exit 6; }; done
sign_bundle "$app" || { echo "signing the app failed; nothing was installed"; exit 6; }
/usr/bin/codesign --verify --deep --strict "$app" 2>&1 | head -3

for bundle in "$app" "$app"/PlugIns/*.appex; do
  if codesign -d --entitlements :- "$bundle" 2>/dev/null | grep -Eq "application-groups|icloud|aps-environment|applesignin|declared-age-range"; then
    echo "REFUSED: $(basename "$bundle") carries an entitlement the wildcard profile can't; nothing was installed"
    exit 3
  fi
done

[ "${BUILD_ONLY:-}" = "1" ] && { echo "built and checked; BUILD_ONLY=1, so nothing was installed"; exit 0; }
xcrun devicectl device install app --device "$udid" "$app" 2>&1 | tail -4
if [ "$launch" = "--launch" ]; then
  xcrun devicectl device process launch --device "$udid" com.loopware.Capling 2>&1 | tail -3
fi
