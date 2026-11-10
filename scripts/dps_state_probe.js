'use strict';
// 连算两次，dump window 上的全局状态差分，找出跨计算残留的那个变量。
const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const REQ = { weapon: 'Gram Prime', enemy: 'Heavy Gunner', level: 100, mods: {}, riven: [], custom: [], opts: {}, stance: null };
const PORT = 9700 + Math.floor(Math.random() * 60);
const sleep = ms => new Promise(r => setTimeout(r, ms));

const SNAP = `(function(){
  var window = document.getElementById('wf-kernel').contentWindow;
  var out = {};
  for (var k in window) {
    try {
      var v = window[k];
      var t = typeof v;
      if (t === 'function') continue;
      if (t === 'number' || t === 'boolean') { out[k] = v; continue; }
      if (t === 'string') { out[k] = v.length > 60 ? v.slice(0, 60) + '…' : v; continue; }
      if (v && t === 'object' && v !== window && v !== document && !v.nodeType) {
        var s;
        try { s = JSON.stringify(v); } catch (e) { s = '[circ]'; }
        if (s && s.length > 200) s = s.slice(0, 200) + '…';
        out[k] = s;
      }
    } catch (e) {}
  }
  return JSON.stringify(out);
})()`;

(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfp-'));
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

  // 算一次，快照
  let r = await send('Runtime.evaluate', {
    expression: `window.WFK.calc(${JSON.stringify(REQ)}).then(x => 'ok', e => String(e))`,
    awaitPromise: true, returnByValue: true });
  console.log('calc1', r.result.value);
  r = await send('Runtime.evaluate', { expression: SNAP, returnByValue: true });
  const a = JSON.parse(r.result.value);

  // 再算一次，快照
  r = await send('Runtime.evaluate', {
    expression: `window.WFK.calc(${JSON.stringify(REQ)}).then(x => 'ok', e => String(e))`,
    awaitPromise: true, returnByValue: true });
  console.log('calc2', r.result.value);
  r = await send('Runtime.evaluate', { expression: SNAP, returnByValue: true });
  const b = JSON.parse(r.result.value);

  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  const diffs = [];
  for (const k of keys) {
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) diffs.push([k, a[k], b[k]]);
  }
  console.log('diff count', diffs.length);
  for (const [k, va, vb] of diffs) {
    console.log('---', k, '\n  A:', String(va).slice(0, 200), '\n  B:', String(vb).slice(0, 200));
  }
  child.kill();
  process.exit(0);
})();
