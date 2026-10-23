# TapBench — actual Mac input recording and tested DMG

The video workflow builds the production Swift app at the workflow commit, runs the native tests, produces the universal DMG/ZIP, then runs that same app on a GitHub-hosted macOS 15 VM. It selects three targets using the app's global hotkeys and starts the app at its default three-point / 40,000 total requested CPS / fast settings for 10 seconds. The release includes the tested DMG, ZIP, checksums and native test results.

The receiving page uses the web source in `ci/performance/web` at the same workflow commit, with the same measuring code bundled inline in a local file opened by WKWebView. A read-only getter exposes its completed report. The harness compacts layout and arms measurement; it never generates page pointer events or increments counts. All measured clicks arrive through the production app and macOS input dispatch. The page counts trusted primary pointer down/up pairs.

`actual-received.json` is the browser's measured report. `test-configuration.json` records target coordinates, settings and build identity. The MOV is a live screen recording with no speed adjustment. Recording overhead, the hosted VM and WebKit affect the result; it is not a claim about every Mac or browser. If `blocked.json` or permission failure is present, no successful performance claim should be made.

The separate diagnostic workflow uses the production scheduler with a CI-only event output to compare pacing and event taps. Its results are explicitly engine diagnostics, not released-app benchmarks. Native delivery counts cover launch through receipt of the completed web report, while browser CPS uses a 10-second handler-time window.

The workflows only use permissions already granted on the runner image. They do not modify TCC or add recording features to the shipped app. The receiver keeps the result visible for five seconds and exits from a background queue, avoiding a cross-app activation wait after input saturation.
