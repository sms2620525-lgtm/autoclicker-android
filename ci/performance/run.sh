#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p performance-output performance-build/Receiver.app/Contents/MacOS
xcrun swiftc -parse-as-library -swift-version 5 -O -framework AppKit -framework WebKit -framework ApplicationServices \
  ci/performance/RecorderTest.swift -o performance-build/Receiver.app/Contents/MacOS/Receiver
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
gh release download macos-7-1 --pattern 'TapBench-1.2.0-universal.zip' --dir performance-build
python3 - <<'PY'
import hashlib
from pathlib import Path
p=Path('performance-build/TapBench-1.2.0-universal.zip')
assert hashlib.sha256(p.read_bytes()).hexdigest()=='40b671befba07460c699d05ac0a4d890acf5c369f6b98e4aeedc3264064b300f'
print('Released app ZIP SHA-256 verified')
PY
ditto -x -k performance-build/TapBench-1.2.0-universal.zip performance-build
codesign --verify --deep --strict performance-build/TapBench.app
APP_PID=''
RECORD_PID=''
cleanup() {
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$RECORD_PID" ]; then kill -INT "$RECORD_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
/usr/sbin/screencapture -v -V 45 -C -m performance-output/TapBench-1.2.0-real-mac-test.mov > performance-output/recording.log 2>&1 &
RECORD_PID=$!
performance-build/TapBench.app/Contents/MacOS/TapBench > performance-output/app.log 2>&1 &
APP_PID=$!
sleep 5
python3 - "$APP_PID" <<'PY'
import subprocess, sys
from pathlib import Path
p=Path.cwd()
args=[str(p/'performance-build/Receiver.app/Contents/MacOS/Receiver'),str(p/'performance-output'),sys.argv[1],str(p/'performance-build/receiver.html')]
try:
    r=subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    output=r.stdout
    code=r.returncode
except subprocess.TimeoutExpired as e:
    output=(e.stdout or b'')+b'\nReceiver process timeout.\n'
    code=1
(p/'performance-output/test.log').write_bytes(output)
print(output.decode(errors='replace'))
sys.exit(code)
PY
wait "$RECORD_PID"
RECORD_PID=''
python3 - <<'PY'
import json
from pathlib import Path
p=Path('performance-output')
r=json.load(open(p/'actual-received.json'))
assert r['completed'] and r['receivedClicks'] > 0
assert sum(t['receivedClicks'] for t in r['receivedByTarget']) == r['receivedClicks']
assert all(t['receivedClicks'] > 0 for t in r['receivedByTarget'])
assert (p/'TapBench-1.2.0-real-mac-test.mov').stat().st_size > 10000
print('Actual input, both targets, complete timing window, and video file verified.')
PY
