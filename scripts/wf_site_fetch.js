'use strict';
// 把 warframe-damage.com 的运行时数据抓到本地：武器 JSON + 敌人 JSON。
// 站点的武器数据是懒加载的（GET /getWeapon.php?name=<Name>），不抓就只有名字没有 attacks。
// 用法：node scripts/wf_site_fetch.js [--force]
const fs = require('fs');
const path = require('path');

const SITE = 'https://warframe-damage.com';
const OUT = path.join(__dirname, '..', 'server', 'site');
const WDIR = path.join(OUT, 'weapons');
const FORCE = process.argv.includes('--force');

const safe = n => n.replace(/[^A-Za-z0-9._-]+/g, '_');

async function get(url, tries = 3) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36',
          'Referer': SITE + '/',
        },
      });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return await r.text();
    } catch (e) {
      if (i === tries - 1) throw e;
      await new Promise(r => setTimeout(r, 400 * (i + 1)));
    }
  }
}

(async () => {
  fs.mkdirSync(WDIR, { recursive: true });

  // 1) 首页里内联的武器名列表，就是站点认的全集
  const home = path.join(OUT, 'index.html');
  if (FORCE || !fs.existsSync(home)) {
    const h = await get(SITE + '/');
    fs.writeFileSync(home, h);
    console.log('index.html', h.length);
  }
  const html = fs.readFileSync(home, 'utf8');
  const m = /var Weapon = (\[[\s\S]*?\]);/.exec(html);
  if (!m) throw new Error('首页里没找到 Weapon 列表');
  const names = JSON.parse(m[1]).map(x => x.name);
  console.log('武器', names.length);

  // 2) 敌人数据
  const ej = path.join(OUT, 'data', 'json', 'enemies-min.json');
  fs.mkdirSync(path.dirname(ej), { recursive: true });
  if (FORCE || !fs.existsSync(ej)) {
    const t = await get(SITE + '/data/json/enemies-min.json');
    fs.writeFileSync(ej, t);
    console.log('enemies-min.json', t.length);
  }

  // 3) 逐个武器
  let ok = 0, skip = 0, fail = [];
  const manifest = {};
  const queue = names.slice();
  async function worker() {
    for (;;) {
      const name = queue.shift();
      if (!name) return;
      const f = path.join(WDIR, safe(name) + '.json');
      manifest[name] = safe(name) + '.json';
      if (!FORCE && fs.existsSync(f) && fs.statSync(f).size > 10) { skip++; continue; }
      try {
        const t = await get(SITE + '/getWeapon.php?name=' + encodeURIComponent(name));
        const j = JSON.parse(t);
        if (!j || !j.attacks || !j.attacks.length) throw new Error('no attacks');
        fs.writeFileSync(f, t);
        ok++;
      } catch (e) {
        fail.push(name + ' :: ' + e.message);
      }
      if ((ok + skip) % 50 === 0) console.log('...', ok + skip, '/', names.length);
    }
  }
  await Promise.all([worker(), worker(), worker(), worker(), worker(), worker()]);
  fs.writeFileSync(path.join(OUT, 'weapons.json'), JSON.stringify(manifest, null, 0));
  console.log('下载', ok, '跳过', skip, '失败', fail.length);
  if (fail.length) console.log(fail.slice(0, 20).join('\n'));
})();
