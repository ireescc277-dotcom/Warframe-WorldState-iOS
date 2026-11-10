'use strict';
// 打开页面，收 JS 错误，截图。用法：node scripts/dps_shot.js [url] [out.png]
const {spawn} = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const URL_ = process.argv[2] || 'http://127.0.0.1:8793/';
const OUT = process.argv[3] || 'build/tmp/shot.png';
const PORT = 9700 + Math.floor(Math.random() * 60);
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  fs.mkdirSync(path.dirname(OUT), {recursive: true});
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfshot-'));
  const child = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',
    ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1440,1000',
     '--remote-debugging-port=' + PORT, '--user-data-dir=' + profile, 'about:blank'],
    {stdio: 'ignore'});
  let wsUrl = null;
  for (let i = 0; i < 70 && !wsUrl; i++) {
    await sleep(200);
    try {
      const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const p = l.find(t => t.type === 'page');
      if (p) wsUrl = p.webSocketDebuggerUrl;
    } catch (e) {}
  }
  if (!wsUrl) { console.log(JSON.stringify({errors: ['浏览器没起来']})); process.exit(1); }
  const ws = new WebSocket(wsUrl);
  let id = 0; const pend = new Map(); const errors = [];
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      errors.push((d.exception && d.exception.description || d.text || '').slice(0, 400));
    }
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') {
      errors.push(m.params.args.map(a => a.value || a.description || '').join(' ').slice(0, 300));
    }
  });
  await new Promise(r => ws.addEventListener('open', r));
  const send = (method, params) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({id: i, method, params})); });
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.navigate', {url: URL_});
  // 等内核真正就绪：iframe 里的站点脚本执行完，武器/敌人列表渲染出来。
  // 首次要拉 448KB 内核 + 2.9MB 武器数据，固定 sleep 会误判成「页面坏了」。
  let ready = false;
  for (let i = 0; i < 60 && !ready; i++) {
    await sleep(500);
    const chk = await send('Runtime.evaluate', {
      expression: `!!(window.WFK && window.WFK.W) || document.querySelectorAll('.slot').length > 0`,
      returnByValue: true,
    });
    ready = !!(chk && chk.result && chk.result.value);
  }
  // 再等结果卡片：calc 要重建内核环境并跑完整 reCalc
  let hasResult = false;
  for (let i = 0; i < 40 && !hasResult; i++) {
    await sleep(500);
    const chk = await send('Runtime.evaluate', {
      expression: `document.querySelectorAll('.acard').length > 0`,
      returnByValue: true,
    });
    hasResult = !!(chk && chk.result && chk.result.value);
  }
  await sleep(600);
  const r = await send('Runtime.evaluate', {expression: `JSON.stringify({
    slots: document.querySelectorAll('.slot').length,
    opts: document.querySelectorAll('.og').length,
    rows: document.querySelectorAll('.orow').length,
    attacks: document.querySelectorAll('.acard').length,
    big: document.querySelector('.fbox .big') && document.querySelector('.fbox .big').textContent,
    wname: document.querySelector('.wname') && document.querySelector('.wname').textContent,
    tname: document.querySelector('.tname') && document.querySelector('.tname').textContent,
    h: document.body.scrollHeight
  })`, returnByValue: true});
  const shot = await send('Page.captureScreenshot', {format: 'png'});
  fs.writeFileSync(OUT, Buffer.from(shot.data, 'base64'));
  console.log(JSON.stringify({page: JSON.parse(r.result.value), errors}, null, 1));
  child.kill();
  process.exit(0);
})();
