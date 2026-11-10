'use strict';
/**
 * 计算内核：直接加载 warframe-damage.com 自己的 min.js，在 jsdom 里运行。
 *
 * 不重写任何公式。mod 特例（WITH_COND / onkill / set / 派系 action 表）、
 * 逐发随机队列、状态时间轴、Health/Armor/Shield/Overguard 四套抗性、
 * TTK、中位数 DPS —— 全部由它算，和站点同源。
 *
 * 站点脚本要求的输入分三块：
 *   1. modsPanel[slot] = {name, actions, tags, uncomp, uncomptag, shard, info}
 *   2. 一批选项全局变量（is_headShot / externalVirus / strengthMult ...）
 *   3. 敌人用 showEnemy(name, steel) + correctEnemyLvl(lv) 缩放
 * 算完的数值落在 dpsQueue / TTK_Queue / MedianTotal_Queue / TotalDmg_Queue。
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { JSDOM } = require('jsdom');

const SITE = path.join(__dirname, 'site');
const readSite = f => fs.readFileSync(path.join(SITE, f), 'utf8');

const JQ_SRC = readSite('jquery-min.js');
const MIN_SRC = readSite('min.js');
const HTML = readSite('index.html');
const ZH_SRC = fs.existsSync(path.join(SITE, 'zh.js')) ? readSite('zh.js') : '';
const MANIFEST = JSON.parse(readSite('weapons.json'));
const ENEMIES = JSON.parse(readSite('data/json/enemies-min.json'));

// 结果队列是站点里的全局对象，只在启动时初始化一次，之后每次计算往里 push。
const Q = ['dpsQueue', 'TTK_Queue', 'MedianTotal_Queue', 'TotalDmg_Queue'];

let W = null;            // jsdom window（常驻）
let booting = null;
let loadedWeapon = null; // 已经 showWeapon 过的武器名

// ---------------------------------------------------------------- 启动

function localFetch(w) {
  return u => {
    const s = String(u);
    if (s.includes('getWeapon.php')) {
      let name = '';
      try { name = new URL('http://x' + s).searchParams.get('name') || ''; } catch (e) {}
      const f = MANIFEST[name];
      if (f) return Promise.resolve(res(fs.readFileSync(path.join(SITE, 'weapons', f), 'utf8')));
      return Promise.resolve(res(JSON.stringify({ error: 'no weapon ' + name })));
    }
    if (s.includes('enemies-min.json')) {
      return Promise.resolve(res(fs.readFileSync(path.join(SITE, 'data/json/enemies-min.json'), 'utf8')));
    }
    if (s.includes('getImg.php')) return Promise.resolve(res(''));
    return Promise.resolve(res('{}'));
  };
}

function res(body) {
  return {
    ok: true, status: 200,
    text: () => Promise.resolve(body),
    json: () => Promise.resolve(JSON.parse(body)),
  };
}

function boot() {
  if (booting) return booting;
  booting = new Promise((resolve, reject) => {
    try {
      const t0 = Date.now();
      const dom = new JSDOM(HTML, { url: 'https://warframe-damage.com/', runScripts: 'dangerously' });
      const ctx = dom.getInternalVMContext();
      const w = dom.window;
      vm.runInContext(JQ_SRC, ctx, { filename: 'jquery-min.js' });
      // 站点自带中文对照表（/zh/zh.js，2438 条）；先定义 localeLang，再设 lang，
      // 脚本加载时会调 weaponWithLocale(lang) 把 localeName 填上。
      if (ZH_SRC) vm.runInContext(ZH_SRC, ctx, { filename: 'zh.js' });
      w.lang = ZH_SRC ? 'zh' : 'en';
      w.fetch = localFetch(w);
      w.scrollTo = () => {};
      vm.runInContext(MIN_SRC, ctx, { filename: 'min.js' });
      // 必须在 min.js 之后覆盖：脚本里的 function 声明会盖掉事先挂上的同名属性。
      // 站点把整份配置压进 URL，记下来可以对拍。
      w.setLocation = a => { w.__lastUrl = String(a); };
      W = w;
      W.__bootMs = Date.now() - t0;
      resolve(w);
    } catch (e) {
      booting = null;
      reject(e);
    }
  });
  return booting;
}

// ---------------------------------------------------------------- 武器 / 敌人

async function setWeapon(name) {
  if (!MANIFEST[name]) throw new Error('未知武器: ' + name);
  if (loadedWeapon === name) return;
  await W.showWeapon(name);
  if (!W.currWeapon || W.currWeapon.name !== name) {
    throw new Error('载入武器失败: ' + name);
  }
  loadedWeapon = name;
  clearMods();
}

function clearMods() {
  const mp = W.modsPanel;
  for (const k in mp) mp[k] = 0;
  W.invalidateModStatsCache();
}

function setEnemy(name, steel, level, eximus, party) {
  const hit = ENEMIES.find(e => e.name === name);
  if (!hit) throw new Error('未知敌人: ' + name);
  W.currEnemyLvl = W.currEnemyLvl || 1;
  W.showEnemy(name, !!steel);
  const lv = Math.max(1, Math.min(9999, Number(level) || 1));
  W.currEnemyLvl = lv;
  try { W.currEnemySPStatus = !!steel; } catch (e) {}
  W.$('#setEnemyLvl').val(String(lv));
  // 有些敌人（爆破型等）没有卓越者形态，站点连勾选框都不渲染
  const ex = hit.eximusOff ? false : !!eximus;
  W.currEnemyEximusStatus = ex;
  W.$('#eEximus').prop('checked', ex);
  // 队伍人数只对 showPartyCount 的敌人有意义，correctEnemyLvl 直接读这个输入框
  const pv = W.$('#eParty');
  if (pv.length) pv.val(String(Math.max(1, Math.min(4, Number(party) || 1))));
  if (typeof W.correctEnemyLvl === 'function') W.correctEnemyLvl(lv);
}

// ---------------------------------------------------------------- mod

function modInfo(name) {
  return W.modsProps.find(m => m.name === name) || null;
}

// 站点装 mod 就是往 modsPanel 里塞这个形状，showMod() 里逐字抄的。
function putMod(slot, name) {
  const f = modInfo(name);
  if (!f) return false;
  const cell = {
    name: f.name,
    actions: JSON.parse(JSON.stringify(f.action)),
    tags: f.tags,
    uncomp: f.uncomp,
    uncomptag: f.uncomptag,
    shard: f.shardType,
    info: f.info || '',
  };
  if (f.set) cell.set = f.set;
  W.modsPanel[slot] = cell;
  return true;
}

function applyMods(mods) {
  clearMods();
  const lost = [];
  for (const slot of Object.keys(mods || {})) {
    const name = mods[slot];
    if (!name) continue;
    if (!putMod(Number(slot), name)) lost.push({ slot: Number(slot), name });
  }
  W.invalidateModStatsCache();
  return lost;
}

// ---------------------------------------------------------------- 选项

// {is_set, val} 形状的开关
function flag(v, key) {
  const k = key || 'is_set';
  if (v == null || v === false) return null;
  if (v === true) return { is_set: true };
  if (typeof v === 'object') return v;
  return { is_set: true, val: Number(v) };
}

function applyOpts(o) {
  o = o || {};
  const w = W;

  // 强度：站点存的是倍数，输入框是百分比（100 → 1）
  const st = Number(o.strength);
  w.strengthMult = isFinite(st) && st > 0 ? st / 100 : 1;

  w.is_headShot = !!o.headshot;
  w.stealthBonus = !!o.stealth;
  w.isMaxCond = o.allConds !== false;          // 站点默认勾上
  w.is_Heavy = !!o.heavy;
  w.is_MultiplicativeBasePerStatus = !!o.perStatusMul;
  w.is_MultiplicativeWeakCC = !!o.weakCC;

  w.externalVirus = o.virus
    ? { is_set: !!o.virus.on, stucks: Math.max(0, Math.min(10, Number(o.virus.stacks) || 0)) }
    : { is_set: false, stucks: 0 };

  w.rhinoBuff = flag(o.rhino) || { is_set: false, val: 0 };
  w.mirageBuff = flag(o.mirage) || { is_set: false, val: 0 };
  w.hakuXata = flag(o.xata) || { is_set: false, val: 0 };
  w.toxicLash = flag(o.tlash) || { is_set: false, val: 0 };
  w.nourishBuff = flag(o.nourish) || { is_set: false, val: 0 };
  w.optFlatCrit = flag(o.flatCrit) || { is_set: false, val: 0 };
  w.decreaseArmorOpt = flag(o.armor) || { is_set: false, val: 0 };
  w.manualCountOfStatuses = flag(o.statusCount) || { is_set: false, val: 0 };
  w.optMadurai = { is_set: !!o.madurai };

  // 近战连击 / 重击起始 / 能力连击 / 狙击连击
  if (o.meleeCombo != null) w.comboСounterVal = Number(o.meleeCombo);
  if (o.heavyStart != null) {
    w.combo_counterInitial = Number(o.heavyStart);
    try { w.comboСounterSettingsVal = Number(o.heavyStart); } catch (e) {}
  }
  w.abilityComboСounterSettings = o.abilityCombo != null
    ? { is_set: true, val: Number(o.abilityCombo) }
    : { is_set: false, val: 12 };
  w.sniperComboСounterSettings = o.sniperCombo != null
    ? { is_set: true, val: Number(o.sniperCombo) }
    : { is_set: false, val: 1.5 };

  if (o.queueLength != null) {
    w.queueLength = Math.max(1, Math.min(60, Number(o.queueLength) || 20));
    w.$('#queueLen').val(String(w.queueLength));
  }

  // DOM 上的勾选状态，reCalc 有几处直接读它
  w.$('#optDecreaseArmor').prop('checked', !!w.decreaseArmorOpt.is_set);
  w.$('#optDecreaseArmorVal').val(String(w.decreaseArmorOpt.val || 0));
  w.$('#optCountStatusOnEnemy').prop('checked', !!w.manualCountOfStatuses.is_set);
  w.$('#optCountStatusOnEnemyPc').val(String(w.manualCountOfStatuses.val || 0));
  w.$('#optVirus').prop('checked', !!w.externalVirus.is_set);
  w.$('#optVirusStacks').val(String(w.externalVirus.stucks || 0));
}

// ---------------------------------------------------------------- 计算

function collect() {
  const w = W;
  const out = [];
  const info = (w.currWeapon && w.currWeapon.info) || {};
  // 站点结果区显示的是 currWeapon.info[攻击].queue_<层>（它标作 "Random queue dps"），
  // dpsQueue 只是内部序列，拿它当结果是错的。
  for (const name of Object.keys(w.dpsQueue || {})) {
    const row = { name, dps: {}, ttk: {}, total: {} };
    const it = info[name] || {};
    for (const d of ['health', 'armor', 'shield', 'overguard']) {
      const v = it['queue_' + d];
      if (v != null && isFinite(v)) row.dps[d] = Math.round(v);
      else {
        const a = w.dpsQueue[name] && w.dpsQueue[name][d === 'health' ? 'hp' : d];
        if (a && a.length) row.dps[d] = a[a.length - 1];
      }
      const t = w.TTK_Queue[name] && w.TTK_Queue[name][d];
      if (t && t.length && t[t.length - 1] != null) row.ttk[d] = t[t.length - 1];
      const m = w.MedianTotal_Queue[name] && w.MedianTotal_Queue[name][d];
      if (m && m.length && m[m.length - 1] != null) row.total[d] = m[m.length - 1];
    }
    if (!Object.keys(row.dps).length) continue;
    out.push(row);
  }
  return out;
}

async function calc(req) {
  await boot();
  await setWeapon(req.weapon);
  setEnemy(req.enemy, req.steel, req.level, req.eximus, req.party);

  const lost = applyMods(req.mods);
  applyOpts(req.opts);

  // 结果队列是累加的，算之前清空。
  for (const k of Q) W[k] = {};

  W.reCalc();

  return {
    weapon: W.currWeapon.name,
    enemy: W.currEnemy.name,
    level: W.currEnemyLvl,
    steel: !!W.currEnemySPStatus,
    eximus: !!W.currEnemyEximusStatus,
    party: (W.$('#eParty').length ? Number(W.$('#eParty').val()) : 1) || 1,
    target: {
      hp: W.currEnemy.currHealth, ar: W.currEnemy.currArmor,
      sh: W.currEnemy.currShield, og: W.currEnemy.currOverguard,
      base: {
        hp: W.currEnemy.health && W.currEnemy.health.val,
        ar: W.currEnemy.armor && W.currEnemy.armor.val,
        sh: W.currEnemy.shield && W.currEnemy.shield.val,
      },
      fac: (W.typeOfFaction && W.typeOfFaction[W.currEnemy.faction]) || null,
    },
    attacks: collect(),
    lostMods: lost,
  };
}

// ---------------------------------------------------------------- 列表

// 站点用 localeLang 做显示名，内部 name 始终是英文；计算只认 name。
function loc(name) {
  const m = (W && W.localeLang) || {};
  return m[name] || name;
}

function weapons() {
  return Object.keys(MANIFEST).sort();
}

function enemies() {
  return ENEMIES.map(e => ({
    name: e.name, l: loc(e.name), faction: e.faction, faction_l: loc(e.faction),
    party: !!e.showPartyCount, eximusOff: !!e.eximusOff,
    hp: e.health ? Number(e.health.val) : 0,
    ar: e.armor ? Number(e.armor.val) : 0,
    sh: e.shield ? Number(e.shield.val) : 0,
  }));
}

let modCache = null;
function mods() {
  if (modCache) return modCache;
  modCache = W.modsProps.map(m => ({
    name: m.name,
    l: loc(m.name),
    img: m.img,
    tags: m.tags || [],
    type: m.type || '',
    info: m.info || '',
    set: m.set || null,
    shard: m.shardType || null,
    action: m.action,
  }));
  return modCache;
}

// 武器基础信息（伤害/暴击/射速/攻击段数），前端展示用
function weaponInfo(name) {
  const f = MANIFEST[name];
  if (!f) return null;
  const j = JSON.parse(fs.readFileSync(path.join(SITE, 'weapons', f), 'utf8'));
  return j;
}

module.exports = { boot, calc, weapons, enemies, mods, weaponInfo, loc, get W() { return W; } };
