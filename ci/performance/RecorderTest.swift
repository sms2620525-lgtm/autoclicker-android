import AppKit
import ApplicationServices
import WebKit

func writeJSON(_ value: Any, to path: String) {
    do {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch { print("JSON write error: \(error)") }
}

func permissions() -> [String: Any] {
    let bounds = CGDisplayBounds(CGMainDisplayID())
    return ["accessibility": AXIsProcessTrusted(), "screenRecording": CGPreflightScreenCaptureAccess(),
            "displayWidth": bounds.width, "displayHeight": bounds.height,
            "os": ProcessInfo.processInfo.operatingSystemVersionString]
}

final class TestDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var started = false
    var done = false
    let outputDirectory: String
    let appPID: pid_t
    let pagePath: String
    init(outputDirectory: String, appPID: pid_t, pagePath: String) {
        self.outputDirectory = outputDirectory; self.appPID = appPID; self.pagePath = pagePath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Receiver launched: \(Bundle.main.bundleIdentifier ?? "no bundle")"); fflush(stdout)
        guard AXIsProcessTrusted() else { fail("Accessibility permission is not already granted on this runner."); return }
        guard let screen = NSScreen.main else { fail("No interactive display."); return }
        window = NSWindow(contentRect: screen.visibleFrame.insetBy(dx: 12, dy: 12),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "REAL MAC TEST — TapBench 1.2.0 / fast / total goal 10,000 CPS"
        web = WKWebView(frame: window.contentView!.bounds)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        window.contentView = web
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let page = URL(fileURLWithPath: pagePath)
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 27) { [weak self] in self?.fail("Test timed out without a completed received-input report.") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Receiver page loaded: \(webView.url?.absoluteString ?? "no URL")"); fflush(stdout)
        guard !started else { return }
        started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.prepareTest() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("Page navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("Page load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("WebKit content process terminated.")
    }

    func prepareTest() {
        print("Preparing the real input test."); fflush(stdout)
        // This only arms the measurement UI and compacts layout for the runner display.
        // No pointer or click event is injected into the page by JavaScript.
        let script = #"""
        (() => {
          const style = document.createElement('style');
          style.textContent = `.header,.intro,.guide,.method,.footer,.history-section,.results,.settings .shortcut-note,.settings .start-note,.settings>.small{display:none!important}
            .wrap{width:calc(100% - 28px)!important}.workspace{display:grid!important;grid-template-columns:220px minmax(0,1fr)!important;gap:12px;padding-top:12px}
            .settings{display:flex!important;padding:16px!important}.settings fieldset{display:block!important;margin-top:10px!important}.field-label,.duration-label,.mode-label{margin-top:10px!important}
            .test-panel{padding:16px!important}.pad{min-height:300px!important}.metrics{padding:12px 0!important}
            .point-grid{gap:12px!important}.point-name,.point-shortcut{font-size:11px!important}.metric strong{font-size:26px!important}`;
          document.head.append(style);
          const banner = document.createElement('div');
          banner.textContent = 'LIVE OS INPUT • TapBench 1.2.0 • FAST • 10,000 CPS goal • GitHub macOS / WebKit';
          banner.style.cssText = 'padding:10px 14px;background:#16372b;color:#b8ffdc;font:13px monospace;text-align:center';
          document.body.prepend(banner);
          try { localStorage.removeItem('tapbench-received-history-v1'); } catch {}
          document.getElementById('target').value = '10000';
          document.getElementById('click-mode').value = 'fast';
          document.getElementById('arm').click();
          return [...document.querySelectorAll('[data-point]')].map(e => {
            const r=e.getBoundingClientRect(); return {x:r.left+r.width/2,y:r.top+r.height/2};
          });
        })()
        """#
        web.evaluateJavaScript(script) { [weak self] value, error in
            guard let self = self, !self.done else { return }
            guard error == nil, let positions = value as? [[String: NSNumber]], positions.count == 2 else {
                self.fail("Page setup failed: \(error?.localizedDescription ?? "missing targets")"); return
            }
            let points = positions.map { self.quartzPoint(x: $0["x"]!.doubleValue, y: $0["y"]!.doubleValue) }
            let display = CGDisplayBounds(CGMainDisplayID())
            guard points.allSatisfy({ display.contains($0) }) else { self.fail("Target outside the visible display."); return }
            writeJSON(["points": points.map { ["x": $0.x, "y": $0.y] },
                       "appPID": self.appPID, "release": "macos-7-1", "appVersion": "1.2.0",
                       "appCommit": "68162c13e1979a899942d7a1df78a5fd63910364",
                       "webSourceCommit": "3042c733a0e501d0bfd79718fd3eac51a06f5d0b",
                       "targetCPS": 10000, "mode": "fast", "seconds": 10,
                       "note": "Unmodified released app. JavaScript arms UI only; received pointer pairs originate from macOS input."],
                      to: self.outputDirectory + "/test-configuration.json")
            self.move(points[0])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.hotkey(1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { self.move(points[1]) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.hotkey(2) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { self.hotkey(49) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.5) { self.collectResult() }
        }
    }

    func quartzPoint(x: Double, y: Double) -> CGPoint {
        let local = NSPoint(x: x, y: web.isFlipped ? y : web.bounds.height - y)
        let inWindow = web.convert(local, to: nil)
        let screen = window.convertPoint(toScreen: inWindow)
        return CGPoint(x: screen.x, y: CGDisplayBounds(CGMainDisplayID()).height - screen.y)
    }

    func move(_ point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    func key(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    func hotkey(_ code: CGKeyCode) {
        key(59, true, .maskControl)
        key(58, true, [.maskControl, .maskAlternate])
        key(code, true, [.maskControl, .maskAlternate])
        key(code, false, [.maskControl, .maskAlternate])
        key(58, false, .maskControl)
        key(59, false, [])
    }

    func collectResult() {
        web.evaluateJavaScript("window.__tapbenchCIResult || null") { [weak self] result, error in
            guard let self = self, !self.done else { return }
            guard error == nil, let report = result as? [String: Any],
                  let count = report["receivedClicks"] as? NSNumber,
                  count.intValue > 0, report["completed"] as? Bool == true else {
                self.fail("The released app did not produce a completed nonzero received-click measurement."); return
            }
            self.done = true
            writeJSON(report, to: self.outputDirectory + "/actual-received.json")
            print("REAL INPUT RESULT: \(count) received clicks; average \(report["averageCPS"] ?? "?") CPS; target 10000 CPS.")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSRunningApplication(processIdentifier: self.appPID)?.activate(options: [.activateIgnoringOtherApps])
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            }
        }
    }

    func fail(_ reason: String) {
        guard !done else { return }
        done = true
        writeJSON(["status": "blocked", "reason": reason, "permissions": permissions()], to: outputDirectory + "/blocked.json")
        print("BLOCKED: \(reason)")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
    }
}

@main
struct RecorderTest {
    static func main() {
        let args = CommandLine.arguments
        if args.count >= 3 && args[1] == "--preflight" {
            let result = permissions()
            writeJSON(result, to: args[2])
            print(result)
            return
        }
        guard args.count == 4, let pid = Int32(args[2]) else { fatalError("Usage: RecorderTest OUTPUT_DIRECTORY APP_PID PAGE_PATH") }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = TestDelegate(outputDirectory: args[1], appPID: pid, pagePath: args[3])
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
