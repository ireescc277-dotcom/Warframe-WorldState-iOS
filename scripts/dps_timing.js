'use strict';
// 测前端内核单次计算端到端耗时（含重建 iframe 环境）。
const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const URL_ = process.argv[2] || 'http://127.0.0.1:8811/';
const PORT = 9700 + Math.floor(Math.random() * 60);
const sleep = ms => new Promise(r => setTimeout(r, ms));

const REQ = {
  weapon: 'Torid', enemy: 'Heavy Gunner', level: 100,
  mods: { 0: 'Split Chamber', 1: 'Serration', 2: 'Point Strike', 3: 'Vital Sense' },
  riven: [], custom: [], opts: { virus: { on: true, stacks: 10 } }, stance: null,
};

(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wft-'));
  const child = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',
    ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1440,1000',
     '--remote-debugging-port=' + PORT, '--user-data-dir=' + profile, 'about:blank'],
    { stdio: 'ignore' });
  let wsUrl = null;
  for (let i = 0; i < 70 && !wsUrl; i++) {
    await sleep(200);
    try {
      const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const p = l.find(t => t.type === 'page');
      if (p) wsUrl = p.webSocketDebuggerUrl;
    } catch (e) {}
  }
  const ws = new WebSocket(wsUrl);
  let id = 0; const pend = new Map(); const errors = [];
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      errors.push((d.exception && d.exception.description || d.text || '').slice(0, 200));
    }
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') {
      errors.push(m.params.args.map(a => a.value || a.description || '').join(' ').slice(0, 200));
    }
  });
  await new Promise(r => ws.addEventListener('open', r));
  const send = (method, params) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.navigate', { url: URL_ });

  for (let i = 0; i < 60; i++) {
    await sleep(500);
    const chk = await send('Runtime.evaluate', { expression: `!!(window.WFK && window.WFK.W)`, returnByValue: true });
    if (chk.result && chk.result.value) break;
  }

  const expr = `window.WFK.calc(${JSON.stringify(REQ)}).then(r => JSON.stringify({
    total: (performance.now() - t0).toFixed(0),
    reCalc: r.ms,
    attacks: (r.attacks||[]).length,
    lost: (r.lostMods||[]).length
  }), e => JSON.stringify({error: String(e && e.message || e)}))`;
  const wrapped = `window.t0 = performance.now(); ${expr}`;

  for (let i = 0; i < 4; i++) {
    const r = await send('Runtime.evaluate', { expression: wrapped, awaitPromise: true, returnByValue: true });
    console.log('run' + (i + 1), r.result.value);
  }
  console.log('errors', JSON.stringify(errors));
  child.kill();
  process.exit(0);
})();
