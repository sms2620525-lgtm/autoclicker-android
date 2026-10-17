package dev.tapbench.autoclicker;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import java.util.Locale;

public final class TapService extends AccessibilityService {
    private static TapService current;
    public static TapService get() { return current; }
    private final Handler handler = new Handler(Looper.getMainLooper());
    private WindowManager windows;
    private LinearLayout panel;
    private View picker;
    private TextView status;
    private Button toggle;
    private WindowManager.LayoutParams panelParams;
    private TapEngine engine;
    private GestureDescription gesture;
    private float x, y;
    private boolean selected, armed, benchmark;
    private int armToken;
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            if (panel == null) return;
            TapEngine.Snapshot s = engine.snapshot();
            status.setText(armed ? "2초 뒤 시작 · 정지로 취소" : String.format(Locale.KOREA,
                "%s  |  %.1f 회/초\n좌표 %s", s.reason, s.completedCps(),
                selected ? Math.round(x) + ", " + Math.round(y) : "미선택"));
            toggle.setText(armed || s.running ? "■ 정지" : "▶ 시작");
            handler.postDelayed(this, 250);
        }
    };
    private final BroadcastReceiver screenOff = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { stop("화면 꺼짐"); }
    };

    @Override protected void onServiceConnected() {
        super.onServiceConnected();
        current = this;
        windows = (WindowManager) getSystemService(WINDOW_SERVICE);
        engine = new TapEngine(SystemClock::elapsedRealtimeNanos, new TapEngine.Queue() {
            public void post(Runnable task, long delay) { handler.postDelayed(task, delay); }
            public void remove(Runnable task) { handler.removeCallbacks(task); }
        }, result -> dispatchGesture(gesture, new GestureResultCallback() {
            @Override public void onCompleted(GestureDescription description) { result.complete(true); }
            @Override public void onCancelled(GestureDescription description) { result.complete(false); }
        }, handler));
        IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_OFF);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenOff, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(screenOff, filter);
    }

    public TapEngine.Snapshot snapshot() { return engine.snapshot(); }
    public boolean isArmed() { return armed; }
    public boolean isBenchmark() { return benchmark; }

    public void showControls() {
        if (panel != null) return;
        benchmark = false;
        panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(10), dp(6), dp(10), dp(6));
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(27, 37, 51)); background.setCornerRadius(dp(16));
        background.setStroke(dp(1), Color.rgb(93, 224, 192)); panel.setBackground(background);
        TextView handle = new TextView(this);
        handle.setText("⠿ TapBench · 드래그 이동"); handle.setTextColor(Color.WHITE);
        handle.setTextSize(14); handle.setPadding(dp(6), dp(8), dp(6), dp(8));
        panel.addView(handle);
        status = new TextView(this); status.setTextColor(Color.LTGRAY); status.setTextSize(12);
        panel.addView(status);
        LinearLayout buttons = new LinearLayout(this);
        Button position = button("◎ 위치", buttons);
        toggle = button("▶ 시작", buttons);
        Button close = button("닫기", buttons);
        panel.addView(buttons);
        panelParams = overlay(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT);
        panelParams.x = dp(8); panelParams.y = dp(60);
        try { windows.addView(panel, panelParams); }
        catch (RuntimeException error) { panel = null; toast("제어창을 열 수 없습니다. 접근성 설정을 확인하세요."); return; }
        position.setOnClickListener(v -> { stop("위치 선택"); choosePosition(); });
        toggle.setOnClickListener(v -> {
            if (armed || engine.snapshot().running) { stop("사용자가 정지"); return; }
            if (!selected) { toast("먼저 위치를 선택하세요"); return; }
            if (panelCoversTarget()) { toast("제어창을 클릭 위치 밖으로 옮기세요"); return; }
            int cps = getSharedPreferences("config", MODE_PRIVATE).getInt("cps", 5000);
            int seconds = getSharedPreferences("config", MODE_PRIVATE).getInt("seconds", 10);
            arm(x, y, cps, seconds, false);
        });
        close.setOnClickListener(v -> { stop("제어창 닫힘"); hideControls(); });
        handle.setOnTouchListener(new View.OnTouchListener() {
            float downX, downY; int initialX, initialY;
            @Override public boolean onTouch(View view, MotionEvent event) {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                    stop("제어창 이동"); downX = event.getRawX(); downY = event.getRawY();
                    initialX = panelParams.x; initialY = panelParams.y; return true;
                }
                if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
                    DisplayMetrics bounds = bounds();
                    panelParams.x = Math.max(0, Math.min(bounds.widthPixels - panel.getWidth(), initialX + (int)(event.getRawX() - downX)));
                    panelParams.y = Math.max(0, Math.min(bounds.heightPixels - panel.getHeight() - dp(36), initialY + (int)(event.getRawY() - downY)));
                    windows.updateViewLayout(panel, panelParams); return true;
                }
                if (event.getActionMasked() == MotionEvent.ACTION_UP) { view.performClick(); return true; }
                return true;
            }
        });
        handler.post(refresh);
    }

    private Button button(String label, LinearLayout parent) {
        Button b = new Button(this); b.setText(label); b.setTextSize(12);
        b.setMinWidth(0); b.setMinimumWidth(0); b.setPadding(dp(8), 0, dp(8), 0);
        parent.addView(b, new LinearLayout.LayoutParams(dp(76), dp(48))); return b;
    }

    private void choosePosition() {
        removePicker();
        TextView select = new TextView(this);
        select.setText("반복 클릭할 지점을 한 번 누르세요\n20초 후 자동 취소");
        select.setGravity(Gravity.CENTER); select.setTextSize(20); select.setTextColor(Color.WHITE);
        select.setBackgroundColor(0x55344660); picker = select;
        select.setOnTouchListener((v, event) -> {
            if (event.getActionMasked() == MotionEvent.ACTION_UP) {
                x = event.getRawX(); y = event.getRawY(); selected = true;
                v.performClick(); removePicker(); toast("클릭 좌표: " + Math.round(x) + ", " + Math.round(y));
            }
            return true;
        });
        windows.addView(select, overlay(-1, -1));
        handler.postDelayed(() -> { if (picker == select) removePicker(); }, 20_000);
    }

    public void arm(float px, float py, int cps, int seconds, boolean test) {
        stop("새 실행 준비"); removePicker();
        DisplayMetrics bounds = bounds();
        if (!Float.isFinite(px) || !Float.isFinite(py) || px < 0 || py < 0 || px >= bounds.widthPixels || py >= bounds.heightPixels)
            throw new IllegalArgumentException("화면 안의 좌표를 선택하세요");
        if (cps < 1 || cps > 5000 || seconds < 1 || seconds > 3600)
            throw new IllegalArgumentException("속도 1~5000, 시간 1~3600초");
        x = px; y = py; selected = true; benchmark = test;
        if (test) hideControls();
        Path path = new Path(); path.moveTo(x, y);
        gesture = new GestureDescription.Builder()
            .addStroke(new GestureDescription.StrokeDescription(path, 0, 1)).build();
        armed = true; int token = ++armToken;
        handler.postDelayed(() -> {
            if (!armed || token != armToken) return;
            armed = false;
            if (!test && panelCoversTarget()) { toast("제어창을 클릭 위치 밖으로 옮기세요"); return; }
            engine.start(cps, seconds);
        }, 2000);
    }

    public void stop(String message) { armed = false; armToken++; if (engine != null) engine.stop(message); }
    public void hideControls() {
        removePicker(); handler.removeCallbacks(refresh);
        if (panel != null) { windows.removeView(panel); panel = null; }
    }
    private void removePicker() { if (picker != null) { windows.removeView(picker); picker = null; } }
    private boolean panelCoversTarget() {
        if (panel == null) return false;
        int[] location = new int[2]; panel.getLocationOnScreen(location);
        return new Rect(location[0], location[1], location[0] + panel.getWidth(), location[1] + panel.getHeight()).contains((int)x, (int)y);
    }
    private WindowManager.LayoutParams overlay(int width, int height) {
        WindowManager.LayoutParams p = new WindowManager.LayoutParams(width, height,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        p.gravity = Gravity.TOP | Gravity.LEFT;
        if (Build.VERSION.SDK_INT >= 28) p.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        return p;
    }
    @SuppressWarnings("deprecation") private DisplayMetrics bounds() {
        DisplayMetrics m = new DisplayMetrics(); windows.getDefaultDisplay().getRealMetrics(m); return m;
    }
    private int dp(int n) { return Math.round(n * getResources().getDisplayMetrics().density); }
    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_SHORT).show(); }
    @Override public void onAccessibilityEvent(AccessibilityEvent event) { /* Screen content is never read. */ }
    @Override public void onInterrupt() { stop("접근성 서비스 중단"); }
    @Override public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c); stop("화면 설정 변경 · 위치를 다시 선택하세요"); selected = false;
        hideControls();
    }
    @Override public void onDestroy() {
        stop("서비스 종료"); hideControls(); handler.removeCallbacksAndMessages(null);
        try { unregisterReceiver(screenOff); } catch (IllegalArgumentException ignored) { }
        if (current == this) current = null;
        super.onDestroy();
    }
}
