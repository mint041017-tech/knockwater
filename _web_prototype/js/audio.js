/* 程序化音效：无外部音频资源 */
window.Sfx = (() => {
  let ctx = null;
  let master = null;
  let send = null;
  let noiseBuf = null;
  let ambientNodes = null;
  let enabled = true;
  let initStarted = false;

  let streak = 0;
  let lastStep = 0;
  let lastPing = 0;

  const PENTA = [0, 2, 4, 7, 9];
  const BASE = 293.66;

  function now() { return ctx ? ctx.currentTime : 0; }

  function makeNoise() {
    const len = Math.floor(ctx.sampleRate * 2);
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    let last = 0;
    for (let i = 0; i < len; i++) {
      const w = Math.random() * 2 - 1;
      last = last * 0.72 + w * 0.28;
      d[i] = last;
    }
    return buf;
  }

  function init() {
    if (initStarted) return;
    initStarted = true;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    try {
      ctx = new AC();
    } catch (e) { return; }
    master = ctx.createGain();
    master.gain.value = enabled ? 0.85 : 0.0001;
    master.connect(ctx.destination);

    const delay = ctx.createDelay(1.2);
    delay.delayTime.value = 0.26;
    const fb = ctx.createGain();
    fb.gain.value = 0.26;
    const wet = ctx.createGain();
    wet.gain.value = 0.35;
    delay.connect(fb); fb.connect(delay);
    delay.connect(wet); wet.connect(master);
    send = ctx.createGain();
    send.gain.value = 0.5;
    send.connect(delay);

    noiseBuf = makeNoise();
    startAmbient();
    if (ctx.state === 'suspended') ctx.resume();
  }

  function startAmbient() {
    if (!ctx || ambientNodes) return;
    const g = ctx.createGain();
    g.gain.value = 0;
    g.gain.linearRampToValueAtTime(0.05, now() + 3);
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 340;
    lp.Q.value = 0.4;
    lp.connect(g); g.connect(master);

    const specs = [
      { f: 73.42, v: 0.5, type: 'sine' },
      { f: 110.0, v: 0.3, type: 'sine' },
      { f: 146.83, v: 0.10, type: 'triangle' }
    ];
    const oscs = [];
    specs.forEach((s, i) => {
      const o = ctx.createOscillator();
      const og = ctx.createGain();
      o.type = s.type;
      o.frequency.value = s.f;
      o.detune.value = i === 1 ? 5 : -3;
      og.gain.value = s.v;
      o.connect(og); og.connect(lp);
      o.start();
      oscs.push(o);
    });

    const lfo = ctx.createOscillator();
    const lfoG = ctx.createGain();
    lfo.frequency.value = 0.045;
    lfoG.gain.value = 90;
    lfo.connect(lfoG); lfoG.connect(lp.frequency);
    lfo.start();
    oscs.push(lfo);

    ambientNodes = { g, oscs };

    const drop = () => {
      if (!ctx) return;
      if (enabled && Math.random() < 0.72) drip();
      setTimeout(drop, 5200 + Math.random() * 7000);
    };
    setTimeout(drop, 4200);
  }

  function tone(freq, dur, vol, type, opts) {
    if (!ctx) return;
    const o = opts || {};
    const t0 = now() + (o.delay || 0);
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = type || 'sine';
    osc.frequency.setValueAtTime(Math.max(20, freq), t0);
    if (o.to) osc.frequency.exponentialRampToValueAtTime(Math.max(20, o.to), t0 + dur * 0.92);
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(Math.max(0.0002, vol), t0 + (o.attack || 0.01));
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(g);
    let tail = g;
    if (o.pan !== undefined && ctx.createStereoPanner) {
      const p = ctx.createStereoPanner();
      p.pan.value = Math.max(-1, Math.min(1, o.pan));
      g.connect(p);
      tail = p;
    }
    tail.connect(master);
    if (o.send) tail.connect(send);
    osc.start(t0);
    osc.stop(t0 + dur + 0.06);
  }

  function noiseHit(dur, vol, freq, type, opts) {
    if (!ctx || !noiseBuf) return;
    const o = opts || {};
    const src = ctx.createBufferSource();
    src.buffer = noiseBuf;
    const f = ctx.createBiquadFilter();
    f.type = type || 'lowpass';
    f.frequency.value = freq;
    const g = ctx.createGain();
    const t0 = now() + (o.delay || 0);
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(Math.max(0.0002, vol), t0 + (o.attack || 0.006));
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    src.connect(f); f.connect(g); g.connect(master);
    src.start(t0);
    src.stop(t0 + dur + 0.05);
  }

  function drip() {
    const f = 520 + Math.random() * 520;
    tone(f, 0.28, 0.028, 'sine', { to: f * 0.42, pan: Math.random() * 1.4 - 0.7, send: true });
  }

  function step() {
    if (!ctx || !enabled) return;
    const t = performance.now();
    if (t - lastStep > 1500) streak = 0;
    lastStep = t;
    const i = streak++;
    const semi = PENTA[i % 5] + 12 * (Math.floor(i / 5) % 2);
    const f = BASE * Math.pow(2, semi / 12);
    tone(f, 0.22, 0.055, 'sine', { to: f * 0.985, send: true });
    tone(f * 2.01, 0.12, 0.012, 'triangle');
    noiseHit(0.06, 0.012, 2600, 'highpass');
  }

  function knock(power) {
    if (!ctx || !enabled) return;
    const p = Math.max(0.2, Math.min(1, power || 1));
    const f = 128 + 22 * p;
    tone(f, 0.95, 0.16, 'sine', { to: 44, attack: 0.012, send: true });
    tone(f * 1.98, 0.7, 0.045, 'triangle', { to: 78 });
    tone(f * 3.02, 1.5, 0.022, 'sine', { to: 150, delay: 0.03, send: true });
    noiseHit(0.42, 0.07, 520, 'lowpass');
    noiseHit(0.12, 0.03, 3000, 'highpass');
  }

  function petalIn(index) {
    if (!ctx || !enabled) return;
    const base = 880 * Math.pow(2, (index % 3) / 12);
    tone(base, 1.5, 0.06, 'sine', { send: true });
    tone(base * 2.01, 1.0, 0.018, 'sine');
    tone(base * 1.5, 1.8, 0.03, 'sine', { delay: 0.08, send: true });
  }

  function rockPing(x) {
    if (!ctx || !enabled) return;
    const t = performance.now();
    if (t - lastPing < 55) return;
    lastPing = t;
    const f = 1350 + Math.random() * 700;
    tone(f, 0.09, 0.01, 'triangle', { pan: (x / 12) * 1.5 - 0.75 });
  }

  function echo() {
    if (!ctx || !enabled) return;
    tone(1240, 0.5, 0.022, 'sine', { to: 980, send: true });
    tone(1860, 0.35, 0.01, 'sine', { delay: 0.05 });
  }

  function strand() {
    if (!ctx || !enabled) return;
    tone(240, 0.7, 0.08, 'sine', { to: 96, send: true });
    noiseHit(0.3, 0.05, 900, 'lowpass');
  }

  function chargeStart() {
    if (!ctx || !enabled) return;
    tone(180, 0.7, 0.03, 'sine', { to: 300 });
    noiseHit(0.6, 0.008, 1800, 'bandpass');
  }

  function chargeCancel() {
    if (!ctx || !enabled) return;
    tone(300, 0.18, 0.02, 'sine', { to: 180 });
  }

  function win() {
    if (!ctx || !enabled) return;
    const notes = [0, 4, 7, 12];
    notes.forEach((s, i) => {
      const f = 293.66 * Math.pow(2, s / 12);
      tone(f, 1.6, 0.06, 'sine', { delay: i * 0.13, send: true });
      tone(f * 2, 1.2, 0.014, 'triangle', { delay: i * 0.13 });
    });
    tone(73.42, 2.8, 0.05, 'sine', { delay: 0.05, send: true });
  }

  function lose() {
    if (!ctx || !enabled) return;
    tone(146.83, 1.5, 0.07, 'sine', { to: 92, send: true });
    tone(110, 1.9, 0.035, 'sine', { to: 73 });
    noiseHit(0.9, 0.02, 420, 'lowpass');
  }

  function ui() {
    if (!ctx || !enabled) return;
    tone(760, 0.06, 0.018, 'sine');
  }

  function setEnabled(v) {
    enabled = !!v;
    try { localStorage.setItem('kw.sound', enabled ? '1' : '0'); } catch (e) {}
    if (!ctx) return;
    const t = now();
    master.gain.cancelScheduledValues(t);
    master.gain.setValueAtTime(Math.max(0.0001, master.gain.value), t);
    master.gain.exponentialRampToValueAtTime(enabled ? 0.85 : 0.0001, t + 0.35);
    if (enabled && ctx.state === 'suspended') ctx.resume();
  }

  function isEnabled() { return enabled; }

  function resume() {
    if (ctx && ctx.state === 'suspended') ctx.resume();
  }

  try { enabled = localStorage.getItem('kw.sound') !== '0'; } catch (e) {}

  return {
    init, step, knock, petalIn, rockPing, echo, strand,
    chargeStart, chargeCancel, win, lose, ui,
    setEnabled, isEnabled, resume
  };
})();
