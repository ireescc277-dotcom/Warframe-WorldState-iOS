'use strict';
// 界面自检：用 CDP 开无头 Chrome，量布局、真实鼠标点交互、截图。
// 用法：node scripts/dps_ui_check.js [url] [outdir]
const {spawn} = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL_ = process.argv[2] || 'http://127.0.0.1:8793/';
const OUT = process.argv[3] || 'build/tmp/ui';
const PORT = 9640 + Math.floor(Math.random() * 40);
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  fs.mkdirSync(OUT, {recursive: true});
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfui-'));
  const child = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',
    ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1440,900',
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
  let id = 0;
  const pend = new Map();
  const errors = [];
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.method === 'Runtime.exceptionThrown') {
      errors.push(JSON.stringify(m.params.exceptionDetails).slice(0, 300));
    }
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
  });
  await new Promise(r => ws.addEventListener('open', r));
  const send = (method, params = {}) => new Promise((res, rej) => {
    const i = ++id;
    pend.set(i, m => m.error ? rej(new Error(m.error.message)) : res(m.result));
    ws.send(JSON.stringify({id: i, method, params}));
  });

  await send('Runtime.enable');
  await send('Page.enable');
  await send('Network.enable');
  await send('Network.setCacheDisabled', {cacheDisabled: true});
  await send('Page.navigate', {url: URL_ + (URL_.includes('?') ? '&' : '?') + 'v=' + Date.now()});
  await sleep(3800);

  const ev = async expr => {
    const r = await send('Runtime.evaluate', {expression: expr, returnByValue: true});
    if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails).slice(0, 300));
    return r.result.value;
  };
  const shot = async name => {
    const r = await send('Page.captureScreenshot', {format: 'png'});
    fs.writeFileSync(path.join(OUT, name + '.png'), Buffer.from(r.data, 'base64'));
  };
  // 真实鼠标点击（headless 下 element.focus() 不触发 focus 事件）
  const clickAt = async (x, y) => {
    await send('Input.dispatchMouseEvent', {type: 'mousePressed', x, y, button: 'left', clickCount: 1});
    await send('Input.dispatchMouseEvent', {type: 'mouseReleased', x, y, button: 'left', clickCount: 1});
  };
  const clickSel = async sel => {
    const p = await ev(`(()=>{const e=document.querySelector(${JSON.stringify(sel)});
      if(!e) return null; const r=e.getBoundingClientRect();
      return {x:Math.round(r.x+r.width/2), y:Math.round(r.y+r.height/2)};})()`);
    if (!p) throw new Error('找不到 ' + sel);
    await clickAt(p.x, p.y);
  };
  const wait = async (ms = 900) => sleep(ms);
  const box = s => ev(`(()=>{const e=document.querySelector(${JSON.stringify(s)});
    if(!e) return null; const r=e.getBoundingClientRect();
    return [Math.round(r.y+scrollY),Math.round(r.height),Math.round(r.width)];})()`);

  const report = {url: URL_, errors};

  // ---------------------------------------------------------------- 布局
  report.layout = {
    docH: await ev('document.body.scrollHeight'),
    header: await box('header'),
    top: await box('.top'),
    wcard: await box('#wcard'),
    tcard: await box('#tcard'),
    build: await box('.build'),
    slots: await box('#slots'),
    lower: await box('.lower'),
    opt: await box('.optpanel'),
    res: await box('.respanel'),
    topCols: await ev(`getComputedStyle(document.querySelector('.top')).gridTemplateColumns`),
    lowerCols: await ev(`getComputedStyle(document.querySelector('.lower')).gridTemplateColumns`),
  };
  report.counts = {
    wlist: await ev(`document.querySelectorAll('#wlist .item').length`),
    elist: await ev(`document.querySelectorAll('#elistbody .item').length`),
    slots: await ev(`document.querySelectorAll('#slots .slot').length`),
    opts: await ev(`document.querySelectorAll('#optgroups .orow').length`),
    groups: await ev(`[...document.querySelectorAll('#optgroups .ogh')].map(e=>e.textContent)`),
  };
  report.values = {
    burst: await ev(`document.getElementById('r-burst').textContent`),
    dps: await ev(`document.getElementById('r-dps').textContent`),
    ttk: await ev(`document.getElementById('r-ttk').textContent`),
    wname: await ev(`document.querySelector('#wcard h2').textContent`),
    tname: await ev(`document.getElementById('tname').textContent.trim()`),
    rows: await ev(`document.querySelectorAll('#brk tbody tr').length`),
  };
  await shot('01-initial');

  // ---------------------------------------------------------------- 武器下拉
  await clickSel('#wsearch');
  await wait(600);
  report.weaponDrop = await ev(`(()=>{const l=document.getElementById('wlist');
    const r=l.getBoundingClientRect(); const i=document.getElementById('wsearch').getBoundingClientRect();
    return {open:getComputedStyle(l).display==='block', n:l.querySelectorAll('.item').length,
      gap:Math.round(r.y-i.bottom), w:Math.round(r.width)};})()`);
  await shot('02-weapon-drop');
  await ev(`(()=>{const i=document.getElementById('wsearch'); i.value='托里德';
    i.dispatchEvent(new Event('input'));})()`);
  await wait(400);
  report.weaponFilter = await ev(`document.querySelectorAll('#wlist .item').length`);
  await clickSel('#wlist .item');
  await wait(1600);
  report.afterWeapon = {
    dropClosed: await ev(`getComputedStyle(document.getElementById('wlist')).display==='none'`),
    name: await ev(`document.querySelector('#wcard h2').textContent`),
    slots: await ev(`document.querySelectorAll('#slots .slot').length`),
    hasInc: await ev(`!!document.getElementById('incpane')`),
    burst: await ev(`document.getElementById('r-burst').textContent`),
  };
  await shot('03-weapon-picked');

  // ---------------------------------------------------------------- 敌人下拉
  await clickSel('#esearch');
  await wait(700);
  report.enemyDrop = await ev(`(()=>{const l=document.getElementById('elist');
    return {open:getComputedStyle(l).display==='block',
      n:l.querySelectorAll('#elistbody .item').length,
      chips:l.querySelectorAll('#fchips button').length};})()`);
  await shot('04-enemy-drop');
  await ev(`[...document.querySelectorAll('#fchips button')].find(b=>b.textContent==='Corpus')?.click()`);
  await wait(400);
  const corpusN = await ev(`document.querySelectorAll('#elistbody .item').length`);
  await clickSel('#elistbody .item');
  await wait(1700);
  report.afterEnemy = {
    corp: corpusN,
    tname: await ev(`document.getElementById('tname').textContent.trim()`),
    hp: await ev(`document.querySelector('#estat div b').textContent`),
    burst: await ev(`document.getElementById('r-burst').textContent`),
  };
  await shot('05-enemy-picked');

  // ---------------------------------------------------------------- 等级
  const before = await ev(`document.getElementById('r-burst').textContent`);
  await ev(`(()=>{const r=document.getElementById('lvl-range'); r.value=200;
    r.dispatchEvent(new Event('input'));})()`);
  await wait(1900);
  report.level200 = {
    from: before,
    to: await ev(`document.getElementById('r-burst').textContent`),
    lv: await ev(`document.getElementById('lvl-num').value`),
    hp: await ev(`document.querySelector('#estat div b').textContent`),
  };

  // ---------------------------------------------------------------- 条件面板
  report.opts = await ev(`(()=>{const g=document.getElementById('optgroups');
    const r=g.getBoundingClientRect();
    return {display:getComputedStyle(g).display, pos:getComputedStyle(g).position,
      h:Math.round(r.height), w:Math.round(r.width),
      rows:g.querySelectorAll('.orow').length,
      groups:[...g.querySelectorAll('.ogh')].map(e=>e.textContent)};})()`);
  const b0 = await ev(`document.getElementById('r-burst').textContent`);
  await ev(`(()=>{const b=document.querySelector('[data-k="rhino"]');
    b.checked=true; b.dispatchEvent(new Event('change'));})()`);
  await wait(1300);
  report.optEffect = {
    before: b0,
    after: await ev(`document.getElementById('r-burst').textContent`),
    badge: await ev(`document.getElementById('opt-n').textContent`),
  };
  await shot('06-opt-on');
  await ev(`(()=>{const b=document.querySelector('[data-k="rhino"]');
    b.checked=false; b.dispatchEvent(new Event('change'));})()`);
  await wait(800);

  // ---------------------------------------------------------------- 选卡器
  // 托里德 10 槽是满的，点第一个已有槽位打开选卡器
  await ev(`(document.querySelector('.slot.empty')||document.querySelector('.slot'))?.click()`);
  await wait(1100);
  report.picker = await ev(`({open:document.getElementById('modal').classList.contains('on'),
    rows:document.querySelectorAll('#m-list .mrow').length})`);
  await shot('07-picker');
  await ev(`document.getElementById('m-close').click()`);

  // ---------------------------------------------------------------- 弹窗
  await clickSel('#btn-note');
  await wait(400);
  report.note = await ev(`({open:document.getElementById('modal').classList.contains('on'),
    title:document.getElementById('m-title').textContent})`);
  await ev(`document.getElementById('m-close').click()`);
  await clickSel('#btn-riven');
  await wait(500);
  report.rivens = await ev(`({open:document.getElementById('modal').classList.contains('on'),
    cards:document.querySelectorAll('.rvr').length})`);
  await ev(`document.getElementById('m-close').click()`);

  // ---------------------------------------------------------------- 排名
  await clickSel('#btn-rank');
  await wait(3200);
  report.rank = await ev(`(()=>{const l=document.getElementById('wlist');
    return {open:getComputedStyle(l).display==='block',
      rows:l.querySelectorAll('.item').length,
      first:(l.querySelector('.item')||{}).textContent?.trim().slice(0,30)};})()`);
  await shot('08-rank');
  await clickSel('#btn-rank');
  await wait(600);

  // ---------------------------------------------------------------- 移动端
  await send('Emulation.setDeviceMetricsOverride',
    {width: 390, height: 844, deviceScaleFactor: 2, mobile: true});
  await send('Page.navigate', {url: URL_ + (URL_.includes('?') ? '&' : '?') + 'm=' + Date.now()});
  await wait(4200);
  report.mobile = {
    docW: await ev('document.body.scrollWidth'),
    viewW: await ev('window.innerWidth'),
    topCols: await ev(`getComputedStyle(document.querySelector('.top')).gridTemplateColumns`),
    overflowX: await ev('document.documentElement.scrollWidth > window.innerWidth + 1'),
    burst: await ev(`document.getElementById('r-burst').textContent`),
  };
  await shot('09-mobile');
  await ev('window.scrollTo(0, document.body.scrollHeight)');
  await wait(700);
  await shot('09b-mobile-bottom');

  report.errors = errors;
  ws.close();
  child.kill();
  console.log(JSON.stringify(report, null, 1));
})();
