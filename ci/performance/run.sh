#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p performance-output performance-build
xcrun swiftc -swift-version 5 -O -framework AppKit -framework WebKit -framework ApplicationServices \
  ci/performance/RecorderTest.swift -o performance-build/RecorderTest
performance-build/RecorderTest --preflight performance-output/permissions.json
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
python3 -m http.server 8765 --bind 127.0.0.1 --directory ci/performance/web > performance-build/http.log 2>&1 &
WEB_PID=$!
APP_PID=''
RECORD_PID=''
cleanup() {
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; fi
  if [ -n "$RECORD_PID" ]; then kill -INT "$RECORD_PID" 2>/dev/null || true; fi
  kill "$WEB_PID" 2>/dev/null || true
}
trap cleanup EXIT
/usr/sbin/screencapture -v -V 32 -C -m performance-output/TapBench-1.2.0-real-mac-test.mov > performance-output/recording.log 2>&1 &
RECORD_PID=$!
performance-build/TapBench.app/Contents/MacOS/TapBench > performance-output/app.log 2>&1 &
APP_PID=$!
sleep 2
performance-build/RecorderTest "$PWD/performance-output" "$APP_PID" | tee performance-output/test.log
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
