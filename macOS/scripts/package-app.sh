#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_CONFIGURATION="${1:-release}"
"$TASK_ROOT/scripts/swift-build.sh" build -c "$TASK_CONFIGURATION"
TASK_BINARY="$TASK_ROOT/.build/arm64-apple-macosx/$TASK_CONFIGURATION"
if [ ! -f "$TASK_BINARY/Kanyomi" ]; then TASK_BINARY="$TASK_ROOT/.build/x86_64-apple-macosx/$TASK_CONFIGURATION"; fi
TASK_APP="$TASK_ROOT/dist/Kanyomi.app"
rm -rf "$TASK_APP"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BINARY/Kanyomi" "$TASK_APP/Contents/MacOS/"
# SwiftPM resolves Bundle.module beside Bundle.main.bundleURL.
cp -R "$TASK_BINARY/KanyomiMac_Kanyomi.bundle" "$TASK_APP/Contents/Resources/"
cp "$TASK_ROOT/LICENSE" "$TASK_ROOT/THIRD_PARTY.md" "$TASK_APP/Contents/Resources/"
if [ ! -f "$TASK_ROOT/.build/AppIcon.icns" ] || [ "$TASK_ROOT/scripts/MakeIcon.swift" -nt "$TASK_ROOT/.build/AppIcon.icns" ] || [ "$TASK_ROOT/Sources/Kanyomi/Resources/BrandMark.png" -nt "$TASK_ROOT/.build/AppIcon.icns" ]; then
    swift -vfsoverlay "$TASK_ROOT/.build/tooling/toolchain-overlay.json" -module-cache-path "$TASK_ROOT/.build/tooling/swift" "$TASK_ROOT/scripts/MakeIcon.swift" "$TASK_ROOT/.build/AppIcon.iconset" "$TASK_ROOT/Sources/Kanyomi/Resources/BrandMark.png"
    python3 - "$TASK_ROOT/.build" <<'PY_ICON'
from pathlib import Path
import sys,struct
root=Path(sys.argv[1]); chunks=[]
for kind,name in [('icp4','icon_16x16.png'),('icp5','icon_32x32.png'),('icp6','icon_32x32@2x.png'),('ic07','icon_128x128.png'),('ic08','icon_256x256.png'),('ic09','icon_512x512.png'),('ic10','icon_512x512@2x.png')]:
    data=(root/'AppIcon.iconset'/name).read_bytes(); chunks.append(struct.pack('>4sI',kind.encode(),len(data)+8)+data)
data=b''.join(chunks); (root/'AppIcon.icns').write_bytes(struct.pack('>4sI',b'icns',len(data)+8)+data)
PY_ICON
fi
cp "$TASK_ROOT/.build/AppIcon.icns" "$TASK_APP/Contents/Resources/"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Kanyomi</string>
<key>CFBundleIdentifier</key><string>local.kanyomi.macos</string>
<key>CFBundleName</key><string>Kanyomi</string>
<key>CFBundleDisplayName</key><string>Kanyomi</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0-beta.7</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>EPUB book</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSItemContentTypes</key><array><string>org.idpf.epub-container</string></array></dict></array>
</dict></plist>
PLIST
codesign --force --deep --sign - "$TASK_APP"
# Retire only generated packages from the previous product name.
rm -rf "$TASK_ROOT/dist/SimpleReader.app" "$TASK_ROOT/dist/簡単.app" "$TASK_ROOT/dist/簡読み.app"
rm -f "$TASK_ROOT/dist/SimpleReader-macOS-beta.zip" "$TASK_ROOT/dist/Kantan-macOS-beta.zip"
# Include source and licenses alongside the binary for the GPL beta distribution.
# Stage the distributable in a temporary folder. Only one app remains in dist,
# so Launch Services and Finder cannot confuse it with a second identical copy.
TASK_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/Kanyomi-package.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT
TASK_EXPORT="$TASK_STAGE/Kanyomi-macOS-beta"
mkdir -p "$TASK_EXPORT"
cp -R "$TASK_APP" "$TASK_EXPORT/"
cp "$TASK_ROOT/README.md" "$TASK_ROOT/FEATURES.md" "$TASK_ROOT/LICENSE" "$TASK_ROOT/THIRD_PARTY.md" "$TASK_EXPORT/"
tar -czf "$TASK_EXPORT/Source.tar.gz" -C "$TASK_ROOT" Package.swift Sources Tests Vendor scripts README.md FEATURES.md LICENSE THIRD_PARTY.md
ditto -c -k --keepParent "$TASK_EXPORT" "$TASK_ROOT/dist/Kanyomi-macOS-beta.zip"
# Remove the generated staging directory used by older versions of this script.
rm -rf "$TASK_ROOT/dist/Kanyomi-macOS-beta"
printf 'App: %s\n' "$TASK_APP"
