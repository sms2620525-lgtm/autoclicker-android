package dev.tapbench.autoclicker;

/** Single-thread-confined, bounded single-flight scheduler. No busy spin or queued backlog. */
public final class TapEngine {
    /** Upper bound of the target rate setting. A request, never a guaranteed throughput. */
    public static final int MAX_CPS = 90_000;
    public interface Clock { long now(); }
    public interface Queue { void post(Runnable task, long delayMillis); void remove(Runnable task); }
    public interface Result { void complete(boolean success); }
    public interface Injector { boolean dispatch(Result result); }

    private final Clock clock;
    private final Queue queue;
    private final Injector injector;
    private long generation, start, end, deadlineNanos, interval, nextDue;
    private long attempts, accepted, completed, cancelled, rejected, skipped, timedOut;
    private int target;
    private boolean running, inFlight;
    private String reason = "대기";
    private final Runnable tick = this::dispatchNext;
    private final Runnable deadline = () -> stop("시간 종료");
    private final Runnable watchdog = () -> { timedOut++; stop("입력 응답 시간 초과"); };

    public TapEngine(Clock clock, Queue queue, Injector injector) {
        this.clock = clock; this.queue = queue; this.injector = injector;
    }

    public void start(int cps, int seconds) {
        if (cps < 1 || cps > MAX_CPS || seconds < 1 || seconds > 3600)
            throw new IllegalArgumentException("속도 1~" + MAX_CPS + ", 시간 1~3600초");
        if (running) throw new IllegalStateException("이미 실행 중입니다");
        generation++;
        target = cps;
        interval = 1_000_000_000L / cps;
        start = clock.now(); nextDue = start;
        deadlineNanos = start + seconds * 1_000_000_000L;
        end = start;
        attempts = accepted = completed = cancelled = rejected = skipped = timedOut = 0;
        running = true; inFlight = false; reason = "실행 중";
        queue.post(deadline, seconds * 1000L);
        queue.post(tick, 0);
    }

    private void dispatchNext() {
        if (!running || inFlight) return;
        long now = clock.now();
        if (now >= deadlineNanos) { stop("시간 종료"); return; }
        if (now < nextDue) { queue.post(tick, ceilMillis(nextDue - now)); return; }
        // Missed ideal time slots are discarded; never burst to catch up.
        skipped += (now - nextDue) / interval;
        nextDue = now + interval;
        attempts++; inFlight = true;
        long token = generation;
        queue.post(watchdog, 2000);
        boolean sent;
        try {
            sent = injector.dispatch(success -> {
                if (!running || token != generation || !inFlight) return;
                queue.remove(watchdog); inFlight = false;
                if (!success) { cancelled++; stop("터치 취소됨"); return; }
                completed++;
                queue.post(tick, ceilMillis(Math.max(0, nextDue - clock.now())));
            });
        } catch (RuntimeException error) { sent = false; }
        if (sent) accepted++;
        else {
            rejected++; inFlight = false;
            queue.remove(watchdog); stop("Android 입력 요청 거절");
        }
    }

    public void stop(String message) {
        if (!running) return;
        end = clock.now(); running = false; generation++;
        reason = message;
        queue.remove(tick); queue.remove(deadline); queue.remove(watchdog);
        // An already dispatched gesture cannot be withdrawn by this API.
        // Its unresolved outcome is retained as pending, never counted as completed.
    }

    private static long ceilMillis(long nanos) { return (nanos + 999_999L) / 1_000_000L; }

    public Snapshot snapshot() {
        return new Snapshot(running, target, Math.max(0, (running ? clock.now() : end) - start),
            attempts, accepted, completed, cancelled, rejected, skipped, timedOut, reason);
    }

    public static final class Snapshot {
        public final boolean running;
        public final int target;
        public final long elapsedNanos, attempts, accepted, completed, cancelled, rejected, skipped, timedOut;
        public final String reason;
        Snapshot(boolean running, int target, long elapsedNanos, long attempts, long accepted,
                 long completed, long cancelled, long rejected, long skipped, long timedOut, String reason) {
            this.running = running; this.target = target; this.elapsedNanos = elapsedNanos;
            this.attempts = attempts; this.accepted = accepted; this.completed = completed;
            this.cancelled = cancelled; this.rejected = rejected; this.skipped = skipped;
            this.timedOut = timedOut; this.reason = reason;
        }
        public double seconds() { return elapsedNanos / 1_000_000_000.0; }
        public double completedCps() { return seconds() > 0 ? completed / seconds() : 0; }
        public long pending() { return Math.max(0, accepted - completed - cancelled - timedOut); }
    }
}
