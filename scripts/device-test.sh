#!/usr/bin/env bash
set -euo pipefail
mkdir -p device-results
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
# Only this disposable CI emulator is configured automatically. Real devices opt in in Settings.
adb shell settings put secure enabled_accessibility_services dev.tapbench.autoclicker/.TapService
adb shell settings put secure accessibility_enabled 1
adb shell am instrument -w dev.tapbench.autoclicker.test/dev.tapbench.autoclicker.BenchInstrumentation | tee device-results/instrumentation.txt
adb shell run-as dev.tapbench.autoclicker cat files/benchmark.json > device-results/benchmark.json
adb exec-out screencap -p > device-results/benchmark-screen.png
python3 - <<'PY'
import json
from pathlib import Path
log = Path('device-results/instrumentation.txt').read_text()
assert 'TAPBENCH_DEVICE_TEST_PASSED' in log, log
report = json.loads(Path('device-results/benchmark.json').read_text())
assert report['received_touches'] > 0, report
assert report['completed_gestures'] > 0, report
assert report['target_cps'] == 5000 and not report['running'], report
print(json.dumps(report, indent=2, ensure_ascii=False))
PY
