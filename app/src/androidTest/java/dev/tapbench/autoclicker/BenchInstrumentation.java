package dev.tapbench.autoclicker;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.SystemClock;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;

/** Real AccessibilityService -> Android input -> Activity touch path; no synthetic counters. */
public final class BenchInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle args) { super.onCreate(args); start(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            MainActivity activity = (MainActivity) startActivitySync(new Intent(getTargetContext(), MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            waitForIdleSync();
            new File(getTargetContext().getFilesDir(), "instrumentation-ready").createNewFile();
            awaitService();
            // Exercise stop while a real run is active.
            runOnMainSync(() -> activity.startBenchmark(10, 10));
            awaitRunning(); SystemClock.sleep(500);
            runOnMainSync(() -> TapService.get().stop("instrumentation stop"));
            long count = state().attempts; SystemClock.sleep(300);
            check(state().attempts == count, "Dispatch continued after stop");
            // Measure the requested 90000 CPS setting for five seconds, without asserting fake throughput.
            runOnMainSync(() -> activity.startBenchmark(90000, 5));
            awaitRunning();
            long deadline = SystemClock.uptimeMillis() + 10_000;
            while (state().running && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(50);
            TapEngine.Snapshot s = state();
            check(!s.running, "Benchmark failed to stop");
            check(s.completed > 0 && s.rejected == 0 && s.timedOut == 0, "No successful gesture path");
            AtomicReference<String> report = new AtomicReference<>();
            AtomicReference<Exception> error = new AtomicReference<>();
            runOnMainSync(() -> {
                try {
                    check(activity.receivedTouches() > 0, "No actual touches reached the test pad");
                    check(TapService.get().pointCount() == TapService.MAX_POINTS, "Benchmark did not arm three points");
                    report.set(activity.reportJson());
                } catch (Exception e) { error.set(e); }
            });
            if (error.get() != null) throw error.get();
            File file = new File(getTargetContext().getFilesDir(), "benchmark.json");
            try (FileOutputStream out = new FileOutputStream(file)) { out.write(report.get().getBytes(StandardCharsets.UTF_8)); }
            Bitmap screenshot = getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES).takeScreenshot();
            if (screenshot != null) {
                try (FileOutputStream out = new FileOutputStream(new File(getTargetContext().getFilesDir(), "benchmark-screen.png"))) {
                    screenshot.compress(Bitmap.CompressFormat.PNG, 100, out);
                }
                screenshot.recycle();
            }
            result.putString("stream", "\nTAPBENCH_DEVICE_TEST_PASSED\n" + report.get() + "\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            result.putString("stream", "\nTAPBENCH_DEVICE_TEST_FAILED: " + error + "\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }
    private void awaitService() throws Exception {
        long deadline = SystemClock.uptimeMillis() + 30_000;
        while (SystemClock.uptimeMillis() < deadline) {
            AtomicReference<Boolean> ready = new AtomicReference<>(false);
            runOnMainSync(() -> ready.set(TapService.get() != null));
            if (ready.get()) return;
            SystemClock.sleep(100);
        }
        throw new Exception("Accessibility service not enabled by the emulator setup");
    }
    private void awaitRunning() throws Exception {
        long deadline = SystemClock.uptimeMillis() + 5000;
        while (SystemClock.uptimeMillis() < deadline) {
            if (state().running) return;
            SystemClock.sleep(50);
        }
        throw new Exception("Run did not start");
    }
    private TapEngine.Snapshot state() {
        AtomicReference<TapEngine.Snapshot> result = new AtomicReference<>();
        runOnMainSync(() -> result.set(TapService.get().snapshot())); return result.get();
    }
    private static void check(boolean value, String message) throws Exception {
        if (!value) throw new Exception(message);
    }
}
