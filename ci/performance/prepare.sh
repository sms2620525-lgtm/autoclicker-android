#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p performance-output performance-build/Receiver.app/Contents/MacOS
node --test ci/performance/tests/benchmark.test.mjs | tee performance-output/web-tests.txt
xcrun swiftc -parse-as-library -swift-version 5 -O -framework AppKit -framework WebKit -framework ApplicationServices \
  macos/Sources/RunSchedule.swift macos/Sources/ClickEngine.swift ci/performance/ProbeOutput.swift ci/performance/RecorderTest.swift -o performance-build/Receiver.app/Contents/MacOS/Receiver
python3 - <<'PY'
import plistlib
from pathlib import Path
with open('performance-build/Receiver.app/Contents/Info.plist', 'wb') as f:
    plistlib.dump({'CFBundleIdentifier':'dev.tapbench.ci.receiver', 'CFBundleName':'TapBench Test Receiver',
                  'CFBundleExecutable':'Receiver', 'CFBundlePackageType':'APPL',
                  'NSPrincipalClass':'NSApplication'}, f)
web=Path('ci/performance/web')
html=(web/'index.html').read_text()
html=html.replace('<link rel="icon" href="/favicon.svg" type="image/svg+xml">', '')
html=html.replace('<link rel="stylesheet" href="/styles.css">', '<style>'+(web/'styles.css').read_text()+'</style>')
app=(web/'app.mjs').read_text()
app=app.replace("import { Benchmark, PointerGate } from './benchmark.mjs';", '', 1)
script=(web/'benchmark.mjs').read_text()+'\n'+app
# This getter only exposes the report already produced by the unchanged measuring code.
script+="\nObject.defineProperty(window, '__tapbenchCIResult', {get: () => savedResult});\n"
script+="\nlet reportSent = false; setInterval(() => { if (savedResult && !reportSent) { reportSent = true; window.webkit.messageHandlers.measurement.postMessage(savedResult); } }, 200);\n"
html=html.replace('<script type="module" src="/app.mjs"></script>', '<script type="module">'+script+'</script>')
Path('performance-build/receiver.html').write_text(html)
PY
codesign --force --sign - performance-build/Receiver.app
performance-build/Receiver.app/Contents/MacOS/Receiver --preflight performance-output/permissions.json
python3 - <<'PY'
import json
p=json.load(open('performance-output/permissions.json'))
assert p['accessibility'], 'Runner has no pre-existing Accessibility permission; no permission changes will be made.'
assert p['screenRecording'], 'Runner has no pre-existing Screen Recording permission; no permission changes will be made.'
PY
