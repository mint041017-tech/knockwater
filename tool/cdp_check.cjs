const { spawn } = require('node:child_process');
const http = require('node:http');
const fs = require('node:fs');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = 9333;
const OUT = 'C:\\Users\\Administrator\\Desktop\\insp\\.shots\\';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function get(url) {
  return new Promise((resolve, reject) => {
    http
      .get(url, (res) => {
        let d = '';
        res.on('data', (c) => (d += c));
        res.on('end', () => resolve(d));
      })
      .on('error', reject);
  });
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const chrome = spawn(
    CHROME,
    [
      `--remote-debugging-port=${PORT}`,
      '--user-data-dir=C:\\Users\\Administrator\\AppData\\Local\\Temp\\kwcdp',
      '--no-first-run',
      '--no-default-browser-check',
      '--hide-scrollbars',
      '--enable-unsafe-swiftshader',
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding',
      '--autoplay-policy=no-user-gesture-required',
      '--window-size=430,900',
      '--window-position=40,40',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  let ready = false;
  for (let i = 0; i < 60; i++) {
    try {
      await get(`http://127.0.0.1:${PORT}/json/version`);
      ready = true;
      break;
    } catch (e) {
      await sleep(250);
    }
  }
  if (!ready) throw new Error('chrome devtools not ready');

  const targets = JSON.parse(await get(`http://127.0.0.1:${PORT}/json`));
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));

  let seq = 0;
  const waiters = new Map();
  ws.addEventListener('message', (e) => {
    const m = JSON.parse(e.data);
    if (m.id && waiters.has(m.id)) {
      const w = waiters.get(m.id);
      waiters.delete(m.id);
      if (m.error) w.reject(new Error(`${m.error.message}`));
      else w.resolve(m.result);
      return;
    }
    if (m.method === 'Page.screencastFrame') {
      send('Page.screencastFrameAck', { sessionId: m.params.sessionId }).catch(() => {});
      return;
    }
    if (m.method === 'Runtime.exceptionThrown') {
      console.log('EXCEPTION', JSON.stringify(m.params.exceptionDetails).slice(0, 900));
    }
    if (m.method === 'Runtime.consoleAPICalled') {
      const text = (m.params.args || []).map((a) => a.value ?? a.description ?? '').join(' ');
      console.log('CONSOLE', m.params.type, text.slice(0, 300));
    }
  });

  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++seq;
      waiters.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });

  async function shot(name) {
    const r = await send('Page.captureScreenshot', { format: 'png', fromSurface: true });
    fs.writeFileSync(OUT + name + '.png', Buffer.from(r.data, 'base64'));
    console.log('shot', name);
  }

  async function touch(type, x, y) {
    await send('Input.dispatchTouchEvent', {
      type,
      touchPoints:
        type === 'touchEnd'
          ? []
          : [{ x, y, id: 1, radiusX: 3, radiusY: 3, force: 1 }],
    });
  }

  async function tap(x, y) {
    await touch('touchStart', x, y);
    await sleep(70);
    await touch('touchEnd', x, y);
  }

  async function hold(x, y, ms) {
    await touch('touchStart', x, y);
    await sleep(ms);
    await touch('touchEnd', x, y);
  }

  async function swipe(x0, y0, x1, y1, steps, stepMs) {
    await touch('touchStart', x0, y0);
    for (let i = 1; i <= steps; i++) {
      await sleep(stepMs);
      await send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [
          {
            x: x0 + ((x1 - x0) * i) / steps,
            y: y0 + ((y1 - y0) * i) / steps,
            id: 1,
            radiusX: 3,
            radiusY: 3,
            force: 1,
          },
        ],
      });
    }
    await sleep(60);
    await touch('touchEnd', x1, y1);
  }

  await send('Page.enable');
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', {
    width: 390,
    height: 844,
    deviceScaleFactor: 1,
    mobile: true,
    screenWidth: 390,
    screenHeight: 844,
  });
  await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });

  await send('Page.navigate', { url: 'http://localhost:5180/' });
  await send('Page.bringToFront');
  await sleep(8000);
  await shot('01_title_390');

  await tap(195, 508);
  await sleep(800);
  await shot('02a_intro');
  await sleep(2200);
  await shot('02_level1_390');

  await swipe(195, 640, 235, 600, 7, 40);
  await sleep(420);
  await shot('03_swipe_wave');
  await sleep(1600);

  await tap(102, 803);
  await sleep(1200);

  await touch('touchStart', 330, 786);
  await sleep(900);
  await shot('04a_charging');
  await sleep(400);
  await touch('touchEnd', 330, 786);
  await sleep(2200);
  await shot('04_knock1');
  await sleep(600);

  await hold(330, 786, 1300);
  await sleep(5000);
  await shot('05_win_a');
  await sleep(3500);
  await shot('06_win_b');

  console.log('done');
  ws.close();
  chrome.kill();
  process.exit(0);
})().catch((e) => {
  console.error('FAILED', e);
  process.exit(1);
});
