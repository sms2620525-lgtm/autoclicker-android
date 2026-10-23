import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

private let testURL = URL(string: "https://tapbench-click-lab.la123923769834767360.chatgpt.site")!

final class AppModel: ObservableObject {
    @Published var cps = String(ClickLimits.defaultCPS)
    @Published var mode: ClickMode = ClickLimits.defaultMode
    @Published var seconds = "10"
    @Published var targetCount = ClickLimits.maxTargets
    @Published var targets: [CGPoint?] = Array(repeating: nil, count: ClickLimits.maxTargets)
    @Published var status = "1번·2번·3번 위치를 지정하고 시작하세요."
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
                switch id {
                case 1: self?.captureNow(index: 0)
                case 3: self?.captureNow(index: 1)
                case 4: self?.captureNow(index: 2)
                default: self?.toggle()
                }
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
            self?.targets = Array(repeating: nil, count: ClickLimits.maxTargets)
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
            status = (1...stats.targets.count).map { String($0) }.joined(separator: " → ") + " 클릭 중 · 중지 ⌃⌥Space"
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

    func captureNow(index: Int) {
        guard !busy, (0..<targetCount).contains(index) else { return }
        cancelPending()
        if let point = CGEvent(source: nil)?.location {
            targets[index] = point
            status = "\(index + 1)번 위치 지정 완료 · 창을 이동하거나 화면을 스크롤하지 마세요."
        }
    }

    func captureDelayed(index: Int) {
        guard !busy, (0..<targetCount).contains(index) else { return }
        scheduleAfterThreeSeconds(kind: "포인터를 \(index + 1)번 위치에 놓으세요") { [weak self] in self?.captureNow(index: index) }
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
        guard hotkeysReady else { status = "단축키를 등록할 수 없습니다. 다른 앱의 ⌃⌥S / ⌃⌥D / ⌃⌥F / ⌃⌥Space 설정을 확인한 뒤 다시 실행하세요."; return }
        let points = targets.prefix(targetCount).compactMap { $0 }
        guard points.count == targetCount else { status = "선택한 \(targetCount)개 위치를 모두 지정하세요."; return }
        guard let rate = Int(cps), (1...ClickLimits.maxCPS).contains(rate),
              let duration = Int(seconds), (1...3600).contains(duration) else {
            status = "목표 속도는 1–40,000, 실행 시간은 1–3,600의 정수로 입력하세요."
            return
        }
        let selectedMode = mode
        busy = true
        scheduleAfterThreeSeconds(kind: "시작 대기 · 브라우저로 돌아가세요") { [weak self] in
            guard let self = self else { return }
            if !self.engine.start(points: points, cps: rate, seconds: duration, mode: selectedMode) {
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
            let schema = "tapbench-macos-v4"
            let appVersion = "1.3.0"
            let createdAt: Date
            let system: String
            let stats: RunStats
            let postedCPS: Double
            let note = "Target CPS is total across all points. Fast mode posts only due slots in batches of at most 32, dropping older backlog; steady mode posts at most one pair per callback. Points alternate by posted pairs. Posted pairs are requests to macOS, not proof that the target app received clicks."
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
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 32)).foregroundColor(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TapBench").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("macOS 오토클릭커 · 1.3.0").foregroundColor(.secondary)
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
                HStack {
                    Text("01   클릭 위치").font(.headline)
                    Spacer()
                    Picker("클릭 지점 수", selection: $model.targetCount) {
                        Text("1개").tag(1)
                        Text("2개 교대").tag(2)
                        Text("3개 교대").tag(3)
                    }.pickerStyle(.segmented).frame(width: 235).disabled(model.busy)
                }
                ForEach(0..<model.targetCount, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.headline).foregroundColor(.mint).frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.targets[index].map { String(format: "X %.0f   Y %.0f", $0.x, $0.y) } ?? "지정되지 않음")
                                .font(.system(size: 17, weight: .medium, design: .monospaced))
                            Text("포인터를 놓고 " + ["⌃⌥S", "⌃⌥D", "⌃⌥F"][index])
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("3초 후 지정") { model.captureDelayed(index: index) }.disabled(model.busy)
                    }
                }
                Text((1...model.targetCount).map { "\($0)번" }.joined(separator: " → ") + " 순서로 반복 클릭합니다.")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05)).cornerRadius(14)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("02   총 목표 속도 · 회/초").font(.headline)
                    TextField("1–40000", text: $model.cps).textFieldStyle(.roundedBorder).disabled(model.busy)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("03   실행 시간 · 초").font(.headline)
                    TextField("1–3600", text: $model.seconds).textFieldStyle(.roundedBorder).disabled(model.busy)
                }
            }
            HStack {
                Text("클릭 방식").font(.headline)
                Picker("클릭 방식", selection: $model.mode) {
                    ForEach(ClickMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented).disabled(model.busy)
                ForEach([1000, 10000, 40000], id: \.self) { rate in
                    Button(rate >= 1000 ? "\(rate / 1000)k" : String(rate)) { model.cps = String(rate) }.disabled(model.busy)
                }
            }
            Text("총 목표를 선택한 \(model.targetCount)개 지점에 나눕니다. 3개에서 총 40,000 CPS이면 지점당 약 13,333 CPS입니다.")
                .font(.caption).foregroundColor(.secondary)
            Text(model.mode == .fast ? "고속: 짧은 묶음으로 전송합니다. 목표가 높아져도 실제 수신 속도는 느려질 수 있습니다." : "기존 방식: 타이머가 깨어날 때 한 번씩 전송하며 밀린 클릭은 건너뜁니다.")
                .font(.caption).foregroundColor(.secondary)
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
            if !model.stats.targets.isEmpty {
                HStack(spacing: 24) {
                    ForEach(Array(model.stats.targets.enumerated()), id: \.offset) { index, target in
                        Text("\(index + 1)번 전송: \(target.postedPairs)회").font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                }
            }
            Text("40,000 CPS는 설정 상한입니다. 위 수치는 macOS에 전송한 요청이며, 실제 수신 속도는 테스트 웹사이트에서 확인하세요. 고속 모드는 한 번에 최대 32쌍만 처리하고 오래 밀린 요청은 버립니다.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("전역 단축키: \(model.hotkeysReady ? "준비됨" : "등록 실패")").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("전송 기록 JSON 저장", action: model.export).disabled(model.busy || model.stats.postedPairs == 0)
            }
        }.padding(24)
        }.frame(width: 580, height: 700).preferredColorScheme(.dark)
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
                    Button("1번 위치 지정") { model.captureNow(index: 0) }
                    Button("2번 위치 지정") { model.captureNow(index: 1) }
                    Button("3번 위치 지정") { model.captureNow(index: 2) }
                    Button("성능 테스트 웹사이트", action: model.openWebsite)
                }
            }
    }
}
