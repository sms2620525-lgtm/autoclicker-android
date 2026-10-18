package dev.tapbench.autoclicker;

import org.junit.Test;
import java.util.PriorityQueue;
import static org.junit.Assert.*;

public final class TapEngineTest {
    static final class Task implements Comparable<Task> {
        long time, order; Runnable work;
        Task(long time, long order, Runnable work) { this.time = time; this.order = order; this.work = work; }
        public int compareTo(Task other) { int n = Long.compare(time, other.time); return n != 0 ? n : Long.compare(order, other.order); }
    }
    static final class Harness implements TapEngine.Clock, TapEngine.Queue, TapEngine.Injector {
        long time, order; int active, maxActive, delay = 10;
        boolean accept = true, answer = true, success = true;
        TapEngine.Result last;
        PriorityQueue<Task> tasks = new PriorityQueue<>();
        TapEngine engine = new TapEngine(this, this, this);
        public long now() { return time; }
        public void post(Runnable r, long ms) { tasks.add(new Task(time + ms * 1_000_000L, order++, r)); }
        public void remove(Runnable r) { tasks.removeIf(t -> t.work == r); }
        public boolean dispatch(TapEngine.Result result) {
            last = result;
            if (!accept) return false;
            active++; maxActive = Math.max(maxActive, active);
            if (answer) post(() -> { active--; result.complete(success); }, delay);
            return true;
        }
        void advance(long ms) {
            long until = time + ms * 1_000_000L;
            while (!tasks.isEmpty() && tasks.peek().time <= until) {
                Task t = tasks.remove(); time = t.time; t.work.run();
            }
            time = until;
        }
    }
    @Test public void highTargetNeverOverlapsOrFakesCompletedClicks() {
        Harness h = new Harness(); h.engine.start(90000, 1); h.advance(1000);
        TapEngine.Snapshot s = h.engine.snapshot();
        assertFalse(s.running); assertEquals(1, h.maxActive);
        assertEquals(100, s.attempts); assertEquals(99, s.completed);
        assertEquals(1, s.pending()); assertTrue(s.skipped > 80000);
        assertEquals(99.0, s.completedCps(), 0.001);
    }
    @Test public void lowRateRespectsPacing() {
        Harness h = new Harness(); h.delay = 2; h.engine.start(10, 1); h.advance(1100);
        assertEquals(10, h.engine.snapshot().attempts); assertEquals(10, h.engine.snapshot().completed);
    }
    @Test public void stoppedSessionDoesNotRestartFromLateCallback() {
        Harness h = new Harness(); h.engine.start(90000, 10); h.advance(0);
        h.engine.stop("stop"); h.advance(1000);
        assertEquals(1, h.engine.snapshot().attempts); assertEquals(0, h.engine.snapshot().completed);
        assertEquals(1, h.engine.snapshot().pending());
    }
    @Test public void cancellationStopsInsteadOfFightingTheUser() {
        Harness h = new Harness(); h.success = false;
        h.engine.start(90000, 10); h.advance(1000);
        assertEquals(1, h.engine.snapshot().cancelled); assertFalse(h.engine.snapshot().running);
        assertEquals(1, h.engine.snapshot().attempts);
    }
    @Test public void rejectedInputStopsWithoutRetryStorm() {
        Harness h = new Harness(); h.accept = false;
        h.engine.start(90000, 10); h.advance(3000);
        assertEquals(1, h.engine.snapshot().rejected); assertEquals(0, h.engine.snapshot().accepted);
        assertEquals(1, h.engine.snapshot().attempts); assertFalse(h.engine.snapshot().running);
    }
    @Test public void missingCallbackHasBoundedTimeout() {
        Harness h = new Harness(); h.answer = false;
        h.engine.start(90000, 10); h.advance(3000);
        assertEquals(1, h.engine.snapshot().timedOut); assertEquals(1, h.engine.snapshot().attempts);
        assertEquals(0, h.engine.snapshot().pending()); assertFalse(h.engine.snapshot().running);
    }
    @Test public void oldGenerationCannotChangeNewSession() {
        Harness h = new Harness(); h.answer = false;
        h.engine.start(90000, 10); h.advance(0); TapEngine.Result old = h.last;
        h.engine.stop("stop"); h.engine.start(1, 10); h.advance(0);
        old.complete(true);
        assertEquals(0, h.engine.snapshot().completed); assertEquals(1, h.engine.snapshot().attempts);
    }
    @Test public void stoppingBeforeFirstDispatchSendsNothing() {
        Harness h = new Harness(); h.engine.start(90000, 1); h.engine.stop("stop"); h.advance(2000);
        assertEquals(0, h.engine.snapshot().attempts);
    }
    @Test public void invalidInputsAreRejected() {
        Harness h = new Harness();
        for (int cps : new int[]{0, -1, 90001, Integer.MAX_VALUE}) {
            assertThrows(IllegalArgumentException.class, () -> h.engine.start(cps, 10));
        }
        assertThrows(IllegalArgumentException.class, () -> h.engine.start(90000, 0));
        assertThrows(IllegalArgumentException.class, () -> h.engine.start(90000, 3601));
    }
}
