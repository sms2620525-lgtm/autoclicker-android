package dev.tapbench.autoclicker;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import org.json.JSONObject;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int BG = Color.rgb(16, 21, 30), CARD = Color.rgb(26, 35, 48);
    private static final int MINT = Color.rgb(93, 224, 192), MUTED = Color.rgb(169, 184, 201);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private LinearLayout content;
    private ScrollView scroll;
    private EditText cpsInput, secondsInput;
    private TextView connection, stats, pad;
    private long received;
    private int benchmarkToken;
    private boolean resumed;
    private String exportJson;
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            renderStats(); handler.postDelayed(this, 250);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        scroll = new ScrollView(this); scroll.setFillViewport(true); scroll.setBackgroundColor(BG);
        content = new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(22), dp(18), dp(22), dp(24)); scroll.addView(content);
        if (Build.VERSION.SDK_INT >= 30) getWindow().setDecorFitsSystemWindows(false);
        scroll.setOnApplyWindowInsetsListener((v, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            } else v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        setContentView(scroll);
        label(content, "TAPBENCH  /  ANDROID", 12, MINT, true);
        label(content, "같은 곳을, 반복해서.", 29, Color.WHITE, true);
        label(content, "지점 3곳 · 목표는 90,000회/초. 실제 속도는 기기에서 측정합니다.", 14, MUTED, false);

        LinearLayout permissions = card();
        connection = label(permissions, "접근성 연결 확인 중", 16, Color.WHITE, true);
        label(permissions, "선택한 좌표에 터치를 보내는 데 접근성 권한을 사용합니다. 화면 내용·키 입력은 읽지 않으며 네트워크 권한도 없습니다.", 13, MUTED, false);
        button(permissions, "접근성 설정 열기", () -> new AlertDialog.Builder(this)
            .setTitle("TapBench 접근성 사용")
            .setMessage("설정에서 TapBench 오토클릭커를 켜세요. 이 서비스는 직접 선택한 지점에 터치를 보냅니다. 정지 버튼 또는 화면 끄기로 멈출 수 있습니다.")
            .setPositiveButton("설정으로", (d, w) -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)))
            .setNegativeButton("취소", null).show());

        LinearLayout setup = card();
        label(setup, "01  클릭 설정", 17, Color.WHITE, true);
        cpsInput = number(setup, "목표 속도 (제스처/초 · 1~90,000)", "cps", TapEngine.MAX_CPS);
        secondsInput = number(setup, "실행 시간 (초 · 1~3,600)", "seconds", 10);
        label(setup, "지점 3곳을 선택하면 한 번의 제스처가 세 곳을 동시에 누릅니다. 따라서 실제 탭 수는 완료 제스처 수의 3배입니다.", 13, MUTED, false);
        label(setup, "Android는 터치 처리 시간을 제한합니다. 90,000 설정은 목표값일 뿐이며 실제 90,000번의 터치를 보장하지 않습니다. 완료 응답을 기다려 겹치는 입력과 무한 대기를 막으므로, 실제 속도는 기기의 입력 처리 속도에서 멈춥니다.", 13, MUTED, false);
        button(setup, "설정 저장 · 떠 있는 제어창 열기", () -> {
            if (!saveConfig()) return;
            TapService s = requireService(); if (s == null) return;
            s.stop("제어창 열기"); s.showControls();
            toast("대상 앱으로 이동 → 위치 → 클릭 지점 선택 → 시작");
        });
        label(setup, "제어창에서 위치를 누르고 지점 3곳을 차례로 선택하세요. 시작 후 2초 뒤 반복 터치합니다. 제어창 상단을 드래그해 옮길 수 있습니다.", 13, MUTED, false);

        LinearLayout bench = card();
        label(bench, "02  실제 터치 성능 테스트", 17, Color.WHITE, true);
        label(bench, "아래 패드에 실제로 도착한 손가락별 터치 종료(ACTION_UP · ACTION_POINTER_UP)를 셉니다. 테스트 중 화면을 직접 만지면 수신 수에 포함됩니다.", 13, MUTED, false);
        label(bench, "테스트는 패드 안의 3개 지점을 동시에 누릅니다. 완료 제스처 1회 = 탭 3회입니다.", 13, MUTED, false);
        button(bench, "설정한 속도로 10초 테스트", () -> {
            if (!saveConfig()) return;
            startBenchmark(Integer.parseInt(cpsInput.getText().toString()), 10);
        });
        button(bench, "■ 즉시 정지", () -> {
            benchmarkToken++;
            TapService s = TapService.get(); if (s != null) s.stop("사용자가 정지");
            getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            renderStats();
        });
        stats = label(bench, "테스트 결과가 여기에 표시됩니다", 14, Color.WHITE, false);
        stats.setTypeface(Typeface.MONOSPACE);
        pad = new TextView(this); pad.setGravity(Gravity.CENTER); pad.setTextSize(20); pad.setTextColor(MINT);
        pad.setTypeface(Typeface.DEFAULT, Typeface.BOLD); pad.setText("◎\n터치 측정 패드\n0회 수신");
        GradientDrawable padBackground = new GradientDrawable(); padBackground.setColor(0xFF122E30);
        padBackground.setCornerRadius(dp(20)); padBackground.setStroke(dp(2), MINT); pad.setBackground(padBackground);
        pad.setContentDescription("실제 터치 측정 패드");
        bench.addView(pad, new LinearLayout.LayoutParams(-1, dp(180)));
        pad.setOnTouchListener((v, event) -> {
            int action = event.getActionMasked();
            // Three simultaneous strokes arrive as three fingers: one ACTION_UP plus ACTION_POINTER_UP for the rest.
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_POINTER_UP) {
                TapService s = TapService.get();
                if (s != null && s.isBenchmark() && s.snapshot().running) received++;
                if (action == MotionEvent.ACTION_UP) v.performClick();
            }
            return true;
        });
        button(bench, "결과 JSON 저장", this::export);
        label(content, "완료 CPS = Android 완료 응답/초 (지점 3곳이면 탭은 그 3배)\n수신 CPS = 측정 패드에 도착한 터치/초\n다른 앱의 내부 클릭 처리 여부는 확인할 수 없습니다.", 12, MUTED, false);
    }

    public void startBenchmark(int cps, int seconds) {
        TapService s = requireService(); if (s == null) return;
        s.stop("테스트 준비"); s.hideControls();
        received = 0; int token = ++benchmarkToken;
        scroll.fullScroll(View.FOCUS_DOWN);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        handler.postDelayed(() -> {
            if (!resumed || token != benchmarkToken) return;
            int[] location = new int[2]; pad.getLocationOnScreen(location);
            // Three points spread across the pad, so every stroke lands inside the measured area.
            float centerX = location[0] + pad.getWidth() / 2f, centerY = location[1] + pad.getHeight() / 2f;
            float gap = pad.getWidth() / 4f;
            s.arm(new float[]{centerX - gap, centerX, centerX + gap},
                new float[]{centerY, centerY, centerY}, TapService.MAX_POINTS, cps, seconds, true);
            renderStats();
        }, 150);
    }

    public long receivedTouches() { return received; }

    public String reportJson() throws Exception {
        TapService service = TapService.get();
        if (service == null) throw new IllegalStateException("서비스가 연결되지 않았습니다");
        TapEngine.Snapshot s = service.snapshot();
        int points = service.pointCount();
        JSONObject data = new JSONObject();
        data.put("schema_version", 2).put("device", Build.MANUFACTURER + " " + Build.MODEL)
            .put("android_api", Build.VERSION.SDK_INT).put("target_cps", s.target)
            .put("points_per_gesture", points).put("target_taps_per_second", (long) s.target * points)
            .put("elapsed_seconds", s.seconds()).put("dispatch_attempts", s.attempts)
            .put("accepted", s.accepted).put("completed_gestures", s.completed)
            .put("completed_taps", s.completed * points)
            .put("completed_taps_per_second", s.completedCps() * points)
            .put("cancelled", s.cancelled).put("rejected", s.rejected).put("timed_out", s.timedOut)
            .put("pending_at_stop", s.pending()).put("skipped_target_slots", s.skipped)
            .put("completed_cps", s.completedCps()).put("stop_reason", s.reason)
            .put("running", s.running).put("measurement", service.isBenchmark() ? "real_touch_pad" : "gesture_callbacks_only")
            .put("received_touches", service.isBenchmark() ? received : JSONObject.NULL)
            .put("received_cps", service.isBenchmark() && s.seconds() > 0 ? received / s.seconds() : JSONObject.NULL)
            .put("note", "Target CPS counts gestures; each gesture presses points_per_gesture points at once. Target CPS is a request, not a guarantee. Completion is not proof that another app handled a click. Manual touches on the pad also count.");
        return data.toString(2);
    }

    private void renderStats() {
        TapService service = TapService.get();
        connection.setText(service == null ? "● 접근성 연결 필요" : "● 접근성 연결됨");
        connection.setTextColor(service == null ? Color.rgb(255, 193, 112) : MINT);
        if (service == null) return;
        TapEngine.Snapshot s = service.snapshot();
        int points = service.pointCount();
        stats.setText(String.format(Locale.KOREA,
            "%s\n목표 %,d 제스처/초 · 지점 %d곳 · %.1f초\n완료 제스처 %,d회 · %.1f/초\n실제 탭 %,d회 · %.1f/초\n수신 %s\n취소 %,d · 거절 %,d · 시간초과 %,d\n건너뛴 목표 슬롯 %,d · 미확인 %,d",
            service.isArmed() ? "2초 뒤 시작합니다" : s.reason, s.target, points, s.seconds(),
            s.completed, s.completedCps(), s.completed * points, s.completedCps() * points,
            service.isBenchmark() ? String.format(Locale.KOREA, "%,d회 · %.1f CPS", received, s.seconds() > 0 ? received / s.seconds() : 0) : "테스트 화면에서만 측정",
            s.cancelled, s.rejected, s.timedOut, s.skipped, s.pending()));
        pad.setText(String.format(Locale.KOREA, "◎\n터치 측정 패드\n%,d회 수신", received));
        if (!s.running && !service.isArmed()) getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    private boolean saveConfig() {
        try {
            int cps = Integer.parseInt(cpsInput.getText().toString().trim());
            int seconds = Integer.parseInt(secondsInput.getText().toString().trim());
            if (cps < 1 || cps > TapEngine.MAX_CPS || seconds < 1 || seconds > 3600) throw new NumberFormatException();
            getSharedPreferences("config", MODE_PRIVATE).edit().putInt("cps", cps).putInt("seconds", seconds).apply();
            return true;
        } catch (NumberFormatException error) { toast("속도는 1~" + TapEngine.MAX_CPS + ", 시간은 1~3600의 정수로 입력하세요"); return false; }
    }
    private TapService requireService() {
        TapService s = TapService.get(); if (s == null) toast("접근성 설정에서 TapBench를 먼저 켜세요"); return s;
    }
    private void export() {
        TapService s = requireService(); if (s == null) return;
        if (s.isArmed() || s.snapshot().running) { toast("측정이 끝난 후 저장하세요"); return; }
        if (s.snapshot().attempts == 0) { toast("먼저 테스트를 실행하세요"); return; }
        try { exportJson = reportJson(); } catch (Exception e) { toast("결과 생성 실패"); return; }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/json")
            .addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE, "tapbench-result.json");
        startActivityForResult(intent, 7);
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == 7 && result == RESULT_OK && data != null && data.getData() != null && exportJson != null) {
            try (OutputStream out = getContentResolver().openOutputStream(data.getData())) {
                if (out == null) throw new IllegalStateException("저장 위치 없음");
                out.write(exportJson.getBytes(StandardCharsets.UTF_8)); toast("결과를 저장했습니다");
            } catch (Exception e) { toast("저장하지 못했습니다: " + e.getMessage()); }
        }
    }
    @Override protected void onResume() { super.onResume(); resumed = true; handler.post(refresh); }
    @Override protected void onPause() {
        resumed = false; benchmarkToken++; handler.removeCallbacks(refresh);
        TapService s = TapService.get(); if (s != null && s.isBenchmark()) s.stop("테스트 화면을 벗어남");
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); super.onPause();
    }
    @Override protected void onDestroy() { handler.removeCallbacksAndMessages(null); super.onDestroy(); }
    private int dp(int n) { return Math.round(n * getResources().getDisplayMetrics().density); }
    private void toast(String text) { Toast.makeText(this, text, Toast.LENGTH_LONG).show(); }
    private LinearLayout card() {
        LinearLayout box = new LinearLayout(this); box.setOrientation(LinearLayout.VERTICAL); box.setPadding(dp(16), dp(14), dp(16), dp(16));
        GradientDrawable bg = new GradientDrawable(); bg.setColor(CARD); bg.setCornerRadius(dp(22)); box.setBackground(bg);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2); p.topMargin = dp(18); content.addView(box, p); return box;
    }
    private TextView label(LinearLayout parent, String text, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(text); t.setTextSize(size); t.setTextColor(color);
        t.setPadding(0, dp(5), 0, dp(9)); if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        parent.addView(t); return t;
    }
    private void button(LinearLayout parent, String title, Runnable action) {
        Button b = new Button(this); b.setText(title); b.setTextSize(14); b.setAllCaps(false); b.setMinHeight(dp(48));
        b.setOnClickListener(v -> action.run()); parent.addView(b, new LinearLayout.LayoutParams(-1, -2));
    }
    private EditText number(LinearLayout parent, String title, String key, int fallback) {
        TextView label = label(parent, title, 13, MUTED, false);
        EditText edit = new EditText(this); edit.setId(View.generateViewId()); label.setLabelFor(edit.getId());
        edit.setContentDescription(title); edit.setSingleLine(); edit.setTextSize(23); edit.setTextColor(MINT);
        edit.setInputType(InputType.TYPE_CLASS_NUMBER);
        edit.setText(String.valueOf(getSharedPreferences("config", MODE_PRIVATE).getInt(key, fallback)));
        parent.addView(edit, new LinearLayout.LayoutParams(-1, dp(52))); return edit;
    }
}
