'use strict';
// 验证「配卡存档」在真浏览器里活着：自动保存 / 刷新恢复 / 命名存档 / 武器页带入。
// 用法：node scripts/dps_store_check.js [站点目录]
//
// 自己起静态服务，不依赖外部进程——之前用 python -m http.server，进程被回收后
// 整轮都会挂在「页面没就绪」上，看不出是哪一步坏的。

const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path'), http = require('http');

const ROOT = path.resolve(process.argv.slice(2).find(a => !a.startsWith('--')) || 'web/app');
const WEB_PORT = 8813;
const PORT = 9800 + Math.floor(Math.random() * 90);
const sleep = ms => new Promise(r => setTimeout(r, ms));

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.webp': 'image/webp', '.png': 'image/png', '.svg': 'image/svg+xml',
};
const server = http.createServer((req, res) => {
  let rel = decodeURIComponent((req.url || '/').split('?')[0]);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(ROOT, rel);
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); res.end('not found'); return;
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
const BASE = `http://127.0.0.1:${WEB_PORT}/`;

(async () => {
  await new Promise((r, j) => server.listen(WEB_PORT, '127.0.0.1', r).on('error', j));
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wfstore-'));
  const child = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',
    ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1440,1100',
     '--no-proxy-server', '--remote-debugging-port=' + PORT, '--user-data-dir=' + profile,
     'about:blank'],
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
  if (!wsUrl) { console.log('{"error":"浏览器没起来"}'); process.exit(1); }

  const ws = new WebSocket(wsUrl);
  let id = 0; const pend = new Map(); const errors = [];
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      errors.push(((d.exception && d.exception.description) || d.text || '').slice(0, 240));
    }
  });
  await new Promise(r => ws.addEventListener('open', r));
  const send = (method, params) => new Promise(r => {
    const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params }));
  });
  await send('Runtime.enable');
  await send('Page.enable');

  const ev = async (expr, awaitPromise) => {
    const r = await send('Runtime.evaluate',
      { expression: expr, awaitPromise: !!awaitPromise, returnByValue: true });
    if (r.exceptionDetails) {
      return { __err: (r.exceptionDetails.exception && r.exceptionDetails.exception.description)
        || r.exceptionDetails.text };
    }
    return r.result.value;
  };

  // 等页面把结果表画出来（= 内核就绪 + boot 走完）
  const waitReady = async (limit = 120) => {
    for (let i = 0; i < limit; i++) {
      if (await ev("!!(document.querySelector('.acard') && window.WFK && window.WFK.W)")) return true;
      await sleep(250);
    }
    return false;
  };

  const go = async url => {
    await send('Page.navigate', { url });
    await sleep(700);
    const ok = await waitReady();
    if (!ok) throw new Error('页面没就绪：' + url);
  };

  const state = () => ev(`JSON.stringify({
      weapon: S.weapon, enemy: S.enemy && S.enemy.name, level: S.level,
      mods: S.mods, riven: S.riven, stance: S.stance,
      saved: (JSON.parse(localStorage.getItem('wf.loadouts.v1')||'[]')||[]).length,
      wmemKeys: Object.keys(JSON.parse(localStorage.getItem('wf.wmem.v1')||'{}')),
      lastWeapon: (JSON.parse(localStorage.getItem('wf.last.v1')||'null')||{}).weapon || null,
      cards: document.querySelectorAll('.acard').length
    })`).then(s => JSON.parse(s));

  const out = {};
  const fail = [];
  const check = (name, cond, detail) => { out[name] = cond ? 'ok' : ('FAIL ' + JSON.stringify(detail)); if (!cond) fail.push(name); };

  // ---------------- A：配卡 → 自动存下
  await go(BASE + 'index.html');
  out.A0 = await state();
  await ev(`S.mods = {0:'Serration', 1:'Split Chamber'}; S.level = 150; renderSlots(); calc(); 1;`);
  await sleep(1600);
  const a = await state();
  check('A_自动存档', a.mods && a.mods[0] === 'Serration' && a.level === 150,
    { mods: a.mods, level: a.level });
  check('A_last写盘', a.lastWeapon === a.weapon, a);

  // ---------------- B：刷新页面 → 接着上次
  await go(BASE + 'index.html');
  const b = await state();
  check('B_刷新恢复mod', b.mods && b.mods[0] === 'Serration' && b.mods[1] === 'Split Chamber', b.mods);
  check('B_刷新恢复等级', b.level === 150, b.level);
  check('B_结果仍在', b.cards > 0, b.cards);

  // ---------------- C：命名存档 → 改配置 → 载入
  await ev(`openLoadouts(); document.getElementById('lv-name').value = '测试存档';
            document.getElementById('lv-save').click(); 1;`);
  await sleep(400);
  const c1 = await state();
  check('C_存下来', c1.saved === 1, c1.saved);
  await ev(`S.mods = {2:'Vital Sense'}; renderSlots(); calc(); 1;`);
  await sleep(1200);
  await ev(`closeModal();
            document.querySelector('[data-lv]').click(); 1;`);
  await sleep(1500);
  const c2 = await state();
  check('C_载入还原', c2.mods && c2.mods[0] === 'Serration' && c2.mods[1] === 'Split Chamber'
    && !c2.mods[2], c2.mods);

  // ---------------- D：武器页带入（?weapon=X 带回这把武器上次的卡）
  await go(BASE + 'index.html?weapon=Vectis');
  await ev(`S.mods = {0:'Serration'}; renderSlots(); calc(); 1;`);
  await sleep(1400);
  // 从没配过的武器：干净进来
  await go(BASE + 'index.html?weapon=Braton');
  const d0 = await state();
  check('D_新武器干净', d0.weapon === 'Braton' && Object.keys(d0.mods || {}).length === 0, d0.mods);
  // 配过的武器：把这把武器上次的卡带回来
  await go(BASE + 'index.html?weapon=Vectis');
  const d2 = await state();
  check('D_武器页带回', d2.weapon === 'Vectis' && d2.mods && d2.mods[0] === 'Serration', d2);
  check('D_全局沿用', d2.level === 150, d2.level);

  // ---------------- E：删存档要点两下
  await ev(`openLoadouts(); document.querySelector('[data-lvdel]').click(); 1;`);
  await sleep(200);
  const e1 = await state();
  await ev(`document.querySelector('[data-lvdel]').click(); 1;`);
  await sleep(300);
  const e2 = await state();
  check('E_一下不删', e1.saved === 1, e1.saved);
  check('E_两下删掉', e2.saved === 0, e2.saved);

  // ---------------- 可选：截一张存档弹窗的图，肉眼确认排版
  if (process.argv.includes('--shot')) {
    const now = Date.now();
    await ev(`localStorage.setItem('wf.loadouts.v1', JSON.stringify([
      {id:'a',name:'托里德 · 毒云流',wname:'托里德',weapon:'Torid',ename:'重型机枪手',
       enemy:'Heavy Gunner',level:150,ts:${now},
       mods:{0:'Serration',1:'Split Chamber',2:'Vital Sense'}},
      {id:'b',name:'韦克蒂斯 · 狙击',wname:'韦克蒂斯',weapon:'Vectis',ename:'轰击者',
       enemy:'Bombard',level:200,ts:${now - 86400000},mods:{0:'Serration'}}
    ])); openLoadouts(); 1;`);
    await sleep(300);
    const mobile = process.argv.includes('--mobile');
    if (mobile) {
      await send('Emulation.setDeviceMetricsOverride',
        { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
      await sleep(400);
    }
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    fs.mkdirSync('build/tmp', { recursive: true });
    const outPath = mobile ? 'build/tmp/store-mobile.png' : 'build/tmp/store.png';
    fs.writeFileSync(outPath, Buffer.from(shot.data, 'base64'));
    out.shot = outPath;
  }

  out.errors = errors.slice(0, 5);
  out.fail = fail;
  console.log(JSON.stringify(out, null, 1));

  child.kill();
  server.close();
  process.exit(fail.length ? 2 : 0);
})().catch(e => {
  console.log(JSON.stringify({ error: String(e && e.stack || e) }));
  server.close();
  process.exit(1);
});
