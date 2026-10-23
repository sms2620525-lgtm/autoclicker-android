#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash ci/performance/prepare.sh
python3 - <<'PY'
import json, os, subprocess, time
from pathlib import Path
root=Path.cwd()
summary=[]
cases=[('hid',1000,'fast'),('pid',1000,'fast'),('pidraw',1000,'fast'),
       ('pid',5000,'fast'),('pid',40000,'fast'),('annotated',40000,'fast')]
for tap, cps, mode in cases:
    name=f'{tap}-{cps}-{mode}'
    folder=root/'performance-build'/name
    folder.mkdir()
    env=dict(os.environ, TAPBENCH_PROBE_TAP=tap,TAPBENCH_PROBE_CPS=str(cps),TAPBENCH_PROBE_MODE=mode)
    args=[str(root/'performance-build/Receiver.app/Contents/MacOS/Receiver'),str(folder),'0',str(root/'performance-build/receiver.html')]
    with (folder/'process.log').open('wb') as log:
        proc=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,env=env)
        try: code=proc.wait(timeout=35)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait(); code=124
    result={'case':name,'tap':tap,'requestedCPS':cps,'mode':mode,'exitCode':code}
    for key, filename in [('posted','posted.json'),('received','actual-received.json'),('native','native-delivery.json')]:
        path=folder/filename
        if path.exists(): result[key]=json.loads(path.read_text())
    for path in folder.iterdir():
        if path.is_file(): (root/'performance-output'/f'{name}-{path.name}').write_bytes(path.read_bytes())
    summary.append(result)
    (root/'performance-output'/'diagnostic-summary.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(result),flush=True)
    time.sleep(2)
assert all('posted' in r and 'received' in r and r['received']['completed'] for r in summary), 'At least one diagnostic did not complete; see partial results.'
PY
