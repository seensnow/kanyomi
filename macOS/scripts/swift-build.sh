#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_CACHE="$TASK_ROOT/.build/tooling"
mkdir -p "$TASK_CACHE/ManifestAPI" "$TASK_CACHE/clang" "$TASK_CACHE/swift" "$TASK_CACHE/spm"
# Some upgraded Command Line Tools retain a Swift 5 private manifest interface
# beside a Swift 6 public interface and library. Use an isolated corrected copy.
TASK_MANIFEST="$(xcrun --find swiftc | sed 's|/bin/swiftc$|/lib/swift/pm/ManifestAPI|')"
cp -R "$TASK_MANIFEST/PackageDescription.swiftmodule" "$TASK_CACHE/ManifestAPI/"
cp "$TASK_MANIFEST/libPackageDescription.dylib" "$TASK_CACHE/ManifestAPI/"
for TASK_INTERFACE in "$TASK_CACHE/ManifestAPI/PackageDescription.swiftmodule/"*.private.swiftinterface; do
    if [ -f "$TASK_INTERFACE" ]; then cp "${TASK_INTERFACE/.private.swiftinterface/.swiftinterface}" "$TASK_INTERFACE"; fi
done
cat > "$TASK_CACHE/swiftc-wrapper.py" <<'PY'
#!/usr/bin/env python3
import os, sys
args = [a.replace(os.environ['SR_SYSTEM_MANIFEST'], os.environ['SR_FIXED_MANIFEST']) for a in sys.argv[1:]]
args += ['-vfsoverlay', os.environ['SR_OVERLAY']]
os.execv(os.environ['SR_SWIFTC'], [os.environ['SR_SWIFTC']] + args)
PY
chmod +x "$TASK_CACHE/swiftc-wrapper.py"
export SR_SYSTEM_MANIFEST="$TASK_MANIFEST" SR_FIXED_MANIFEST="$TASK_CACHE/ManifestAPI" SR_SWIFTC="$(xcrun --find swiftc)"
export SWIFT_EXEC="$TASK_CACHE/swiftc-wrapper.py" CLANG_MODULE_CACHE_PATH="$TASK_CACHE/clang" SWIFTPM_MODULECACHE_OVERRIDE="$TASK_CACHE/swift"
export SR_OVERLAY="$TASK_CACHE/toolchain-overlay.json"
python3 - <<'PY_OVERLAY'
import json,os,pathlib
empty=pathlib.Path(os.environ['SR_FIXED_MANIFEST']).parent/'empty.modulemap'
empty.write_text('// Superseded by bridging.modulemap in this toolchain.\n')
legacy=pathlib.Path(os.environ['SR_SWIFTC']).parents[1]/'include/swift/module.modulemap'
pathlib.Path(os.environ['SR_OVERLAY']).write_text(json.dumps({'version':0,'roots':[{'type':'file','name':str(legacy),'external-contents':str(empty)}]}))
PY_OVERLAY
TASK_COMMAND="${1:-build}"
if [ "$#" -gt 0 ]; then shift; fi
if [ "$TASK_COMMAND" = "test" ]; then
    TASK_FRAMEWORKS="$(xcrun --find swiftc | sed 's|/usr/bin/swiftc$|/Library/Developer/Frameworks|')"
    set -- --disable-xctest -Xswiftc -F -Xswiftc "$TASK_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TASK_FRAMEWORKS" "$@"
fi
exec swift "$TASK_COMMAND" --package-path "$TASK_ROOT" --disable-sandbox --cache-path "$TASK_CACHE/spm" -Xcxx -isystem -Xcxx "$(xcrun --show-sdk-path)/usr/include/c++/v1" "$@"
