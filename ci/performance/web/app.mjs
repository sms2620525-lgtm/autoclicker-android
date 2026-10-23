import { Benchmark, PointerGate } from './benchmark.mjs';

const $ = id => document.getElementById(id);
const engine = new Benchmark();
const pad = $('pad');
const points = [...document.querySelectorAll('[data-point]')];
const number = new Intl.NumberFormat('ko-KR');
const decimals = new Intl.NumberFormat('ko-KR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const storageKey = 'tapbench-received-history-v1';
const reasons = { completed: '완료', stopped: '수동 중지', hidden: '탭 숨김', resized: '창 크기 변경' };
const modeNames = { fast: '고속', steady: '기존 방식', unspecified: '미지정' };
let duration = 10;
let history = [];
let savedResult = null;
let previousState = '';
let chartKey = '';
let pointBounds = [];
const refreshBounds = () => { pointBounds = points.map(point => point.getBoundingClientRect()); };
let sessionSize = null;
let storageAvailable = true;

try {
  const stored = JSON.parse(localStorage.getItem(storageKey) || '[]');
  if (Array.isArray(stored)) history = stored.filter(r => ['tapbench-web-v1', 'tapbench-web-v2', 'tapbench-web-v3', 'tapbench-web-v4'].includes(r?.schema) && Number.isFinite(r.averageCPS) && Number.isInteger(r.receivedClicks) && Number.isFinite(r.measuredSeconds) && typeof r.createdAt === 'string').slice(0, 8);
} catch { storageAvailable = false; }

function saveHistory() {
  try { localStorage.setItem(storageKey, JSON.stringify(history)); }
  catch { storageAvailable = false; }
}

function renderHistory() {
  const body = $('history-body');
  body.replaceChildren();
  $('clear-history').hidden = history.length === 0;
  if (!history.length) {
    const row = body.insertRow();
    const cell = row.insertCell();
    cell.colSpan = 7;
    cell.className = 'empty-history';
    cell.textContent = '아직 측정 기록이 없습니다. 첫 번째 테스트를 시작해보세요.';
    return;
  }
  for (const result of history) {
    const row = body.insertRow();
    const date = new Date(result.createdAt);
    const when = Number.isNaN(date.valueOf()) ? '—' : new Intl.DateTimeFormat('ko-KR', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(date);
    const values = [when, reasons[result.reason] || '중단', modeNames[result.clickMode] || '미지정', `${decimals.format(result.measuredSeconds)}초`, number.format(result.receivedClicks), decimals.format(result.averageCPS), `${decimals.format(result.targetPercent)}%`];
    values.forEach((v, i) => { const td = row.insertCell(); td.textContent = v; if (i === 1) td.className = result.completed ? 'run-complete' : 'run-interrupted'; });
  }
}

function setDuration(value) {
  duration = value;
  document.querySelectorAll('[data-duration]').forEach(button => {
    const active = Number(button.dataset.duration) === value;
    button.classList.toggle('selected', active);
    button.setAttribute('aria-pressed', String(active));
  });
  if (engine.state === 'idle') $('remaining').textContent = duration.toFixed(1);
}

function commitResult() {
  if (!engine.result || savedResult === engine.result) return;
  savedResult = engine.result;
  history.unshift(savedResult);
  history = history.slice(0, 8);
  saveHistory();
  renderHistory();
  const result = savedResult;
  const perTarget = result.receivedByTarget.map(p => `${p.target}번 ${number.format(p.receivedClicks)}회`).join(' / ');
  $('run-status').textContent = `${modeNames[result.clickMode]} · ${reasons[result.reason] || '중단'} · ${decimals.format(result.measuredSeconds)}초 · ${perTarget} · 합계 평균 ${decimals.format(result.averageCPS)} CPS${!result.completed ? ' · 중단된 측정입니다.' : ''}${!storageAvailable ? ' · 브라우저 저장이 제한되어 현재 화면에서만 유지됩니다.' : ''}`;
}

function drawChart(s) {
  const values = s.perSecond;
  const key = values.join(',') + ':' + Math.floor(s.elapsed);
  if (key === chartKey) return;
  chartKey = key;
  const ceiling = Math.max(10, Math.ceil(Math.max(0, ...values) / 10) * 10);
  const ns = 'http://www.w3.org/2000/svg';
  const bars = document.createDocumentFragment();
  const labels = document.createDocumentFragment();
  const step = 658 / Math.max(1, values.length);
  values.forEach((value, i) => {
    if (!value) return;
    const rect = document.createElementNS(ns, 'rect');
    const height = value / ceiling * 120;
    rect.setAttribute('x', String(32 + i * step + step * 0.13));
    rect.setAttribute('y', String(140 - height));
    rect.setAttribute('width', String(step * 0.74));
    rect.setAttribute('height', String(height));
    rect.setAttribute('rx', '2');
    rect.setAttribute('fill', '#a6f4c9');
    rect.setAttribute('opacity', s.elapsed < i + 1 ? '0.45' : '0.9');
    const title = document.createElementNS(ns, 'title');
    title.textContent = `${i}–${i + 1}초: ${number.format(value)}회${s.elapsed < i + 1 ? ' (부분 구간)' : ''}`;
    rect.append(title); bars.append(rect);
  });
  [0, 1, 2, 3].forEach(i => {
    const label = document.createElementNS(ns, 'text');
    label.setAttribute('x', '25'); label.setAttribute('y', String(144 - i * 40));
    label.setAttribute('text-anchor', 'end'); label.setAttribute('font-size', '8'); label.setAttribute('fill', '#93a2a5');
    label.textContent = number.format(Math.round(ceiling * i / 3)); labels.append(label);
  });
  $('chart-bars').replaceChildren(bars);
  $('chart-labels').replaceChildren(labels);
  $('chart').setAttribute('aria-label', `초별 수신 클릭 수: ${values.map((v, i) => `${i + 1}번째 구간 ${v}회`).join(', ')}`);
  $('chart-duration').textContent = `${engine.duration || duration}초`;
  $('chart-caption').textContent = s.total ? '실측값에 맞춰 축 조정' : '측정하면 그래프가 표시됩니다';
}

function render() {
  const now = performance.now();
  engine.advance(now);
  const state = engine.state;
  const s = engine.snapshot(now);
  const active = state === 'armed' || state === 'running';
  if (state !== previousState) {
    previousState = state;
    document.body.className = `state-${state}`;
    $('settings-fields').disabled = active;
    $('arm').disabled = active;
    $('stop').disabled = !active;
    $('export-csv').disabled = !engine.result;
    $('export-json').disabled = !engine.result;
    $('arm').innerHTML = (state === 'completed' || state === 'interrupted') ? '다시 측정 <span>↻</span>' : '측정 준비 <span>→</span>';
    const texts = {
      idle: ['대기 중', '세 지점의 속도를 확인하세요', '‘측정 준비’를 누르면 세 영역이 활성화됩니다.'],
      armed: ['첫 클릭 대기', '1번·2번·3번 위치를 지정하세요', '1번 ⌃⌥S · 2번 ⌃⌥D · 3번 ⌃⌥F · 시작 ⌃⌥Space'],
      running: ['측정 중', '', '1번 → 2번 → 3번 교대 클릭 · 앱 중지는 ⌃⌥Space'],
      completed: ['측정 완료', '측정이 끝났어요', '앱이 계속 클릭 중이라면 ⌃⌥Space로 중지하세요.'],
      interrupted: ['측정 중단', '측정을 중단했어요', '앱이 계속 클릭 중이라면 ⌃⌥Space로 중지하세요.'],
    };
    const [badge, title, hint] = texts[state];
    $('badge-text').textContent = badge;
    $('pad-title').textContent = title;
    $('pad-hint').textContent = hint;
    if (engine.result) commitResult();
  }
  if (state === 'running') $('pad-title').textContent = `${number.format(s.total)} clicks`;
  $('average').textContent = decimals.format(s.average);
  $('total').textContent = number.format(s.total);
  points.forEach((_, i) => {
    $('point-count-' + i).textContent = number.format(s.points[i]?.receivedClicks ?? 0);
    $('point-rate-' + i).textContent = `${decimals.format(s.points[i]?.averageCPS ?? 0)} CPS`;
  });
  $('current').textContent = s.current === null ? '—' : number.format(s.current);
  $('peak').textContent = s.peak === null ? '—' : `${number.format(s.peak)} CPS`;
  $('percent').textContent = decimals.format(s.percent);
  $('remaining').textContent = (engine.bins ? s.remaining : duration).toFixed(1);
  $('goal').textContent = `${number.format(engine.target || Number($('target').value) || 40000)} CPS`;
  const progress = engine.duration ? Math.min(100, s.elapsed / engine.duration * 100) : 0;
  $('progress-fill').style.width = `${progress}%`;
  $('progress').setAttribute('aria-valuenow', String(Math.round(progress)));
  $('goal-fill').style.width = `${Math.max(0, Math.min(100, s.percent))}%`;
  $('timing-text').textContent = state === 'running' ? '측정 진행 중' : state === 'completed' ? '측정 완료' : state === 'interrupted' ? '측정 중단' : '첫 클릭 대기';
  drawChart(s);
}

const gate = new PointerGate((now, type, targetIndex) => engine.record(now, type, targetIndex), () => {
  if (engine.state === 'armed' || engine.state === 'running') engine.synthetic += 1;
});

points.forEach((point, index) => point.addEventListener('pointerdown', e => {
  if (engine.state !== 'armed' && engine.state !== 'running') return;
  if (e.isTrusted) e.preventDefault();
  gate.down(e, index);
}));
window.addEventListener('pointerup', e => {
  if (engine.state !== 'armed' && engine.state !== 'running') return;
  let index = -1;
  for (let i = 0; i < pointBounds.length; i++) {
    const b = pointBounds[i];
    if (e.clientX >= b.left && e.clientX <= b.right && e.clientY >= b.top && e.clientY <= b.bottom) { index = i; break; }
  }
  gate.up(e, performance.now(), index >= 0, index);
});
window.addEventListener('pointercancel', e => gate.cancel(e));
pad.addEventListener('contextmenu', e => e.preventDefault());
pad.addEventListener('dragstart', e => e.preventDefault());

document.querySelectorAll('[data-duration]').forEach(b => b.addEventListener('click', () => setDuration(Number(b.dataset.duration))));
$('arm').addEventListener('click', () => {
  $('error').textContent = '';
  if (!window.PointerEvent) { $('error').textContent = '최신 Safari 또는 Chrome에서 열어주세요.'; return; }
  try {
    const target = Number($('target').value);
    engine.arm({ duration, target, targetCount: points.length, mode: $('click-mode').value });
    gate.reset(); savedResult = null; chartKey = '';
    $('run-status').textContent = '1번 영역에서 ⌃⌥S, 2번 영역에서 ⌃⌥D, 3번 영역에서 ⌃⌥F로 위치를 지정한 뒤 ⌃⌥Space로 시작하세요. 세 영역은 첫 클릭부터 같은 시간 동안 측정됩니다.';
    render();
    // Capture after state changes; font loading and scrolling refresh bounds separately.
    refreshBounds();
    sessionSize = { width: window.innerWidth, height: window.innerHeight };
  } catch (error) { $('error').textContent = '목표 속도에 1–40,000 사이 정수를 입력하세요.'; }
});
function stop(reason) {
  if (engine.state !== 'armed' && engine.state !== 'running') return;
  const wasArmed = engine.state === 'armed';
  engine.finish(performance.now(), reason);
  gate.reset(); render();
  if (wasArmed) $('run-status').textContent = '측정 준비를 취소했습니다. 클릭 기록은 생성되지 않았습니다.';
}
$('stop').addEventListener('click', () => stop('stopped'));
window.addEventListener('keydown', e => { if (e.key === 'Escape') stop('stopped'); });
document.addEventListener('visibilitychange', () => { if (document.hidden) stop('hidden'); });
window.addEventListener('resize', () => {
  if (sessionSize && (window.innerWidth !== sessionSize.width || Math.abs(window.innerHeight - sessionSize.height) > 40)) stop('resized');
  refreshBounds();
});
window.addEventListener('scroll', refreshBounds, { passive: true });
document.fonts?.ready.then(refreshBounds);
$('clear-history').addEventListener('click', () => { history = []; saveHistory(); renderHistory(); });

function exportResult(kind) {
  const result = engine.result;
  if (!result) return;
  let data;
  if (kind === 'json') data = JSON.stringify(result, null, 2);
  else {
    const rows = [
      ['metric', 'value'], ['created_at', result.createdAt], ['status', result.reason],
      ['click_mode', result.clickMode], ['mode_source', result.modeSource],
      ['target_cps', result.targetCPS], ['measured_seconds', result.measuredSeconds],
      ['received_clicks', result.receivedClicks], ['average_cps', result.averageCPS],
      ...result.receivedByTarget.flatMap(p => [[`target_${p.target}_clicks`, p.receivedClicks], [`target_${p.target}_average_cps`, p.averageCPS]]),
      ['peak_full_second_cps', result.peakFullSecondCPS ?? ''], [],
      ['interval_start_seconds', 'interval_duration_seconds', 'received_clicks', 'full_second'],
    ];
    result.clicksPerSecond.forEach((count, i) => {
      const seconds = Math.min(1, Math.max(0, result.measuredSeconds - i));
      if (seconds > 0) rows.push([i, seconds, count, seconds === 1]);
    });
    data = '\uFEFF' + rows.map(row => row.map(v => '"' + String(v).replaceAll('"', '""') + '"').join(',')).join('\r\n');
  }
  const url = URL.createObjectURL(new Blob([data], { type: kind === 'json' ? 'application/json' : 'text/csv;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url; a.download = `TapBench-${result.createdAt.replaceAll(':', '-')}.${kind}`;
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
$('export-csv').addEventListener('click', () => exportResult('csv'));
$('export-json').addEventListener('click', () => exportResult('json'));
renderHistory(); render();
// Input handlers only count. Rendering runs at 10 Hz and never generates a click.
setInterval(render, 100);
