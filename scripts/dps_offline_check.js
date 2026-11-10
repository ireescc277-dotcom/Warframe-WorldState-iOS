'use strict';
// 验证浏览器内核：同一份配置，前端（iframe 里的站点脚本）与 Node 内核各算一次，比对。
// 用法：node scripts/dps_offline_check.js [页面地址]

const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const URL_ = process.argv[2] || 'http://127.0.0.1:8811/';
const PORT = 9700 + Math.floor(Math.random() * 60);
const sleep = ms => new Promise(r => setTimeout(r, ms));

// 先在 Node 侧用同一个内核算一遍，拿基准
const K = require('../server/kernel.js');

const CASES = [
  {
    name: 'Torid 无 mod',
    req: { weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, mods: {}, riven: [], custom: [], opts: {}, stance: null },
  },
  {
    name: 'Torid 步枪分裂',
    req: {
      weapon: 'Torid', enemy: 'Heavy Gunner', level: 100,
      mods: { 0: 'Split Chamber' }, riven: [], custom: [], opts: {}, stance: null,
    },
  },
  {
    name: 'Torid + 步枪分裂 + 紫卡爆击',
    req: {
      weapon: 'Torid', enemy: 'Heavy Gunner', level: 100,
      mods: { 0: 'Split Chamber', 1: 'Riven' },
      riven: [{ p: 'crit_chance', v: 60 }, { p: 'multishot', v: 30 }],
      custom: [], opts: {}, stance: null,
    },
  },
  {
    name: 'Torid 钢铁 Lv150 卓越者',
    req: {
      weapon: 'Torid', enemy: 'Heavy Gunner', level: 150, steel: true, eximus: true,
      mods: { 0: 'Split Chamber' }, riven: [], custom: [], opts: { virus: { on: true, stacks: 10 } },
      stance: null,
    },
  },
  {
    name: 'Gram Prime 空手',
    req: { weapon: 'Gram Prime', enemy: 'Heavy Gunner', level: 100, mods: {}, riven: [], custom: [], opts: {}, stance: null },
  },
  {
    name: 'Gram Prime Crossing Snakes',
    req: {
      weapon: 'Gram Prime', enemy: 'Heavy Gunner', level: 100,
      mods: { 9: 'Crossing Snakes' }, riven: [], custom: [], opts: {}, stance: 'Crossing Snakes',
    },
  },
];

function pick(res) {
  const out = {};
  for (const a of (res.attacks || [])) {
    out[a.name] = a.dps;
  }
  return out;
}

(async () => {
  // ---------------- Node 基准
  await K.boot();
  const nodeOut = {};
  for (const c of CASES) {
    try {
      const r = await K.calc(JSON.parse(JSON.stringify(c.req)));
      nodeOut[c.name] = pick(r);
    } catch (e) {
      nodeOut[c.name] = { error: e.message };
    }
  }
  console.log('NODE ' + JSON.stringify(nodeOut, null, 1));

  // ---------------- 浏览器
  fs.mkdirSync('build/tmp', { recursive: true });
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfoff-'));
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
  if (!wsUrl) { console.log('BROWSER  {"error":"浏览器没起来"}'); process.exit(1); }
  const ws = new WebSocket(wsUrl);
  let id = 0; const pend = new Map(); const errors = [];
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      errors.push((d.exception && d.exception.description || d.text || '').slice(0, 300));
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
  await sleep(2500);

  const webOut = {};
  for (const c of CASES) {
    const expr = `window.WFK.calc(${JSON.stringify(c.req)}).then(r => JSON.stringify((r.attacks||[]).reduce((o,a)=>{o[a.name]=a.dps;return o},{})), e => JSON.stringify({error:String(e && e.message || e)}))`;
    const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    try { webOut[c.name] = JSON.parse(r.result.value); } catch (e) { webOut[c.name] = { error: 'bad result ' + r.result.value }; }
  }
  console.log('WEB   ' + JSON.stringify(webOut, null, 1));
  console.log('ERRORS ' + JSON.stringify(errors));
  child.kill();
  process.exit(0);
})();
