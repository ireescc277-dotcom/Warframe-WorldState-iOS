'use strict';
// Warframe 伤害计算后端。
//
// 数据：data/payload.json（由 scripts/build_dpsapp.py 生成）
// 计算：engine.js（与页面内联版逐值对拍过，见 scripts/dps_parity.js）
// 前端：web/ 下的静态文件，同源提供，省掉 CORS 和一整套构建工具。
//
//   node api.js              # 127.0.0.1:8793
//   WF_DPS_PORT=9000 node api.js

const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const {makeEngine} = require('./engine.js');

const PORT = Number(process.env.WF_DPS_PORT || 8793);
const HOST = process.env.WF_DPS_HOST || '127.0.0.1';
const DATA = process.env.WF_DPS_DATA || path.join(__dirname, 'data', 'payload.json');
const WEB = process.env.WF_DPS_WEB || path.join(__dirname, '..', 'web', 'app');

// ---------------------------------------------------------------- 数据装载
let DB = null, ENG = null, LOADED_AT = 0, DATA_MTIME = 0;
let index = null;

const CAT_NAME = {LongGuns: 'PRIMARY', Pistols: 'SECONDARY', Melee: 'MELEE',
  SentinelWeapons: 'SENTINEL', SpaceGuns: 'ARCH-GUN', SpaceMelee: 'ARCH-MELEE'};

function load() {
  const st = fs.statSync(DATA);
  DB = JSON.parse(fs.readFileSync(DATA, 'utf8'));
  ENG = makeEngine(DB);
  DATA_MTIME = st.mtimeMs;
  LOADED_AT = Date.now();
  index = buildIndex();
  console.log(`[load] 武器 ${Object.keys(DB.w).length} · mod ${Object.keys(DB.m).length} · ` +
    `配卡 ${DB.b.length} · 敌人 ${DB.e.length} · 灵化 ${Object.keys(DB.i || {}).length} · ` +
    `紫卡 ${(DB.rv || []).length}`);
}

// 只在 mtime 变了才重载，省得每次请求都 stat 大文件之外还解析。
function maybeReload() {
  try {
    const st = fs.statSync(DATA);
    if (st.mtimeMs !== DATA_MTIME) {
      console.log('[reload] payload 变了');
      load();
    }
  } catch (e) {
    console.error('[reload] ' + e.message);
  }
}

function buildIndex() {
  const W = DB.w;
  const builds = DB.b.filter(b => W[b.w]);
  // 按中文名排序，和页面里的顺讯一致（localeCompare zh）
  const coll = new Intl.Collator('zh-Hans-CN');
  builds.sort((a, b) => coll.compare(W[a.w].z || W[a.w].n, W[b.w].z || W[b.w].n));
  const byUid = new Map();
  builds.forEach((b, i) => byUid.set(b.w, i));

  // mod 按槽位类型分桶，选卡器只拉需要的那一桶
  const modsByCat = {};
  for (const uid in DB.m) {
    const m = DB.m[uid];
    if (m.rv) continue;            // 紫卡是武器专属的，不进通用选卡器
    const t = m.t || '---';
    (modsByCat[t] || (modsByCat[t] = [])).push(uid);
  }
  for (const t in modsByCat) {
    modsByCat[t].sort((x, y) => coll.compare(DB.m[x].z || DB.m[x].n, DB.m[y].z || DB.m[y].n));
  }
  return {builds, byUid, modsByCat};
}

// ---------------------------------------------------------------- 结果缓存
const RANK_CACHE = new Map();
const RANK_MAX = 24;

function padSlots(a) {
  // 配卡最多 11 槽（8 普通 + 特殊功能槽 + 紫卡槽 + 赋能 …），不能截断：
  // 截到 8 会让 43 套配卡少算后面几张卡。
  const x = (a || []).slice(0, 11);
  while (x.length < 8) x.push(null);
  return x.map(s => (s && s.m ? {m: s.m, lv: s.lv | 0} : null));
}

const num = (v, lo, hi, dflt) => {
  const n = Number(v);
  if (!isFinite(n)) return dflt;
  return Math.max(lo, Math.min(hi, n));
};

// 选项口径对齐 warframe-damage.com：0 表示该项关闭（战甲 buff 用 0 代表未勾选）
function readOpt(raw) {
  const o = raw || {};
  return {
    steel: !!o.steel,
    status: o.status !== false,
    // 外部病毒层数：1-10，勾选才生效
    extViral: num(o.extViral, 0, 10, 0),
    // 外部削甲：0-99%
    armorStrip: num(o.armorStrip, 0, 99, 0),
    // 队列时长（秒）：那一站叫「连续射击/攻击时间」，1-60，默认 20
    window: num(o.window, 1, 60, 20),
    // 技能强度：100 = 100%，缩放依赖强度的加成
    strength: num(o.strength, 0, 1000, 100),
    headshot: !!o.headshot,
    // 近战偷袭（暴击倍率 +7）
    stealth: !!o.stealth,
    // 轻攻击连击倍率：0 关闭，1-13
    meleeCombo: num(o.meleeCombo, 0, 13, 0),
    // 狙击连击倍率：0 关闭，1.5-100
    sniperCombo: num(o.sniperCombo, 0, 100, 0),
    // 战甲 buff：0 关闭，否则为百分比
    rhino: num(o.rhino, 0, 9999, 0),
    mirage: num(o.mirage, 0, 9999, 0),
    xata: num(o.xata, 0, 9999, 0),
    tlash: num(o.tlash, 0, 9999, 0),
    nourish: num(o.nourish, 0, 9999, 0),
    // 绝对增加暴击几率（Kullervo / Harrow）
    ccBuff: num(o.ccBuff, 0, 200, 0),
    // 物理伤害 +30%（Madurai）
    madurai: !!o.madurai,
    crit: o.crit !== false,
    incarnon: !!o.incarnon,
    dmgBuff: num(o.dmgBuff, 0, 500, 0),
  };
}

const fmtStat = (k, v) => ({k, v});

// 单次计算
function calcOne(uid, slots, enemy, level, opt) {
  const w = DB.w[uid];
  if (!w) return null;
  const t0 = process.hrtime.bigint();
  const r = ENG.compute(w, slots, enemy, level, opt, uid);
  const A = r.A, d = r.d, s = r.s;

  // 每张卡在「当前等级」下的实际数值，供左栏明细用
  const contrib = [];
  const bad = [];
  for (const sl of slots) {
    if (!sl) continue;
    const m = DB.m[sl.m];
    if (!m) { bad.push((sl.m.split('/').pop() || '')); continue; }
    const row = m.lv[Math.min(sl.lv, m.lv.length - 1)] || {};
    contrib.push({
      n: (m.z && m.z !== m.n) ? m.z : m.n,
      lv: sl.lv, mx: m.mx,
      st: Object.keys(row).map(k => fmtStat(k, row[k])),
    });
  }

  const w2 = r.wp2;
  const payload = {
    uid,
    weapon: {
      n: w2.n, z: w2.z || w2.n, tr: w2.tr || '', cat: w2.cat || '',
      td: w2.td || 0, cc: w2.cc || 0, cm: w2.cm || 1, sc: w2.sc || 0,
      fr: w2.fr || 0, mag: w2.mag || 0, rl: w2.rl || 0, ms: w2.ms || 1,
      incarnon: !!opt.incarnon && !!(DB.i && DB.i[uid]),
    },
    target: {
      n: enemy.n, f: enemy.f || '', fk: A.fk, lv: A.lv,
      hp: A.hp, ar: A.ar0, sh: A.sh, og: A.og, dr: A.dr0,
      base: {hp: enemy.hp, ar: enemy.ar, sh: enemy.sh},
    },
    raw: {perShot: A.perShotShield, shotBase: A.shotBase},
    direct: {
      burst: d.burst, sust: d.sust, perShot: d.toHealth,
      retain: A.perShotShield ? d.toHealth / A.perShotShield : 0,
      rows: d.rows.map(x => ({t: x.t, base: x.base, f: x.f, dr: x.dr,
                             vH: x.vH, share: x.share})),
    },
    contrib, bad,
    bane: A.banePct,
  };
  if (s) {
    payload.sim = {
      dps: s.dps, directDps: s.directDps, dotDps: s.dotDps, kill: s.kill,
      viral: s.viralAtEnd, corr: s.corrAtEnd, strip: s.stripAtEnd,
      dur: s.dur, window: opt.window,
    };
  } else payload.sim = null;

  payload.ms = Number(process.hrtime.bigint() - t0) / 1e6;
  return payload;
}

// ---------------------------------------------------------------- 排名
// 直接序列化整个 opt：以后加选项不会漏进缓存键
const rankKey = (ei, level, opt) => ei + '|' + level + '|' + JSON.stringify(opt);

function rankCached(ei, level, opt) {
  const k = rankKey(ei, level, opt);
  const hit = RANK_CACHE.get(k);
  if (hit) { RANK_CACHE.delete(k); RANK_CACHE.set(k, hit); }
  return hit || null;
}

function rankCompute(ei, level, opt) {
  const k = rankKey(ei, level, opt);
  const enemy = DB.e[ei];
  const t0 = process.hrtime.bigint();
  const rows = index.builds.map((b, i) => {
    const r = ENG.compute(DB.w[b.w], padSlots(b.slots[0]), enemy, level, opt, b.w);
    const val = opt.status ? (r.s ? r.s.dps : r.d.burst) : r.d.burst;
    return {i, uid: b.w, n: DB.w[b.w].z || DB.w[b.w].n, val};
  });
  rows.sort((a, b) => b.val - a.val);
  const out = {rows, ms: Number(process.hrtime.bigint() - t0) / 1e6};
  RANK_CACHE.set(k, out);
  if (RANK_CACHE.size > RANK_MAX) RANK_CACHE.delete(RANK_CACHE.keys().next().value);
  return out;
}

// 1 核小机器上第一次跑要付 JIT 的钱（~1.2s）。开机先按最可能的那组参数跑一遍，
// 用户第一次点「排名」就是热的。
function warmup() {
  const ei = DB.e.findIndex(e => e.n === 'Heavy Gunner');
  const level = 100;
  const opt = readOpt({});
  const t0 = Date.now();
  rankCompute(ei < 0 ? 0 : ei, level, opt);
  console.log(`[warm] 排名预热 ${Date.now() - t0}ms`);
}

// ---------------------------------------------------------------- HTTP
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
  '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8',
};

function sendJSON(res, code, obj, gzipOK) {
  const body = Buffer.from(JSON.stringify(obj), 'utf8');
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  };
  const ae = gzipOK || '';
  if (body.length > 1024 && ae.includes('gzip')) {
    const z = zlib.gzipSync(body, {level: 6});
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

// 静态文件：只允许 web/ 之内的路径
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

function metaPayload() {
  const W = DB.w;
  const weapons = index.builds.map((b, i) => {
    const w = W[b.w];
    return {
      uid: b.w, i, n: w.z || w.n, e: w.n,
      cat: CAT_NAME[w.cat] || w.cat || '',
      ncfg: b.slots.length,
      inc: !!(DB.i && DB.i[b.w]),
      riven: b.slots.some(c => c.some(s => s && s.m.startsWith('RIVEN:'))),
    };
  });
  const facSet = new Set(DB.e.map(e => e.f));
  return {
    meta: DB.meta,
    loadedAt: LOADED_AT,
    weapons,
    enemies: DB.e.map((e, i) => ({i, n: e.n, f: e.f || '', fk: e.fk || ''})),
    factions: [...facSet],
    rivens: DB.rv || [],
  };
}

async function route(req, res) {
  const u = new URL(req.url, 'http://x');
  const p = u.pathname;
  const ae = req.headers['accept-encoding'] || '';

  if (p === '/api/health') {
    return sendJSON(res, 200, {ok: true, loadedAt: LOADED_AT,
      counts: {weapons: Object.keys(DB.w).length, mods: Object.keys(DB.m).length,
               builds: DB.b.length, enemies: DB.e.length}}, ae);
  }
  if (p === '/api/meta') return sendJSON(res, 200, metaPayload(), ae);

  if (p === '/api/weapon') {
    const uid = u.searchParams.get('uid') || '';
    const i = index.byUid.get(uid);
    if (i == null) return sendJSON(res, 404, {error: 'unknown weapon'}, ae);
    const b = index.builds[i];
    const w = DB.w[uid];
    const slots = b.slots.map(cfg => padSlots(cfg).map(s => {
      if (!s) return null;
      const m = DB.m[s.m];
      return m ? {m: s.m, n: m.n, z: m.z || m.n, mx: m.mx, lv: s.lv,
                  t: m.t || '', d: m.d || 0, pol: m.pol || ''}
               : {m: s.m, n: s.m.split('/').pop(), z: '', mx: 0, lv: 0, t: '', d: 0, pol: '', bad: 1};
    }));
    let inc = null;
    if (DB.i && DB.i[uid]) {
      const x = DB.i[uid];
      inc = {name: x.name, tree: x.tree, picked: x.picked,
             forms: (x.forms || []).map(f => ({n: f.n}))};
    }
    return sendJSON(res, 200, {uid, weapon: w, slots, inc,
      riven: (DB.rv || []).filter(r => r.compat === uid)}, ae);
  }

  if (p === '/api/mods') {
    const cat = u.searchParams.get('cat') || '';
    // '---' 桶是通用 mod（任何武器都能装），每次都要带上
    const list = [...(index.modsByCat[cat] || []), ...(index.modsByCat['---'] || [])];
    const raw = new Set((u.searchParams.get('used') || '').split(',').filter(Boolean));
    const out = [];
    for (const uid of list) {
      if (raw.has(uid)) continue;
      const m = DB.m[uid];
      const last = m.lv[m.lv.length - 1] || {};
      out.push({u: uid, n: m.n, z: m.z || m.n, mx: m.mx, d: m.d, t: m.t,
                pol: m.pol || '', st: Object.keys(last).map(k => fmtStat(k, last[k]))});
    }
    return sendJSON(res, 200, {cat, mods: out}, ae);
  }

  if (p === '/api/calc' && req.method === 'POST') {
    const body = await readBody(req);
    const uid = String(body.uid || '');
    if (!index.byUid.has(uid)) return sendJSON(res, 404, {error: 'unknown weapon'}, ae);
    const ei = num(body.ei, 0, DB.e.length - 1, 0);
    const enemy = DB.e[ei | 0];
    const level = num(body.level, 1, 9999, 100);
    const opt = readOpt(body.opt);
    const slots = Array.isArray(body.slots) ? padSlots(body.slots) : padSlots(index.builds[index.byUid.get(uid)].slots[0]);
    const r = calcOne(uid, slots, enemy, level, opt);
    if (!r) return sendJSON(res, 400, {error: 'calc failed'}, ae);
    return sendJSON(res, 200, r, ae);
  }

  if (p === '/api/rank' && req.method === 'POST') {
    const body = await readBody(req);
    const ei = num(body.ei, 0, DB.e.length - 1, 0) | 0;
    const level = num(body.level, 1, 9999, 100);
    const opt = readOpt(body.opt);
    const hit = rankCached(ei, level, opt);
    if (hit) return sendJSON(res, 200, {...hit, cached: true}, ae);
    return sendJSON(res, 200, {...rankCompute(ei, level, opt), cached: false}, ae);
  }

  if (p.startsWith('/api/')) return sendJSON(res, 404, {error: 'not found'}, ae);

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405); res.end('method not allowed'); return;
  }
  return serveStatic(req, res, p);
}

function main() {
  load();
  const server = http.createServer((req, res) => {
    if (req.url !== '/api/health') maybeReload();
    route(req, res).catch(e => {
      console.error(`[err] ${req.url} ${e.message}`);
      if (!res.headersSent) sendJSON(res, 500, {error: e.message});
      else res.end();
    });
  });
  server.keepAliveTimeout = 5000;
  server.listen(PORT, HOST, () => {
    console.log(`wf-dps listening on http://${HOST}:${PORT}  web=${WEB}`);
    console.log(`payload mtime=${new Date(DATA_MTIME).toISOString()}`);
    setTimeout(() => { try { warmup(); } catch (e) { console.error('[warm] ' + e.message); } }, 200);
  });
  const bye = () => { server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 800); };
  process.on('SIGTERM', bye);
  process.on('SIGINT', bye);
}

main();
