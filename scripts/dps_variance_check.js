'use strict';
// 同一配置连算 N 次，看结果波动区间。用来区分「站点自身的随机」和「两边行为不一致」。
const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const K = require('../server/kernel.js');

const N = 12;
const REQ = { weapon: 'Gram Prime', enemy: 'Heavy Gunner', level: 100, mods: {}, riven: [], custom: [], opts: {}, stance: null };
const PORT = 9700 + Math.floor(Math.random() * 60);
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  await K.boot();
  const node = [];
  for (let i = 0; i < N; i++) {
    const r = await K.calc(JSON.parse(JSON.stringify(REQ)));
    const s = (r.attacks.find(a => a.name === 'Slam') || {}).dps || {};
    node.push({ hp: s.health, ar: s.armor });
  }

  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfv-'));
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
  let id = 0; const pend = new Map();
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
  });
  await new Promise(r => ws.addEventListener('open', r));
  const send = (method, params) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.navigate', { url: 'http://127.0.0.1:8811/' });
  await sleep(2500);

  // 同一页面连算 N 次：结果应当完全一致。不一致就说明还有状态残留。
  const web = [];
  for (let i = 0; i < N; i++) {
    const expr = `window.WFK.calc(${JSON.stringify(REQ)}).then(r => { var a = (r.attacks||[]).find(function(x){return x.name==='Slam'}) || {}; return JSON.stringify({hp:a.dps&&a.dps.health, ar:a.dps&&a.dps.armor}); }, e => JSON.stringify({error:String(e&&e.message||e)}))`;
    const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    web.push(JSON.parse(r.result.value));
  }
  console.log('node Slam', JSON.stringify(node));
  console.log('web  Slam', JSON.stringify(web));
  child.kill();
  process.exit(0);
})();
