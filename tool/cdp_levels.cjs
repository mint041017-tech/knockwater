const { spawn } = require('node:child_process');
const http = require('node:http');
const fs = require('node:fs');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = 9334;
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
  const chrome = spawn(
    CHROME,
    [
      '--headless=new',
      `--remote-debugging-port=${PORT}`,
      '--user-data-dir=C:\\Users\\Administrator\\AppData\\Local\\Temp\\kwcdp2',
      '--no-first-run',
      '--no-default-browser-check',
      '--hide-scrollbars',
      '--enable-unsafe-swiftshader',
      '--window-size=500,900',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  for (let i = 0; i < 60; i++) {
    try {
      await get(`http://127.0.0.1:${PORT}/json/version`);
      break;
    } catch (e) {
      await sleep(250);
    }
  }
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
      if (m.error) w.reject(new Error(m.error.message));
      else w.resolve(m.result);
    }
    if (m.method === 'Runtime.exceptionThrown') {
      console.log('EXCEPTION', JSON.stringify(m.params.exceptionDetails).slice(0, 700));
    }
  });
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++seq;
      waiters.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });

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

  for (const level of [2, 4, 6]) {
    await send('Page.navigate', { url: `http://localhost:5180/?level=${level}` });
    await sleep(4800);
    const r = await send('Page.captureScreenshot', { format: 'png', fromSurface: true });
    fs.writeFileSync(`${OUT}level${level}_390.png`, Buffer.from(r.data, 'base64'));
    console.log('shot level', level);
  }

  ws.close();
  chrome.kill();
  process.exit(0);
})().catch((e) => {
  console.error('FAILED', e);
  process.exit(1);
});
