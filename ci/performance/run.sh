#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash ci/performance/prepare.sh
bash macos/scripts/build.sh
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' macos/Info.plist)"
export TAPBENCH_TEST_VERSION="$APP_VERSION"
ditto macos/build/TapBench.app performance-build/TapBench.app
cp macos/dist/* performance-output/
codesign --verify --deep --strict performance-build/TapBench.app
APP_PID=''
RECORD_PID=''
cleanup() {
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$RECORD_PID" ]; then kill -INT "$RECORD_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
/usr/sbin/screencapture -v -V 45 -C -m "performance-output/TapBench-${APP_VERSION}-real-mac-test.mov" > performance-output/recording.log 2>&1 &
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
kill -INT "$RECORD_PID" 2>/dev/null || true
wait "$RECORD_PID" || true
RECORD_PID=''
python3 - <<'PY'
import json
from pathlib import Path
p=Path('performance-output')
r=json.load(open(p/'actual-received.json'))
assert r['completed'] and r['receivedClicks'] > 0
assert sum(t['receivedClicks'] for t in r['receivedByTarget']) == r['receivedClicks']
assert len(r['receivedByTarget']) == 3 and all(t['receivedClicks'] > 0 for t in r['receivedByTarget'])
assert r['targetCPS'] == 40000 and r['measuredSeconds'] == 10
assert r['receivedClicks'] == sum(r['countsPer100ms']) == sum(r['clicksPerSecond'])
assert r['ignoredSyntheticEvents'] == 0
videos=list(p.glob('TapBench-*-real-mac-test.mov'))
assert len(videos)==1 and videos[0].stat().st_size > 10000
print('Actual input, all three targets, complete timing window, and video file verified.')
PY
