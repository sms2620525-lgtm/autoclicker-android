import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

private let testURL = URL(string: "https://tapbench-click-lab.la123923769834767360.chatgpt.site")!

final class AppModel: ObservableObject {
    @Published var cps = "5000"
    @Published var seconds = "10"
    @Published var target: CGPoint?
    @Published var status = "위치를 지정하고 시작하세요."
    @Published var trusted = false
    @Published var busy = false
    @Published var hotkeysReady = false
    @Published var stats = RunStats()
    private let engine = ClickEngine()
    private var hotkeys: Hotkeys?
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var pendingDeadline: Date?
    private var pendingKind: String?
    private var observers: [NSObjectProtocol] = []
    private var refreshCount = 0

    init() {
        trusted = AXIsProcessTrusted()
        hotkeys = Hotkeys { [weak self] id in
            DispatchQueue.main.async {
                if id == 1 { self?.captureNow() } else { self?.toggle() }
            }
        }
        hotkeysReady = hotkeys?.registered ?? false
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.screensDidSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stop("잠자기 또는 세션 변경")
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            self?.stop("화면 구성이 변경되었습니다. 위치를 다시 지정하세요.")
            self?.target = nil
        })
    }

    func refresh() {
        refreshCount += 1
        if refreshCount % 10 == 0 {
            trusted = AXIsProcessTrusted()
            if !trusted && engine.snapshot().active { stop("손쉬운 사용 권한이 해제되었습니다.") }
        }
        stats = engine.snapshot()
        if let deadline = pendingDeadline, let kind = pendingKind {
            status = "\(kind) · \(max(1, Int(ceil(deadline.timeIntervalSinceNow))))초"
        } else if stats.active {
            status = "클릭 중 · 중지 ⌃⌥Space"
        } else if busy {
            busy = false
            status = stats.stopReason
        }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            status = "손쉬운 사용에서 TapBench를 허용한 뒤 돌아오세요."
        }
    }

    func captureNow() {
        guard !busy else { return }
        cancelPending()
        if let point = CGEvent(source: nil)?.location {
            target = point
            status = "위치 지정 완료 · 창을 이동하거나 화면을 스크롤하지 마세요."
        }
    }

    func captureDelayed() {
        guard !busy else { return }
        scheduleAfterThreeSeconds(kind: "포인터를 클릭할 위치에 놓으세요") { [weak self] in self?.captureNow() }
    }

    private func scheduleAfterThreeSeconds(kind: String, action: @escaping () -> Void) {
        cancelPending()
        pendingDeadline = Date().addingTimeInterval(3)
        pendingKind = kind
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.pendingDeadline = nil
            self?.pendingKind = nil
            action()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
        pendingDeadline = nil
        pendingKind = nil
    }

    func toggle() {
        if busy || pending != nil { stop(); return }
        trusted = AXIsProcessTrusted()
        guard trusted else { status = "먼저 손쉬운 사용 권한을 허용하세요."; return }
        guard hotkeysReady else { status = "중지 단축키를 등록할 수 없습니다. 다른 앱의 ⌃⌥Space 단축키를 해제한 뒤 다시 실행하세요."; return }
        guard let point = target else { status = "클릭할 위치를 먼저 지정하세요."; return }
        guard let rate = Int(cps), (1...5000).contains(rate),
              let duration = Int(seconds), (1...3600).contains(duration) else {
            status = "목표 속도는 1–5,000, 실행 시간은 1–3,600의 정수로 입력하세요."
            return
        }
        busy = true
        scheduleAfterThreeSeconds(kind: "시작 대기 · 브라우저로 돌아가세요") { [weak self] in
            guard let self = self else { return }
            if !self.engine.start(point: point, cps: rate, seconds: duration) {
                self.busy = false
                self.status = "시작하지 못했습니다. 손쉬운 사용 권한을 확인하세요."
            }
        }
    }

    func stop(_ reason: String = "사용자 중지") {
        cancelPending()
        engine.stop(reason)
        stats = engine.snapshot()
        busy = false
        status = reason
    }

    func openWebsite() { NSWorkspace.shared.open(testURL) }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TapBench-mac-posted-events.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        struct Report: Encodable {
            let schema = "tapbench-macos-v1"
            let createdAt: Date
            let system: String
            let stats: RunStats
            let postedCPS: Double
            let note = "Posted mouse-down/up pairs are requests to macOS, not proof that the target app received clicks. Use the performance website to measure received clicks."
        }
        do {
            let current = engine.snapshot()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Report(createdAt: Date(), system: ProcessInfo.processInfo.operatingSystemVersionString,
                                                 stats: current, postedCPS: current.postedCPS))
            try data.write(to: url, options: .atomic)
            status = "전송 기록을 저장했습니다."
        } catch { status = "저장 실패: \(error.localizedDescription)" }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 32)).foregroundColor(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TapBench").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("macOS 오토클릭커").foregroundColor(.secondary)
                }
                Spacer()
                Text("MAC").font(.caption.monospaced()).padding(8).background(.white.opacity(0.08)).cornerRadius(8)
            }
            HStack {
                Image(systemName: model.trusted ? "checkmark.circle.fill" : "lock.circle").foregroundColor(model.trusted ? .mint : .orange)
                Text(model.trusted ? "손쉬운 사용 허용됨" : "클릭하려면 손쉬운 사용 권한이 필요합니다.").font(.callout)
                Spacer()
                Button("권한 설정", action: model.requestPermission).disabled(model.busy)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("01   클릭 위치").font(.headline)
                Text(model.target.map { String(format: "X  %.0f     Y  %.0f", $0.x, $0.y) } ?? "지정되지 않음")
                    .font(.system(size: 24, weight: .medium, design: .monospaced)).foregroundColor(.mint)
                HStack {
                    Button("3초 후 현재 위치 지정", action: model.captureDelayed).disabled(model.busy)
                    Text("또는 포인터를 놓고 ⌃⌥S").font(.caption).foregroundColor(.secondary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05)).cornerRadius(14)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("02   목표 속도 · 회/초").font(.headline)
                    TextField("1–5000", text: $model.cps).textFieldStyle(.roundedBorder).disabled(model.busy)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("03   실행 시간 · 초").font(.headline)
                    TextField("1–3600", text: $model.seconds).textFieldStyle(.roundedBorder).disabled(model.busy)
                }
            }
            HStack {
                Button(model.busy ? "중지  ⌃⌥Space" : "3초 후 시작  ⌃⌥Space", action: model.toggle)
                    .buttonStyle(.borderedProminent).tint(model.busy ? .red : .mint).controlSize(.large)
                Spacer()
                Button("성능 테스트 웹사이트 ↗", action: model.openWebsite).disabled(model.busy)
            }
            Text(model.status).font(.callout).foregroundColor(model.busy ? .mint : .secondary)
                .frame(height: 38, alignment: .leading)
            HStack(spacing: 30) {
                metric("전송한 클릭 쌍", "\(model.stats.postedPairs)")
                metric("전송 속도", String(format: "%.1f CPS", model.stats.postedCPS))
                metric("실행 시간", String(format: "%.1f초", model.stats.elapsedSeconds))
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05)).cornerRadius(12)
            Text("5,000 CPS는 목표입니다. 위 수치는 macOS에 전송한 요청이며, 실제 수신 속도는 테스트 웹사이트에서 확인하세요. 지연된 클릭은 몰아서 실행하지 않습니다.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("전역 단축키: \(model.hotkeysReady ? "준비됨" : "등록 실패")").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("전송 기록 JSON 저장", action: model.export).disabled(model.busy || model.stats.postedPairs == 0)
            }
        }.padding(28).frame(width: 540).preferredColorScheme(.dark)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 21, weight: .semibold, design: .monospaced))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TapBenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("TapBench") { ContentView(model: model) }
            .windowResizability(.contentSize)
            .commands {
                CommandGroup(replacing: .newItem) { }
                CommandMenu("클릭") {
                    Button("시작 / 중지", action: model.toggle)
                    Button("현재 포인터 위치 지정", action: model.captureNow)
                    Button("성능 테스트 웹사이트", action: model.openWebsite)
                }
            }
    }
}
