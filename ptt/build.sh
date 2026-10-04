#!/bin/bash
# Build Pardon.app from the Swift package in ptt/: swift build, write Info.plist, sign. Does not install or open.
#
#   SWIFT       Swift driver (default /usr/bin/swift, from Xcode Command Line Tools)
#   BUILD_DIR   output directory (default build; relative to ptt/ unless absolute); SwiftPM keeps its cache in BUILD_DIR/swiftpm
#   SIGN=0      skip signing (the CodeQL build)
#
# Signs with the "Pardon" identity from `make ptt-cert` if present, else ad-hoc.
# Run from anywhere:  ./ptt/build.sh   (or: make ptt)
set -euo pipefail
cd "$(dirname "$0")"

SWIFT="${SWIFT:-/usr/bin/swift}"
BUILD_DIR="${BUILD_DIR:-build}"
SIGN="${SIGN:-1}"
BUNDLE_ID="io.github.abandisch.pardon"
APP="$BUILD_DIR/Pardon.app"
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# hw.optional.arm64, not uname -m: under Rosetta (CodeQL's build tracer) uname reports x86_64.
[ "$(uname -s)" = Darwin ] && [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] || die "needs macOS on Apple Silicon"
[ -x "$SWIFT" ] || die "swift not found at $SWIFT — install Xcode Command Line Tools: xcode-select --install"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftpm=(-c release --arch arm64 --scratch-path "$BUILD_DIR/swiftpm")
"$SWIFT" build "${swiftpm[@]}" --product Pardon
bin="$("$SWIFT" build "${swiftpm[@]}" --show-bin-path)"
# swift build targets the running process's architecture, which is x86_64 under Rosetta.
[ "$(/usr/bin/lipo -archs "$bin/Pardon")" = arm64 ] || die "$bin/Pardon is not arm64 only — build from a native arm64 shell"
cp "$bin/Pardon" "$APP/Contents/MacOS/Pardon"

BUILD="$( (git describe --tags --always --dirty 2>/dev/null || echo unknown) | tr -cd 'A-Za-z0-9._+-')"
BUILD="${BUILD:-unknown}"
if [[ "$BUILD" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+) ]]; then
  VERSION="${BASH_REMATCH[1]}"
else
  VERSION="0.0.0"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Pardon</string>
  <key>CFBundleName</key><string>Pardon</string>
  <key>CFBundleDisplayName</key><string>Pardon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>PardonBuild</key><string>$BUILD</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key><string>Pardon records your voice only while you are dictating with the Option key or the floating pet, and sends it only to the speech-to-text container on this Mac.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null

cat > "$BUILD_DIR/Pardon.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$BUILD_DIR/Pardon.entitlements" >/dev/null

if [ "$SIGN" != 0 ]; then
  # Without the hardened runtime, DYLD_INSERT_LIBRARIES could load foreign code into a process
  # holding the Microphone and Accessibility grants.
  sign=(/usr/bin/codesign --force --options runtime --entitlements "$BUILD_DIR/Pardon.entitlements" --identifier "$BUNDLE_ID")
  # No -v: an untrusted self-signed identity is listed only without it.
  ids="$(/usr/bin/security find-identity -p codesigning || true)"
  if grep -q '"Pardon"' <<<"$ids"; then
    "${sign[@]}" --sign Pardon "$APP" \
      || die "the \"Pardon\" identity could not sign — delete it in Keychain Access and run make ptt-cert again"
  else
    warn "no \"Pardon\" signing identity: ad-hoc signed, so macOS will ask for Microphone and Accessibility again after every rebuild (make ptt-cert fixes it)"
    "${sign[@]}" --sign - "$APP"
  fi
fi

echo "built $(cd "$BUILD_DIR" && pwd)/Pardon.app ($BUILD)"
