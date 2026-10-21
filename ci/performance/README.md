# TapBench 1.2.0 — real Mac input recording

This workflow runs the unchanged, SHA-256-verified app from `macos-7-1` on a GitHub-hosted macOS 15 VM. It selects two targets using the app's global hotkeys and starts the app at its default fast mode / total goal 10,000 CPS / 10 seconds.

The receiving page is an exact snapshot of TapBench web source `3042c733a0e501d0bfd79718fd3eac51a06f5d0b`, served on localhost in WKWebView. The harness changes only layout and arms the measurement. It does not generate page pointer events or increment counts. All measured clicks arrive through the released app and macOS input dispatch. The page counts trusted primary pointer down/up pairs.

`actual-received.json` is the browser's measured report. `test-configuration.json` records target coordinates and release identity. The MOV is a live screen recording with no speed adjustment. Recording overhead, the hosted VM and WebKit affect the result; it is not a claim about every Mac or browser. If `blocked.json` or permission failure is present, the test did not complete and no successful performance claim should be made.

The workflow only uses permissions already granted on the runner image. It does not modify TCC, disable security protections, or add recording features to the shipped app.
