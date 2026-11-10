'use strict';
// Warframe 伤害计算后端（v2）。
//
// 计算不在这里做：server/kernel.js 把 warframe-damage.com 自己的 min.js 装进
// jsdom 里跑，mod 特例、逐发队列、状态时间轴、四套抗性都由它算。
// 这一层只负责数据索引、mod 槽位过滤、把 HTTP 请求翻译成内核入参。
//
//   node api.js                  # 127.0.0.1:8793
//   WF_DPS_PORT=9000 node api.js

const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const K = require('./kernel.js');

const PORT = Number(process.env.WF_DPS_PORT || 8793);
const HOST = process.env.WF_DPS_HOST || '127.0.0.1';
const WEB = process.env.WF_DPS_WEB || path.join(__dirname, '..', 'web', 'app');
const SITE = path.join(__dirname, 'site');

// ---------------------------------------------------------------- 武器索引

const MANIFEST = JSON.parse(fs.readFileSync(path.join(SITE, 'weapons.json'), 'utf8'));
const WEAPONS = {};          // name -> 精简索引
const RAW = new Map();       // name -> 完整 JSON（懒读）

function weaponJson(name) {
  if (RAW.has(name)) return RAW.get(name);
  const f = MANIFEST[name];
  if (!f) return null;
  const j = JSON.parse(fs.readFileSync(path.join(SITE, 'weapons', f), 'utf8'));
  j.name = name;
  RAW.set(name, j);
  return j;
}

function buildIndex() {
  for (const name of Object.keys(MANIFEST)) {
    try {
      const j = weaponJson(name);
      if (!j || !j.attacks || !j.attacks.length) continue;
      WEAPONS[name] = {
        name,
        category: j.category || '',
        categories: j.categories || [],
        compTags: j.compTags || [],
        tags: j.tags || [],
        type: j.type || '',
        masteryReq: j.masteryReq || 0,
        imageName: j.imageName || '',
        attacks: j.attacks.map(a => a.name),
        incarnon: !!(j.incarnon && j.incarnon.length),
        mag: j.magazineSize,
        reload: j.reloadTime,
        trigger: j.trigger || '',
      };
    } catch (e) {
      console.error('[idx] ' + name + ' ' + e.message);
    }
  }
}

// ---------------------------------------------------------------- mod 槽位

// 站点的槽位语义（data-id）：
//   0-7   八个主槽
//   8     exilus
//   9     stance（近战）
//   10    武器赋能
//   11-12 战甲赋能
//   13-16 战甲 mod
//   17    aura
//   23-27 执政官碎片
const SLOT_KIND = {
  0: 'main', 1: 'main', 2: 'main', 3: 'main', 4: 'main', 5: 'main', 6: 'main', 7: 'main',
  8: 'exilus', 9: 'stance', 10: 'arcane',
  11: 'frameArcane', 12: 'frameArcane',
  13: 'frame', 14: 'frame', 15: 'frame', 16: 'frame',
  17: 'aura',
  23: 'shard', 24: 'shard', 25: 'shard', 26: 'shard', 27: 'shard',
};

const has = (arr, v) => Array.isArray(arr) && arr.includes(v);
const hasAny = (arr, vs) => Array.isArray(arr) && vs.some(v => arr.includes(v));

// 战甲类 mod 的 tags 有两种含义：武器类别（primary/melee…）或战甲名（BARUUK）。
// 前者按当前武器筛，后者不筛。
function tagOk(m, w) {
  const t = m.tags || [];
  if (!t.length) return true;
  return hasAny(w.categories, t);
}

function modsFor(weaponName, slot) {
  const w = WEAPONS[weaponName];
  if (!w) return [];
  const kind = SLOT_KIND[slot] || 'main';
  const all = K.mods();
  const out = [];
  for (const m of all) {
    const t = m.type || '';
    let ok = false;
    if (kind === 'main') {
      ok = !['exilus', 'stance', 'weapon_mist', 'frame_mist', 'aura', 'shard'].includes(t) &&
           hasAny(w.categories, m.tags);
    } else if (kind === 'exilus') {
      ok = t === 'exilus' && hasAny(w.categories, m.tags);
    } else if (kind === 'stance') {
      ok = t === 'stance' && hasAny(w.compTags, m.tags);
    } else if (kind === 'arcane') {
      ok = t === 'weapon_mist' && hasAny(w.categories, m.tags);
    } else if (kind === 'frameArcane') {
      ok = t === 'frame_mist' && tagOk(m, w);
    } else if (kind === 'frame') {
      ok = t === 'frame_mod';
    } else if (kind === 'aura') {
      ok = t === 'aura_mod' && tagOk(m, w);
    } else if (kind === 'shard') {
      ok = t === 'shard' && tagOk(m, w);
    }
    if (ok) out.push(m);
  }
  return out;
}

// ---------------------------------------------------------------- 串行化
// jsdom 里只有一份全局状态，并发 calc 会互相踩。排队。
let chain = Promise.resolve();
function serial(fn) {
  const p = chain.then(fn, fn);
  chain = p.catch(() => {});
  return p;
}

// ---------------------------------------------------------------- HTTP

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
  '.webp': 'image/webp', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8',
};

function sendJSON(res, code, obj, ae) {
  const body = Buffer.from(JSON.stringify(obj), 'utf8');
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  };
  if (body.length > 1024 && String(ae || '').includes('gzip')) {
    const z = zlib.gzipSync(body, { level: 6 });
    headers['Content-Encoding'] = 'gzip';
    headers['Content-Length'] = z.length;
    res.writeHead(code, headers);
    res.end(z);
  } else {
    headers['Content-Length'] = body.length;
    res.writeHead(code, headers);
    res.end(body);
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let n = 0;
    const chunks = [];
    req.on('data', c => {
      n += c.length;
      if (n > 512 * 1024) { reject(new Error('body too large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!n) return resolve({});
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch (e) { reject(new Error('bad json')); }
    });
    req.on('error', reject);
  });
}

function serveStatic(req, res, urlPath) {
  let rel = decodeURIComponent(urlPath.replace(/^\/+/, ''));
  if (!rel || rel.endsWith('/')) rel += 'index.html';
  const full = path.resolve(WEB, rel);
  if (!full.startsWith(path.resolve(WEB) + path.sep) && full !== path.resolve(WEB)) {
    res.writeHead(403); res.end('forbidden'); return;
  }
  fs.stat(full, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404); res.end('not found'); return; }
    const ext = path.extname(full).toLowerCase();
    const etag = `W/"${st.size.toString(16)}-${st.mtimeMs.toString(16)}"`;
    if (req.headers['if-none-match'] === etag) { res.writeHead(304); res.end(); return; }
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': 'no-cache',
      'ETag': etag,
      'X-Content-Type-Options': 'nosniff',
    });
    if (req.method === 'HEAD') { res.end(); return; }
    fs.createReadStream(full).pipe(res);
  });
}

// ---------------------------------------------------------------- 路由

async function route(req, res) {
  const u = new URL(req.url, 'http://x');
  const p = u.pathname;
  const ae = req.headers['accept-encoding'] || '';

  if (p === '/api/health') {
    return sendJSON(res, 200, {
      ok: true,
      weapons: Object.keys(WEAPONS).length,
      mods: K.W ? K.mods().length : 0,
      bootMs: K.W ? K.W.__bootMs : null,
      rss: Math.round(process.memoryUsage().rss / 1048576),
    }, ae);
  }

  if (p === '/api/meta') {
    return sendJSON(res, 200, {
      weapons: Object.values(WEAPONS).map(w => ({
        n: w.name, l: K.loc(w.name), cat: w.category, atk: w.attacks, tags: w.tags,
        inc: w.incarnon, mr: w.masteryReq, img: w.imageName,
      })),
      enemies: K.enemies(),
      modCount: K.W ? K.mods().length : 0,
    }, ae);
  }

  if (p === '/api/weapon') {
    const name = u.searchParams.get('name') || '';
    const j = weaponJson(name);
    if (!j) return sendJSON(res, 404, { error: 'unknown weapon' }, ae);
    return sendJSON(res, 200, { ...j, index: WEAPONS[name] }, ae);
  }

  if (p === '/api/riven') {
    // 紫卡可选属性随武器类别变（近战没有多重/弹匣，远程没有连击/范围）
    const name = u.searchParams.get('weapon') || '';
    const melee = (WEAPONS[name] && WEAPONS[name].category === 'Melee') || false;
    return sendJSON(res, 200, { melee, attrs: K.rivenAttrs(melee) }, ae);
  }

  if (p === '/api/custom') {
    return sendJSON(res, 200, { attrs: K.customAttrs() }, ae);
  }

  if (p === '/api/mods') {
    const name = u.searchParams.get('weapon') || '';
    const slot = Number(u.searchParams.get('slot'));
    if (!WEAPONS[name]) return sendJSON(res, 404, { error: 'unknown weapon' }, ae);
    if (!Number.isFinite(slot)) return sendJSON(res, 400, { error: 'slot?' }, ae);
    const list = modsFor(name, slot);
    return sendJSON(res, 200, {
      slot, kind: SLOT_KIND[slot] || 'main',
      mods: list.map(m => ({ n: m.name, l: m.l, t: m.type, tags: m.tags, info: m.info,
                             img: m.img, set: m.set, shard: m.shard, act: m.action })),
    }, ae);
  }

  if (p === '/api/calc' && req.method === 'POST') {
    const body = await readBody(req);
    if (!WEAPONS[body.weapon]) return sendJSON(res, 404, { error: 'unknown weapon' }, ae);
    try {
      const r = await serial(() => K.calc({
        weapon: body.weapon,
        enemy: body.enemy,
        level: body.level,
        steel: body.steel,
        eximus: body.eximus,
        party: body.party,
        stance: body.stance,
        riven: body.riven,
        custom: body.custom,
        mods: body.mods,
        opts: body.opts,
      }));
      return sendJSON(res, 200, r, ae);
    } catch (e) {
      return sendJSON(res, 400, { error: e.message }, ae);
    }
  }

  if (p.startsWith('/api/')) return sendJSON(res, 404, { error: 'not found' }, ae);

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405); res.end('method not allowed'); return;
  }
  return serveStatic(req, res, p);
}

// ---------------------------------------------------------------- 启动

async function main() {
  const t0 = Date.now();
  buildIndex();
  console.log(`[idx] 武器 ${Object.keys(WEAPONS).length} / ${Object.keys(MANIFEST).length}`);
  await K.boot();
  console.log(`[boot] 站点内核 ${K.W.__bootMs}ms，mod ${K.mods().length}`);
  console.log(`[idx] 总计 ${Date.now() - t0}ms`);

  const server = http.createServer((req, res) => {
    route(req, res).catch(e => {
      console.error(`[err] ${req.url} ${e.message}`);
      if (!res.headersSent) sendJSON(res, 500, { error: e.message });
      else res.end();
    });
  });
  server.keepAliveTimeout = 5000;
  server.listen(PORT, HOST, () => {
    console.log(`wf-dps listening on http://${HOST}:${PORT}  web=${WEB}`);
  });

  // 预热一次，别让第一个用户等 JIT
  serial(() => K.calc({ weapon: 'Torid', enemy: 'Heavy Gunner', level: 100 }))
    .then(() => console.log('[warm] ok'))
    .catch(e => console.error('[warm] ' + e.message));

  const bye = () => { server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 800); };
  process.on('SIGTERM', bye);
  process.on('SIGINT', bye);
}

main();
