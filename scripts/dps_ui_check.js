// 用 Chrome DevTools Protocol 打开页面、量尺寸、点击、截图。
// 没有 playwright 时靠它做前端回归；Node 22 自带 WebSocket。
//
//   node scripts/dps_ui_check.js http://127.0.0.1:8793/ [outPrefix]
const {spawn} = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL_ = process.argv[2] || 'http://127.0.0.1:8793/';
const OUT = process.argv[3] || path.join(__dirname, '..', 'build', 'tmp', 'ui');
const CHROME = process.env.CHROME ||
  'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = 9333 + Math.floor(Math.random() * 200);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfcdp-'));
  const child = spawn(CHROME, [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--hide-scrollbars', '--force-device-scale-factor=1',
    '--window-size=1440,900', `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${profile}`, 'about:blank',
  ], {stdio: 'ignore'});

  let wsUrl = null;
  for (let i = 0; i < 60 && !wsUrl; i++) {
    await sleep(200);
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find(t => t.type === 'page');
      if (page) wsUrl = page.webSocketDebuggerUrl;
    } catch (e) {}
  }
  if (!wsUrl) { child.kill(); throw new Error('chrome 没起来'); }

  const ws = new WebSocket(wsUrl);
  const waiters = new Map();
  let id = 0;
  ws.addEventListener('message', ev => {
    const m = JSON.parse(ev.data);
    if (m.id && waiters.has(m.id)) { waiters.get(m.id)(m); waiters.delete(m.id); }
  });
  await new Promise(r => ws.addEventListener('open', r));
  const send = (method, params = {}) => new Promise((res, rej) => {
    const i = ++id;
    waiters.set(i, m => m.error ? rej(new Error(m.error.message)) : res(m.result));
    ws.send(JSON.stringify({id: i, method, params}));
  });

  await send('Page.enable');
  await send('Runtime.enable');
  const logs = [];
  ws.addEventListener('message', ev => {
    const m = JSON.parse(ev.data);
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') {
      logs.push('console: ' + m.params.args.map(a => a.value || a.description).join(' '));
    }
    if (m.method === 'Runtime.exceptionThrown') {
      logs.push('exception: ' + (m.params.exceptionDetails.exception || {}).description);
    }
  });

  await send('Page.navigate', {url: URL_});
  await sleep(3500);   // 跨境链路 + 三次请求（meta / weapon / calc）

  const ev = async expr => {
    const r = await send('Runtime.evaluate', {expression: expr, returnByValue: true, awaitPromise: true});
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + expr);
    return r.result.value;
  };

  const report = {};
  report.viewport = await ev(`[innerWidth, innerHeight]`);
  report.scroll = await ev(`[document.documentElement.scrollHeight, document.body.scrollHeight]`);
  report.boxes = await ev(`(() => {
    const g = s => { const e = document.querySelector(s);
      if (!e) return null; const r = e.getBoundingClientRect();
      return {y: Math.round(r.y), h: Math.round(r.height), w: Math.round(r.width)}; };
    return {header: g('header'), main: g('main'), footer: g('footer'),
            app: g('#app'), bwrap: g('.bwrap'), slots: g('.slots')};
  })()`);
  report.counts = await ev(`(() => ({
    weapons: document.querySelectorAll('#wlist .item').length,
    slots: document.querySelectorAll('.slot').length,
    enemies: document.querySelectorAll('#elist .item').length,
    rows: document.querySelectorAll('#brk tr').length,
    contrib: document.querySelectorAll('#contrib .cr').length,
  }))()`);
  report.values = await ev(`(() => ({
    burst: document.getElementById('r-burst').textContent,
    dps: document.getElementById('r-dps').textContent,
    ttk: document.getElementById('r-ttk').textContent,
    stats: document.getElementById('wstats').innerText.replace(/\\s+/g,' ').trim(),
    target: document.getElementById('estat').innerText.replace(/\\s+/g,' ').trim(),
  }))()`);

  fs.mkdirSync(OUT, {recursive: true});
  const shot = async name => {
    const r = await send('Page.captureScreenshot', {format: 'png'});
    fs.writeFileSync(path.join(OUT, name + '.png'), Buffer.from(r.data, 'base64'));
  };
  await shot('01-initial');

  // 点第二把武器 → 数字应该变
  const before = report.values.burst;
  await ev(`document.querySelectorAll('#wlist .item')[1].click()`);
  await sleep(900);
  const after = await ev(`document.getElementById('r-burst').textContent`);
  report.switchWeapon = {before, after, changed: before !== after};
  await shot('02-second-weapon');

  // 等级拉到 200
  await ev(`(() => { const r = document.getElementById('lvl-range');
    r.value = 200; r.dispatchEvent(new Event('input')); })()`);
  await sleep(1800);
  report.level200 = await ev(`({burst: document.getElementById('r-burst').textContent,
    hp: document.querySelector('#estat').innerText.replace(/\\s+/g,' ')})`);

  // 打开选卡器
  await ev(`document.querySelector('.slot.empty')?.click()`);
  await sleep(900);
  report.picker = await ev(`({open: document.getElementById('modal').classList.contains('on'),
    rows: document.querySelectorAll('#m-list .mrow').length})`);
  await shot('03-picker');
  await ev(`document.getElementById('m-close').click()`);

  // 打开口径弹窗
  await ev(`document.getElementById('btn-note').click()`);
  await sleep(300);
  report.note = await ev(`({open: document.getElementById('modal').classList.contains('on'),
    title: document.getElementById('m-title').textContent})`);
  await shot('03-note');
  await ev(`document.getElementById('m-close').click()`);

  // 带紫卡 + 灵化的武器：野猪 Prime
  await ev(`(() => { const s = document.getElementById('wsearch');
    s.value = '野猪'; s.dispatchEvent(new Event('input')); })()`);
  await sleep(300);
  await ev(`document.querySelector('#wlist .item')?.click()`);
  await sleep(900);
  report.rivenWeapon = await ev(`(() => ({
    name: document.querySelector('.wtitle h2').textContent,
    rivenSlot: [...document.querySelectorAll('.slot .snm')].map(e => e.textContent)
      .filter(t => /-/.test(t)).length,
    incarnon: !!document.querySelector('#incpane'),
    burst: document.getElementById('r-burst').textContent,
  }))()`);
  await shot('04-riven-incarnon');

  // 切灵化形态
  const preIn = await ev(`document.getElementById('r-burst').textContent`);
  await ev(`document.querySelector('#incpane .seg button[data-v="1"]').click()`);
  await sleep(900);
  const postIn = await ev(`document.getElementById('r-burst').textContent`);
  report.incarnon = {preIn, postIn, changed: preIn !== postIn};

  // 多配置切换
  await ev(`(() => { const s = document.getElementById('wsearch');
    s.value = ''; s.dispatchEvent(new Event('input')); })()`);
  await ev(`(() => { const it = [...document.querySelectorAll('#wlist .item')]
    .find(e => e.textContent.includes('奏凯')); it && it.click(); })()`);
  await sleep(900);
  report.tabs = await ev(`(() => {
    const bs = [...document.querySelectorAll('.tabs button')];
    if (bs.length < 2) return {tabs: bs.length};
    const before = [...document.querySelectorAll('.slot .snm')].map(e => e.textContent).join('|');
    bs[1].click();
    return {tabs: bs.length, before};
  })()`);
  await sleep(900);
  report.tabs.after = await ev(
    `[...document.querySelectorAll('.slot .snm')].map(e => e.textContent).join('|')`);
  report.tabs.changed = report.tabs.before !== report.tabs.after;

  // 紫卡清单
  await ev(`document.getElementById('btn-riven').click()`);
  await sleep(400);
  report.rivens = await ev(`({rows: document.querySelectorAll('#m-list .rvr').length})`);
  await ev(`document.getElementById('m-close').click()`);

  // 排名
  await ev(`document.getElementById('btn-rank').click()`);
  await sleep(2500);
  report.rank = await ev(`({rows: document.querySelectorAll('#wlist .item').length,
    first: document.querySelector('#wlist .item .sub')?.textContent})`);
  await shot('05-rank');

  // 窄屏
  await send('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 2, mobile: true});
  await sleep(600);
  await shot('05-mobile');
  report.mobile = await ev(`({pane: document.body.dataset.pane,
    tabbar: getComputedStyle(document.getElementById('tabbar')).display,
    footer: document.querySelector('footer').getBoundingClientRect().height})`);

  report.errors = logs;
  console.log(JSON.stringify(report, null, 2));

  ws.close();
  child.kill();
  try { fs.rmSync(profile, {recursive: true, force: true}); } catch (e) {}
}

main().catch(e => { console.error(e); process.exit(1); });
