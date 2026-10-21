#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash ci/performance/prepare.sh
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
