export class Benchmark {
  constructor() { this.state = 'idle'; this.total = 0; this.result = null; }
  arm({ duration, target, targetCount = 1, mode = 'unspecified' }) {
    if (![5, 10, 30, 60].includes(duration) || !Number.isInteger(target) || target < 1 || target > 20000 || ![1, 2].includes(targetCount) || !['fast', 'steady', 'unspecified'].includes(mode)) throw new Error('설정을 확인하세요.');
    this.mode = mode;
    this.duration = duration;
    this.target = target;
    this.state = 'armed';
    this.total = 0;
    this.targetTotals = Array(targetCount).fill(0);
    this.started = null;
    this.ended = null;
    this.result = null;
    this.bins = new Uint32Array(duration * 10);
    this.types = { mouse: 0, touch: 0, pen: 0, other: 0 };
    this.synthetic = 0;
  }
  record(now, pointerType = 'other', targetIndex = 0) {
    if (!Number.isFinite(now) || !Number.isInteger(targetIndex) || targetIndex < 0 || targetIndex >= (this.targetTotals?.length ?? 0)) return false;
    if (this.state === 'armed') { this.state = 'running'; this.started = now; }
    if (this.state !== 'running' || now < this.started) return false;
    if (now >= this.started + this.duration * 1000) { this.finish(this.started + this.duration * 1000, 'completed'); return false; }
    const bucket = Math.floor((now - this.started) / 100);
    this.bins[bucket] += 1;
    this.total += 1;
    this.targetTotals[targetIndex] += 1;
    this.types[Object.hasOwn(this.types, pointerType) ? pointerType : 'other'] += 1;
    return true;
  }
  advance(now) {
    if (this.state === 'running' && now >= this.started + this.duration * 1000) this.finish(this.started + this.duration * 1000, 'completed');
  }
  snapshot(now) {
    if (!this.bins) return { state: this.state, total: 0, elapsed: 0, average: 0, current: null, peak: null, perSecond: [], percent: 0, remaining: 10, points: [] };
    const end = this.ended ?? Math.min(now, (this.started ?? now) + this.duration * 1000);
    const elapsed = this.started === null ? 0 : Math.max(0, (end - this.started) / 1000);
    const perSecond = Array.from({ length: this.duration }, (_, sec) => {
      let count = 0;
      for (let i = sec * 10; i < sec * 10 + 10; i++) count += this.bins[i];
      return count;
    });
    // Latest ten fully elapsed 100 ms buckets: bounded work and a true one-second denominator.
    let current = null;
    const completedBins = Math.min(this.bins.length, Math.floor(elapsed * 10 + 1e-8));
    if (completedBins >= 10) {
      current = 0;
      for (let i = completedBins - 10; i < completedBins; i++) current += this.bins[i];
    }
    const completeSeconds = Math.min(this.duration, Math.floor(elapsed + 1e-8));
    const peak = completeSeconds ? Math.max(...perSecond.slice(0, completeSeconds)) : null;
    const average = elapsed > 0 ? this.total / elapsed : 0;
    const points = this.targetTotals.map((receivedClicks, index) => ({ target: index + 1, receivedClicks, averageCPS: elapsed > 0 ? receivedClicks / elapsed : 0 }));
    return { state: this.state, total: this.total, elapsed, average, current, peak, perSecond,
      percent: average / this.target * 100, remaining: Math.max(0, this.duration - elapsed), points };
  }
  finish(now, reason) {
    if (this.state === 'armed') { this.state = 'idle'; return null; }
    if (this.state !== 'running') return this.result;
    this.ended = Math.max(this.started, Math.min(now, this.started + this.duration * 1000));
    this.state = reason === 'completed' ? 'completed' : 'interrupted';
    const s = this.snapshot(this.ended);
    this.result = {
      schema: 'tapbench-web-v3', createdAt: new Date().toISOString(), reason,
      clickMode: this.mode, modeSource: 'User-selected label; not detected from the native app.',
      completed: reason === 'completed', targetCPS: this.target, requestedSeconds: this.duration,
      measuredSeconds: s.elapsed, receivedClicks: s.total, averageCPS: s.average,
      receivedByTarget: s.points,
      peakFullSecondCPS: s.peak, targetPercent: s.percent, countsPer100ms: Array.from(this.bins),
      clicksPerSecond: s.perSecond, pointerTypes: { ...this.types }, ignoredSyntheticEvents: this.synthetic,
      method: 'Trusted primary pointer down/up pairs received within the target. Monotonic handler-time window starts on first completed click. No generated clicks. Partial last second is a count, not an extrapolated CPS.',
    };
    return this.result;
  }
}

// Accept exactly one completed primary left-button pair. Compatibility click/touch events
// are not subscribed to, so a physical click cannot be counted twice.
export class PointerGate {
  constructor(onClick, onSynthetic = () => {}) {
    this.onClick = onClick; this.onSynthetic = onSynthetic;
    this.pending = { active: false, id: 0, type: 'other', targetIndex: 0 };
  }
  reset() { this.pending.active = false; }
  down(e, targetIndex = 0) {
    if (!e.isTrusted) { this.onSynthetic(); return; }
    if (e.button !== 0 || e.isPrimary === false) return;
    const p = this.pending;
    p.active = true; p.id = e.pointerId; p.type = e.pointerType; p.targetIndex = targetIndex;
  }
  up(e, now, inside = true, targetIndex = 0) {
    if (!e.isTrusted) { this.onSynthetic(); return false; }
    const p = this.pending;
    if (!p.active || p.id !== e.pointerId) return false;
    p.active = false;
    if (!inside || targetIndex !== p.targetIndex || e.button !== 0 || e.isPrimary === false) return false;
    return this.onClick(now, p.type, p.targetIndex);
  }
  cancel(e) { if (this.pending.id === e.pointerId) this.reset(); }
}
