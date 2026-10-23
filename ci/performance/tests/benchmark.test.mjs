import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Benchmark, PointerGate } from '../web/benchmark.mjs';

function make(duration = 10) { const b = new Benchmark(); b.arm({ duration, target: 5000 }); return b; }
const event = (extra = {}) => ({ isTrusted: true, button: 0, isPrimary: true, pointerId: 1, pointerType: 'mouse', ...extra });

test('first click starts time; idle timers do not produce clicks', () => {
  const b = make(); b.advance(10000); assert.equal(b.total, 0); assert.equal(b.state, 'armed');
  b.record(10000, 'mouse'); assert.equal(b.total, 1); assert.equal(b.started, 10000);
  b.advance(20000); assert.equal(b.result.averageCPS, 0.1); assert.equal(b.result.measuredSeconds, 10);
});
test('50,000 supplied input pairs across ten seconds count correctly without an unbounded log', () => {
  const b = make();
  for (let i = 0; i < 50000; i++) b.record(1000 + i * 0.2, 'mouse');
  b.advance(11000);
  assert.equal(b.result.receivedClicks, 50000); assert.equal(b.result.averageCPS, 5000);
  assert.equal(b.result.targetPercent, 100); assert.equal(b.bins.length, 100);
  assert.equal(b.result.clicksPerSecond.reduce((a, v) => a + v, 0), 50000);
});
test('the deadline is exclusive even if the render timer is late', () => {
  const b = make(5); b.record(10); b.record(5009.99); assert.equal(b.record(5010), false);
  b.advance(100000); assert.equal(b.total, 2); assert.equal(b.result.measuredSeconds, 5);
});
test('manual stop uses actual elapsed time; later input is ignored', () => {
  const b = make(); b.record(0); b.record(100); b.finish(1000, 'stopped');
  assert.equal(b.result.averageCPS, 2); assert.equal(b.result.completed, false);
  b.record(1100); assert.equal(b.total, 2);
});
test('single click at zero elapsed has finite zero average until time passes', () => {
  const b = make(); b.record(10); b.finish(10, 'stopped'); assert.equal(b.result.averageCPS, 0);
});
test('synthetic events and incomplete pairs cannot increment the benchmark', () => {
  const b = make(); const g = new PointerGate((t, p) => b.record(t, p));
  g.up(event(), 0); assert.equal(b.total, 0);
  g.down(event({ isTrusted: false })); g.up(event({ isTrusted: false }), 0); assert.equal(b.total, 0);
  g.down(event()); g.up(event(), 0); g.up(event(), 0); assert.equal(b.total, 1);
});
test('cancelled, outside, nonprimary and right-button clicks are excluded', () => {
  const b = make(); const g = new PointerGate(t => b.record(t));
  g.down(event()); g.cancel(event()); g.up(event(), 0);
  g.down(event()); g.up(event(), 0, false);
  g.down(event({ button: 2 })); g.up(event({ button: 2 }), 0);
  g.down(event({ isPrimary: false })); g.up(event({ isPrimary: false }), 0);
  assert.equal(b.total, 0);
});
test('pointer IDs match and synthetic up cannot consume a trusted pair', () => {
  const b = make(); const g = new PointerGate(t => b.record(t));
  g.down(event()); g.up(event({ pointerId: 2 }), 0); assert.equal(b.total, 0);
  g.up(event({ isTrusted: false }), 0); assert.equal(b.total, 0);
  g.up(event(), 0); assert.equal(b.total, 1);
});
test('armed cancellation makes no result; next run resets counts', () => {
  const b = make(); b.finish(500, 'hidden'); assert.equal(b.result, null); assert.equal(b.state, 'idle');
  b.arm({ duration: 5, target: 100 }); b.record(800); b.finish(1800, 'hidden');
  assert.equal(b.result.receivedClicks, 1); assert.equal(b.result.reason, 'hidden');
  b.arm({ duration: 10, target: 5000 }); assert.equal(b.total, 0); assert.equal(b.result, null);
});
test('recent and peak CPS use complete intervals and include empty intervals', () => {
  const b = make(5); b.record(0); b.record(999); b.record(1000);
  assert.equal(b.snapshot(999).current, null); assert.equal(b.snapshot(1000).current, 2);
  assert.equal(b.snapshot(1000).peak, 2); b.advance(5000); assert.equal(b.result.peakFullSecondCPS, 2);
  assert.deepEqual(b.result.clicksPerSecond, [2, 1, 0, 0, 0]);
});
test('invalid settings are rejected', () => {
  for (const target of [0, 40001, NaN, Infinity, 0.5]) assert.throws(() => new Benchmark().arm({ duration: 10, target }));
  assert.throws(() => new Benchmark().arm({ duration: 0, target: 100 }));
  assert.throws(() => new Benchmark().arm({ duration: 10, target: 100, targetCount: 4 }));
});

test('two targets share one timing window and their counts sum to the total', () => {
  const b = new Benchmark(); b.arm({ duration: 10, target: 5000, targetCount: 2 });
  for (let i = 0; i < 50000; i++) b.record(1000 + i * 0.2, 'mouse', i % 2);
  b.advance(11000);
  assert.equal(b.result.receivedClicks, 50000);
  assert.equal(b.result.averageCPS, 5000);
  assert.deepEqual(b.result.receivedByTarget, [
    { target: 1, receivedClicks: 25000, averageCPS: 2500 },
    { target: 2, receivedClicks: 25000, averageCPS: 2500 },
  ]);
});

test('a down on one target and up on another is a drag, not a click', () => {
  const b = new Benchmark(); b.arm({ duration: 5, target: 5000, targetCount: 2 });
  const g = new PointerGate((t, p, i) => b.record(t, p, i));
  g.down(event(), 0); g.up(event(), 0, true, 1);
  assert.equal(b.total, 0); assert.equal(b.state, 'armed');
  g.down(event(), 1); g.up(event(), 100, true, 1);
  g.down(event(), 0); g.up(event(), 200, true, 0);
  b.finish(1100, 'stopped');
  assert.equal(b.result.averageCPS, 2);
  assert.deepEqual(b.result.receivedByTarget.map(p => p.receivedClicks), [1, 1]);
});

test('a missing second target remains zero and invalid target indices cannot start timing', () => {
  const b = new Benchmark(); b.arm({ duration: 5, target: 5000, targetCount: 2 });
  assert.equal(b.record(0, 'mouse', -1), false);
  assert.equal(b.record(0, 'mouse', 2), false);
  assert.equal(b.state, 'armed');
  b.record(100, 'mouse', 0); b.advance(5100);
  assert.deepEqual(b.result.receivedByTarget.map(p => p.receivedClicks), [1, 0]);
  b.arm({ duration: 5, target: 5000, targetCount: 2 });
  assert.deepEqual(b.targetTotals, [0, 0]);
});

test('200,000 supplied pairs at the new upper goal retain exact totals and fair two-point counts', () => {
  const b = new Benchmark(); b.arm({ duration: 10, target: 20000, targetCount: 2, mode: 'fast' });
  const g = new PointerGate((t, p, i) => b.record(t, p, i));
  const e = event();
  for (let i = 0; i < 200000; i++) {
    g.down(e, i % 2); g.up(e, 1000 + i * 0.05, true, i % 2);
  }
  b.advance(11000);
  assert.equal(b.result.receivedClicks, 200000);
  assert.equal(b.result.averageCPS, 20000);
  assert.equal(b.result.targetPercent, 100);
  assert.deepEqual(b.result.receivedByTarget.map(p => p.receivedClicks), [100000, 100000]);
  assert.equal(b.result.schema, 'tapbench-web-v4');
  assert.equal(b.result.clickMode, 'fast');
  assert.equal(b.bins.length, 100);
});

test('mode labels are explicit metadata and cannot generate or alter received counts', () => {
  for (const mode of ['fast', 'steady', 'unspecified']) {
    const b = new Benchmark(); b.arm({ duration: 5, target: 10000, mode });
    b.advance(10000); assert.equal(b.total, 0);
    b.record(10000); b.advance(15000);
    assert.equal(b.result.clickMode, mode);
    assert.equal(b.result.receivedClicks, 1);
    assert.equal(b.result.averageCPS, 0.2);
    assert.match(b.result.modeSource, /User-selected/);
  }
  assert.throws(() => new Benchmark().arm({ duration: 5, target: 10000, mode: 'fake' }));
});

// Injected fixture objects test counting logic only; this is not a real-input speed claim.
test('400,000 supplied pairs at 40k share one timing window across three targets', () => {
  const b = new Benchmark(); b.arm({ duration: 10, target: 40000, targetCount: 3, mode: 'fast' });
  const g = new PointerGate((t, p, i) => b.record(t, p, i)); const e = event();
  for (let i = 0; i < 400000; i++) { g.down(e, i % 3); g.up(e, 1000 + i * 0.025, true, i % 3); }
  b.advance(11000);
  assert.equal(b.result.receivedClicks, 400000); assert.equal(b.result.averageCPS, 40000);
  assert.deepEqual(b.result.receivedByTarget.map(p => p.receivedClicks), [133334, 133333, 133333]);
  assert.equal(b.result.countsPer100ms.reduce((a, v) => a + v, 0), 400000);
  assert.equal(b.result.schema, 'tapbench-web-v4');
  b.arm({ duration: 5, target: 40000, targetCount: 3, mode: 'fast' });
  assert.deepEqual(b.targetTotals, [0, 0, 0]);
  g.reset(); g.down(e, 2); assert.equal(g.up(e, 0, true, 1), false); assert.equal(b.total, 0);
  g.down(e, 2); g.up(e, 1, true, 2); b.advance(5001);
  assert.deepEqual(b.result.receivedByTarget.map(p => p.receivedClicks), [0, 0, 1]);
});
