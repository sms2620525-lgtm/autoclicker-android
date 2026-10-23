import Foundation
import ApplicationServices

// CI-only comparison. All routes use real Quartz events and the same receiver.
enum ProbeOutput {
    static func make(points: [CGPoint], route: String, pid: pid_t, windowNumber: Int) -> ClickEngine.PairOutput? {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .privateState) else { return nil }
        source.localEventsSuppressionInterval = 0
        var events: [(CGEvent, CGEvent)] = []
        for point in points {
            guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                     mouseCursorPosition: point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                   mouseCursorPosition: point, mouseButton: .left) else { return nil }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                if route == "pid" {
                    event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
                    event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowNumber))
                    event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowNumber))
                }
            }
            down.setDoubleValueField(.mouseEventPressure, value: 1)
            up.setDoubleValueField(.mouseEventPressure, value: 0)
            events.append((down, up))
        }
        return { index, time, number in
            let (down, up) = events[index]
            func post(_ event: CGEvent) {
                switch route {
                case "pid", "pidraw": event.postToPid(pid)
                case "session": event.post(tap: .cgSessionEventTap)
                case "annotated": event.post(tap: .cgAnnotatedSessionEventTap)
                default: event.post(tap: .cghidEventTap)
                }
            }
            down.timestamp = time
            down.setIntegerValueField(.mouseEventNumber, value: number)
            post(down)
            up.timestamp = DispatchTime.now().uptimeNanoseconds
            up.setIntegerValueField(.mouseEventNumber, value: number)
            post(up)
        }
    }
}
