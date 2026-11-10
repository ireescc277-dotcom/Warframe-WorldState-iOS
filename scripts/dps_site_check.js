'use strict';
// 对拍：本服务 vs warframe-damage.com 线上。
//
// 做法是自己算一遍，同时把内核生成的分享串（?p=...）交给真实站点打开，
// 读它结果区显示的数字，两边并列。
//
//   node scripts/dps_site_check.js
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const K = require('../server/kernel.js');

const PORT = 9810 + Math.floor(Math.random() * 50);
const sleep = ms => new Promise(r => setTimeout(r, ms));

const CASES = [
  { name: '无 mod', req: { weapon: 'Torid', enemy: 'Heavy Gunner', level: 100 } },
  { name: 'Serration', req: { weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, mods: { 0: 'Serration' } } },
  { name: 'Vital Sense', req: { weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, mods: { 0: 'Vital Sense' } } },
  { name: 'Galvanized Chamber', req: { weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, mods: { 0: 'Galvanized Chamber' } } },
  { name: 'Serration+GC', req: { weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, mods: { 0: 'Serration', 1: 'Galvanized Chamber' } } },
];

(async () => {
  // ---- 1. 本方
  const mine = [];
  for (const c of CASES) {
    const r = await K.calc(c.req);
    const url = String(K.W.__lastUrl || '');
    const atk = {};
    for (const a of r.attacks) atk[a.name] = { dps: a.dps.health, ttk: a.ttk.health };
    mine.push({ name: c.name, url, atk });
  }

  // ---- 2. 站点
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfsite-'));
  const child = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',
    ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1500,1100',
      '--remote-debugging-port=' + PORT, '--user-data-dir=' + profile, 'about:blank'],
    { stdio: 'ignore' });

  let wsUrl = null;
  for (let i = 0; i < 80 && !wsUrl; i++) {
    await sleep(200);
    try {
      const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const p = l.find(t => t.type === 'page');
      if (p) wsUrl = p.webSocketDebuggerUrl;
    } catch (e) {}
  }
  if (!wsUrl) { console.log('浏览器没起来'); process.exit(1); }

  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pend = new Map();
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
  });
  await new Promise(r => ws.addEventListener('open', r));
  const send = (method, params) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  await send('Runtime.enable');
  await send('Page.enable');

  const out = [];
  for (const c of mine) {
    await send('Page.navigate', { url: c.url });
    // 站点要下载武器 JSON 再算，给足时间
    await sleep(7000);
    const r = await send('Runtime.evaluate', {
      expression: `(() => {
        const o = {};
        document.querySelectorAll('.rWAItem').forEach(box => {
          const t = box.dataset.type;
          box.querySelectorAll('.rWAItemAttackItem').forEach(it => {
            const n = it.dataset.attack;
            const dps = it.querySelector('.infoQueueDmgOutput');
            const ttk = it.querySelector('[data-type=ttk]');
            if (!n) return;
            o[n] = o[n] || {};
            o[n][t] = dps ? parseInt(dps.textContent.replace(/[^0-9]/g, ''), 10) : null;
            if (t === 'health' && ttk) o[n].ttk = ttk.textContent.trim();
          });
        });
        return JSON.stringify(o);
      })()`, returnByValue: true,
    });
    let site = {};
    try { site = JSON.parse(r.result.value); } catch (e) {}
    out.push({ name: c.name, mine: c.atk, site });
  }

  console.log(JSON.stringify(out, null, 1));
  child.kill();
  process.exit(0);
})();
