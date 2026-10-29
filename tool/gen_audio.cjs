const fs = require('node:fs');
const path = require('node:path');

const SR = 44100;
const OUT = path.join(__dirname, '..', 'assets', 'audio');
fs.mkdirSync(OUT, { recursive: true });

function make(dur) {
  return new Float64Array(Math.ceil(SR * dur));
}

function tone(buf, opt) {
  const start = opt.start || 0;
  const dur = opt.dur;
  const f0 = opt.f0;
  const f1 = opt.f1 || f0;
  const vol = opt.vol == null ? 1 : opt.vol;
  const decay = opt.decay || 0.3;
  const attack = opt.attack || 0.005;
  const partials = opt.partials || [[1, 1]];
  const i0 = Math.floor(start * SR);
  const n = Math.floor(dur * SR);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const p = Math.min(1, t / dur);
    const f = f0 + (f1 - f0) * p;
    const atk = Math.min(1, t / attack);
    const rel = Math.min(1, (dur - t) / 0.04);
    const env = atk * rel * Math.exp(-t / decay);
    let s = 0;
    for (const [mult, amp] of partials) {
      s += Math.sin(2 * Math.PI * f * mult * t + (opt.phase || 0)) * amp;
    }
    const idx = i0 + i;
    if (idx < buf.length) buf[idx] += s * env * vol;
  }
}

function noise(buf, opt) {
  const start = opt.start || 0;
  const dur = opt.dur;
  const vol = opt.vol == null ? 1 : opt.vol;
  const decay = opt.decay || 0.2;
  const lpAmt = opt.lowpass == null ? 0.25 : opt.lowpass;
  const i0 = Math.floor(start * SR);
  const n = Math.floor(dur * SR);
  let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const w = Math.random() * 2 - 1;
    lp += (w - lp) * lpAmt;
    const env = Math.min(1, t / 0.004) * Math.min(1, (dur - t) / 0.04) * Math.exp(-t / decay);
    const idx = i0 + i;
    if (idx < buf.length) buf[idx] += lp * env * vol;
  }
}

function shimmer(buf, opt) {
  const start = opt.start || 0;
  const dur = opt.dur;
  const vol = opt.vol == null ? 0.04 : opt.vol;
  const decay = opt.decay || 0.2;
  const i0 = Math.floor(start * SR);
  const n = Math.floor(dur * SR);
  let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const w = Math.random() * 2 - 1;
    lp += (w - lp) * 0.08;
    const hp = w - lp;
    const env = Math.min(1, t / 0.002) * Math.min(1, (dur - t) / 0.05) * Math.exp(-t / decay);
    const idx = i0 + i;
    if (idx < buf.length) buf[idx] += hp * env * vol;
  }
}

function addEcho(buf, taps) {
  const src = Float64Array.from(buf);
  for (const [delay, gain] of taps) {
    const d = Math.floor(delay * SR);
    let lp = 0;
    for (let i = d; i < src.length; i++) {
      lp += (src[i - d] - lp) * 0.35;
      buf[i] += lp * gain;
    }
  }
}

const BELL_PARTIALS = [
  [1.0, 1.0, 1.0],
  [2.0, 0.36, 0.78],
  [2.4, 0.25, 0.62],
  [3.0, 0.15, 0.48],
  [4.2, 0.09, 0.34],
  [5.4, 0.05, 0.24],
];

const STEP_PARTIALS = [
  [1.0, 0.65, 1.25],
  [2.0, 0.55, 1.0],
  [2.4, 0.45, 0.85],
  [3.0, 0.3, 0.65],
  [4.2, 0.16, 0.45],
  [5.4, 0.08, 0.3],
];

const KNOCK_PARTIALS = [
  [0.5, 0.3, 3.4],
  [1.0, 0.65, 3.0],
  [2.0, 0.7, 2.6],
  [2.4, 0.55, 2.3],
  [3.0, 0.4, 2.0],
  [4.2, 0.22, 1.5],
  [5.4, 0.12, 1.0],
  [6.8, 0.06, 0.7],
];

function bell(buf, opt) {
  const f = opt.f;
  const start = opt.start || 0;
  const dry = opt.dur || 1.5;
  const scale = opt.decayScale || 1;
  const vol = opt.vol == null ? 0.6 : opt.vol;
  const partials = opt.partials || BELL_PARTIALS;
  for (const [mult, amp, dec] of partials) {
    tone(buf, {
      start,
      dur: dry,
      f0: f * mult,
      vol: vol * amp * 0.62,
      decay: dec * scale,
      attack: 0.0015,
    });
    tone(buf, {
      start,
      dur: dry,
      f0: f * mult * 1.0015,
      vol: vol * amp * 0.38,
      decay: dec * scale,
      attack: 0.0015,
    });
  }
  shimmer(buf, {
    start,
    dur: Math.min(0.9, dry),
    vol: vol * 0.055,
    decay: 0.2,
  });
  if (opt.echo !== false) {
    addEcho(buf, opt.echoTaps || [[0.12, 0.24], [0.25, 0.13], [0.43, 0.06]]);
  }
}


const HARP_HARMONICS = [
  [1, 1.0, 0.72],
  [2, 0.48, 0.55],
  [3, 0.32, 0.45],
  [4, 0.22, 0.36],
  [5, 0.15, 0.28],
  [6, 0.1, 0.22],
  [8, 0.06, 0.15],
];

function harp(buf, opt) {
  const f = opt.f;
  const start = opt.start || 0;
  const dry = opt.dur || 0.82;
  const vol = opt.vol == null ? 0.75 : opt.vol;
  for (const [n, a, d] of HARP_HARMONICS) {
    tone(buf, {
      start,
      dur: dry,
      f0: f * n,
      vol: vol * a,
      decay: d,
      attack: 0.0018,
    });
  }
  shimmer(buf, { start, dur: 0.04, vol: vol * 0.08, decay: 0.01 });
  if (opt.echo !== false) {
    addEcho(buf, opt.echoTaps || [[0.08, 0.06], [0.16, 0.03]]);
  }
}


function reverb(buf, wet, decay) {
  const combs = [1557, 1617, 1491, 1422].map((d) => ({ b: new Float64Array(d), i: 0, lp: 0 }));
  const aps = [225, 556].map((d) => ({ b: new Float64Array(d), i: 0 }));
  const out = new Float64Array(buf.length);
  for (let n = 0; n < buf.length; n++) {
    const x = buf[n];
    let y = 0;
    for (const c of combs) {
      const o = c.b[c.i];
      c.lp = o * 0.6 + c.lp * 0.4;
      c.b[c.i] = x + c.lp * decay;
      c.i = (c.i + 1) % c.b.length;
      y += o;
    }
    y *= 0.25;
    for (const a of aps) {
      const o = a.b[a.i];
      const inp = y + o * 0.5;
      a.b[a.i] = inp;
      a.i = (a.i + 1) % a.b.length;
      y = o - inp * 0.5;
    }
    out[n] = y;
  }
  for (let n = 0; n < buf.length; n++) buf[n] += out[n] * wet;
}

function ksHarp(buf, opt) {
  const f = opt.f;
  const start = opt.start || 0;
  const dur = opt.dur || 2.2;
  const vol = opt.vol == null ? 0.7 : opt.vol;
  const D = SR / f;
  const N = Math.floor(D);
  const frac = D - N;
  const size = N + 2;
  const delay = new Float64Array(size);
  let lp = 0;
  for (let i = 0; i < size; i++) {
    const w = Math.random() * 2 - 1;
    lp += (w - lp) * 0.45;
    delay[i] = lp;
  }
  const pick = Math.max(1, Math.floor(N * 0.23));
  const exc = Float64Array.from(delay);
  for (let i = pick; i < size; i++) delay[i] = exc[i] - exc[i - pick] * 0.75;
  let idx = 0;
  let damp = 0;
  const total = Math.floor(dur * SR);
  const i0 = Math.floor(start * SR);
  for (let i = 0; i < total; i++) {
    const cur = delay[idx];
    const nxt = delay[(idx + 1) % size];
    const s = cur + (nxt - cur) * frac;
    damp += (s - damp) * 0.12;
    const loop = (s * 0.55 + damp * 0.45) * 0.9992;
    delay[idx] = loop;
    const oi = i0 + i;
    if (oi < buf.length) buf[oi] += s * vol;
    idx = (idx + 1) % size;
  }
  reverb(buf, opt.wet == null ? 0.3 : opt.wet, 0.72);
}



function lowpassBuf(buf, cutoff, passes) {
  for (let p = 0; p < passes; p++) {
    const rc = 1 / (2 * Math.PI * cutoff);
    const dt = 1 / SR;
    const a = dt / (rc + dt);
    let y = 0;
    for (let i = 0; i < buf.length; i++) {
      y += a * (buf[i] - y);
      buf[i] = y;
    }
  }
}

function waterBell(buf, opt) {
  const f = opt.f;
  const start = opt.start || 0;
  const dur = opt.dur || 1.0;
  const vol = opt.vol == null ? 0.7 : opt.vol;
  const partials = [
    [1.0, 1.0, 0.55],
    [2.0, 0.42, 0.4],
    [2.4, 0.18, 0.3],
    [3.0, 0.09, 0.22],
    [4.1, 0.04, 0.14],
  ];
  for (const [m, a, d] of partials) {
    tone(buf, { start, dur, f0: f * m, vol: vol * a, decay: d, attack: 0.005 });
    tone(buf, { start, dur, f0: f * m * 1.0012, vol: vol * a * 0.35, decay: d, attack: 0.005 });
  }
  tone(buf, {
    start: start + 0.008,
    dur: 0.85,
    f0: f * 0.25,
    vol: vol * 0.06,
    decay: 0.42,
    attack: 0.02,
    partials: [[1, 1], [2, 0.12]],
  });
  lowpassBuf(buf, 1900, 2);
  reverb(buf, 0.24, 0.42);
}

function finishSilver(buf, peak, name) {
  let max = 0;
  for (let i = 0; i < buf.length; i++) {
    const a = Math.abs(buf[i]);
    if (a > max) max = a;
  }
  const n = buf.length;
  const scale = max > 1e-6 ? peak / max : 0;
  const out = Buffer.alloc(44 + n * 2);
  out.write('RIFF', 0);
  out.writeUInt32LE(36 + n * 2, 4);
  out.write('WAVE', 8);
  out.write('fmt ', 12);
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24);
  out.writeUInt32LE(SR * 2, 28);
  out.writeUInt16LE(2, 32);
  out.writeUInt16LE(16, 34);
  out.write('data', 36);
  out.writeUInt32LE(n * 2, 40);
  const fadeIn = Math.floor(SR * 0.004);
  const fadeOut = Math.floor(SR * 0.09);
  for (let i = 0; i < n; i++) {
    let s = buf[i] * scale;
    if (i < fadeIn) s *= i / fadeIn;
    if (i > n - fadeOut) s *= (n - i) / fadeOut;
    s = Math.max(-1, Math.min(1, s));
    out.writeInt16LE(Math.round(s * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(OUT, name), out);
  console.log(name, (n / SR).toFixed(2) + 's', Math.round(out.length / 1024) + 'KB');
}


function chargeBell(buf) {
  const f = 196;
  const dur = 1.3;
  const partials = [
    [1, 1.0, 0.9],
    [2, 0.5, 0.7],
    [2.4, 0.3, 0.55],
    [3, 0.18, 0.4],
    [4.2, 0.08, 0.25],
  ];
  const n = Math.floor(dur * SR);
  for (const [m, a, d] of partials) {
    for (const det of [1, 1.0015]) {
      const vol = a * (det === 1 ? 0.65 : 0.35) * 0.8;
      for (let i = 0; i < n; i++) {
        const t = i / SR;
        const atk = Math.min(1, t / 0.06);
        const swell = Math.pow(Math.min(1, t / dur), 1.5);
        const trem = 1 + 0.22 * Math.sin(2 * Math.PI * 6.5 * t) * Math.min(1, t / 0.25);
        const rel = Math.min(1, (dur - t) / 0.05);
        buf[i] += Math.sin(2 * Math.PI * f * m * det * t) * atk * swell * trem * rel * vol;
      }
    }
  }
  tone(buf, { dur: 0.45, f0: f * 2, vol: 0.16, decay: 0.12, attack: 0.002, partials: [[1, 1], [2.4, 0.25]] });
  tone(buf, { dur: 1.25, f0: f * 0.5, vol: 0.05, decay: 1.0, attack: 0.08 });
  reverb(buf, 0.22, 0.5);
}

function finishHarp(buf, name) {
  let sum = 0;
  for (let i = 0; i < buf.length; i++) sum += buf[i] * buf[i];
  const rms = Math.sqrt(sum / buf.length);
  const scale = 0.075 / Math.max(rms, 1e-9);
  const n = buf.length;
  const out = Buffer.alloc(44 + n * 2);
  out.write('RIFF', 0);
  out.writeUInt32LE(36 + n * 2, 4);
  out.write('WAVE', 8);
  out.write('fmt ', 12);
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24);
  out.writeUInt32LE(SR * 2, 28);
  out.writeUInt16LE(2, 32);
  out.writeUInt16LE(16, 34);
  out.write('data', 36);
  out.writeUInt32LE(n * 2, 40);
  const fadeIn = Math.floor(SR * 0.003);
  const fadeOut = Math.floor(SR * 0.09);
  for (let i = 0; i < n; i++) {
    let s = buf[i] * scale;
    s = Math.tanh(s);
    if (i < fadeIn) s *= i / fadeIn;
    if (i > n - fadeOut) s *= (n - i) / fadeOut;
    out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s)) * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(OUT, name), out);
  console.log(name, (n / SR).toFixed(2) + 's', Math.round(out.length / 1024) + 'KB');
}

function finish(buf, peak, name) {
  let max = 0;
  for (let i = 0; i < buf.length; i++) {
    const a = Math.abs(buf[i]);
    if (a > max) max = a;
  }
  const scale = max > 1e-6 ? peak / max : 0;
  const n = buf.length;
  const out = Buffer.alloc(44 + n * 2);
  out.write('RIFF', 0);
  out.writeUInt32LE(36 + n * 2, 4);
  out.write('WAVE', 8);
  out.write('fmt ', 12);
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24);
  out.writeUInt32LE(SR * 2, 28);
  out.writeUInt16LE(2, 32);
  out.writeUInt16LE(16, 34);
  out.write('data', 36);
  out.writeUInt32LE(n * 2, 40);
  const fade = Math.floor(SR * 0.06);
  for (let i = 0; i < n; i++) {
    let s = buf[i] * scale;
    if (i < fade) s *= i / fade;
    if (i > n - fade) s *= (n - i) / fade;
    s = Math.max(-1, Math.min(1, s));
    out.writeInt16LE(Math.round(s * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(OUT, name), out);
  console.log(name, (n / SR).toFixed(2) + 's', Math.round(out.length / 1024) + 'KB');
}

const penta = [587.33, 659.26, 739.99, 880.0, 987.77];
penta.forEach((f, i) => {
  const b = make(1.4);
  waterBell(b, { f, dur: 1.0, vol: 0.7 });
  finishSilver(b, 0.38, `step_${i}.wav`);
});

{
  const b = make(3.4);
  const f = 196;
  const partials = [
    [0.5, 0.16, 2.4],
    [1.0, 0.7, 2.3],
    [1.48, 0.35, 2.0],
    [2.0, 0.5, 1.8],
    [2.4, 0.35, 1.5],
    [3.0, 0.2, 1.1],
    [4.2, 0.1, 0.7],
    [5.4, 0.05, 0.45],
  ];
  for (const [m, a, d] of partials) {
    tone(b, { dur: 2.6, f0: f * m, vol: 0.85 * a, decay: d, attack: 0.003 });
    tone(b, { dur: 2.6, f0: f * m * 1.001, vol: 0.3 * a, decay: d, attack: 0.003 });
  }
  tone(b, { dur: 2.4, f0: 98, vol: 0.12, decay: 1.4, attack: 0.01 });
  lowpassBuf(b, 2600, 2);
  reverb(b, 0.26, 0.6);
  finishSilver(b, 0.75, 'knock.wav');
}

{
  const b = make(3.2);
  bell(b, {
    f: 1046,
    dur: 2.0,
    vol: 0.6,
    echoTaps: [[0.12, 0.24], [0.25, 0.12], [0.47, 0.06]],
  });
  finish(b, 0.5, 'chime.wav');
}

{
  const b = make(4.0);
  bell(b, {
    f: 659,
    dur: 2.8,
    vol: 0.6,
    decayScale: 1.2,
    echoTaps: [[0.14, 0.24], [0.29, 0.12], [0.5, 0.06]],
  });
  tone(b, { dur: 2.5, f0: 329, vol: 0.12, decay: 1.2, attack: 0.01 });
  finish(b, 0.52, 'settle.wav');
}

{
  const b = make(1.4);
  tone(b, {
    dur: 1.0,
    f0: 150,
    f1: 60,
    vol: 0.85,
    decay: 0.35,
    attack: 0.004,
    partials: [[1, 1], [2, 0.2]],
  });
  noise(b, { dur: 0.5, vol: 0.3, decay: 0.16, lowpass: 0.08 });
  finish(b, 0.6, 'strand.wav');
}

{
  const b = make(4.6);
  const notes = [293.66, 369.99, 440.0, 587.33];
  notes.forEach((f, i) => {
    bell(b, {
      start: i * 0.18,
      f,
      dur: 2.6,
      vol: 0.5,
      decayScale: 1.1,
      echo: false,
    });
  });
  addEcho(b, [[0.15, 0.2], [0.3, 0.1], [0.55, 0.05]]);
  tone(b, { dur: 3.5, f0: 146.83, vol: 0.15, decay: 1.8, attack: 0.03 });
  finish(b, 0.62, 'win.wav');
}

{
  const b = make(3.6);
  bell(b, {
    f: 146.83,
    dur: 2.6,
    vol: 0.6,
    decayScale: 1.3,
    echo: false,
    partials: [[1, 1, 1.2], [2, 0.25, 0.8], [3, 0.1, 0.5]],
  });
  tone(b, { dur: 2.6, f0: 146, f1: 92, vol: 0.45, decay: 1.1, attack: 0.01 });
  noise(b, { dur: 1.4, vol: 0.06, decay: 0.6, lowpass: 0.03 });
  addEcho(b, [[0.2, 0.15], [0.4, 0.07]]);
  finish(b, 0.55, 'lose.wav');
}

{
  const b = make(0.12);
  tone(b, { dur: 0.1, f0: 900, vol: 0.5, decay: 0.03, attack: 0.002, partials: [[1, 1], [2, 0.2]] });
  finish(b, 0.32, 'ui.wav');
}

{
  const b = make(1.3);
  chargeBell(b);
  finishSilver(b, 0.35, 'charge.wav');
}
