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
  const lv = Math.max(1, Math.min(9999, Number(level) || 1));
  // The real page sets these globals before calling showEnemy (see its enemy
  // picker handler). `showEnemy`/`correctEnemyLvl` read them while rebuilding
  // the resistance table. Setting Eximus afterward left the previous case's
  // overguard on a non-Eximus enemy in this persistent jsdom harness.
  const ex = hit.eximusOff ? false : !!eximus;
  W.currEnemySPStatus = !!steel;
  W.currEnemyEximusStatus = ex;
  W.currEnemyLvl = lv;
  W.showEnemy(name, !!steel);
  W.$('#setEnemyLvl').val(String(lv));
  // 有些敌人（爆破型等）没有卓越者形态，站点连勾选框都不渲染
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

function applyMods(mods, riven) {
  clearMods();
  const lost = [];
  for (const slot of Object.keys(mods || {})) {
    const name = mods[slot];
    if (!name) continue;
    if (name === 'Riven') {
      if (!putRiven(Number(slot), riven)) lost.push({ slot: Number(slot), name });
      continue;
    }
    if (!putMod(Number(slot), name)) lost.push({ slot: Number(slot), name });
  }
  W.invalidateModStatsCache();
  return lost;
}

// 灵化节点不是 modsProps 里的普通 Mod；网站界面选择后会把原始武器 JSON
// 里的 action 直接放进固定的 18...22 槽。对拍入口使用同一形状，而不是
// 重新解释节点公式。接受 {"19": 1} 或 ["19:1"] 两种便于 fixture 的格式。
function applyIncarnon(perks) {
  const raw = W.currWeapon && W.currWeapon.incarnon && W.currWeapon.incarnon[0];
  if (!raw || !perks) return [];

  const pairs = [];
  if (Array.isArray(perks)) {
    for (const value of perks) {
      const [tier, option] = String(value).split(':');
      pairs.push([Number(tier), Number(option)]);
    }
  } else if (typeof perks === 'object') {
    for (const [tier, option] of Object.entries(perks)) {
      pairs.push([Number(tier), Number(option)]);
    }
  }

  const lost = [];
  for (const [tier, option] of pairs) {
    const choices = raw[tier];
    const choice = choices && choices[option];
    if (!Number.isInteger(tier) || !Number.isInteger(option) || !choice) {
      lost.push({ tier, option });
      continue;
    }
    W.modsPanel[tier] = {
      name: 'Incarnon',
      mod_id: tier,
      prop_id: option,
      actions: JSON.parse(JSON.stringify(choice.action || {})),
    };
  }
  W.invalidateModStatsCache();
  return lost;
}

function normalizeCombination(value) {
  const list = Array.isArray(value) ? value : String(value).split(',');
  const members = list.map(Number).filter(Number.isInteger).sort((a, b) => a - b);
  return members.length > 1 && new Set(members).size === members.length
    ? members.join(',')
    : null;
}

// comb 是网站 UI 的一组 checkbox，初始均未勾选。每一次计算都显式重置
// 它们，避免同一 jsdom 会话中前一个 case 的选择泄漏到后一个 case。
function applyCombinedAttacks(requested) {
  const wanted = new Set((Array.isArray(requested) ? requested : [])
    .map(normalizeCombination)
    .filter(Boolean));
  const selected = [];
  W.$('.combCxb').each(function () {
    const checkbox = W.$(this);
    const id = normalizeCombination(checkbox.parent('.combItem').data('id'));
    const enabled = !!id && wanted.has(id);
    checkbox.prop('checked', enabled);
    if (enabled) selected.push(id.split(',').map(Number));
  });
  return selected;
}

// ---------------------------------------------------------------- 自定义属性
//
// 站点的 26 项面板外加成，写进 customStats，由 getCustomStat() 在各处读取。
// d=1 的项界面按百分比填、内部存小数；d=0 的项原值（多重、连击数、初始连击等）。

const CUSTOM_ATTR = [
  { k: 'base', n: 'Base Damage', l: '基础伤害', pct: 1 },
  { k: 'base_per_status', n: 'Base Damage per Status Effect', l: '每层状态的基础伤害', pct: 1 },
  { k: 'flat_change_dmg', n: 'Increase Base Damage (flat)', l: '固定加算基础伤害', pct: 0 },
  { k: 'abilityCombo', n: 'Combo Ability Multiplier', l: '技能连击倍率', pct: 0 },
  { k: 'crit_chance', n: 'Critical Chance', l: '暴击率', pct: 1 },
  { k: 'mult_crit_chance', n: 'Critical Chance (multiplicative)', l: '暴击率（乘算）', pct: 1 },
  { k: 'flat_crit_chance', n: 'Critical Chance (absolute)', l: '暴击率（绝对加成）', pct: 1 },
  { k: 'crit_chance_weakp', n: 'Weak Point Critical Chance', l: '弱点暴击率', pct: 1 },
  { k: 'crit_mult', n: 'Critical Multiplier', l: '暴击倍率', pct: 1 },
  { k: 'crit_mult_add', n: 'Critical Multiplier (absolute)', l: '暴击倍率（绝对加成）', pct: 0 },
  { k: 'crit_mult_mult', n: 'Critical Multiplier (final ×)', l: '暴击倍率（最终乘算）', pct: 0 },
  { k: 'status_chance', n: 'Status Chance', l: '触发几率', pct: 1 },
  { k: 'status_chance_mult', n: 'Vulnerable to Status Chance', l: '触发几率易伤', pct: 1 },
  { k: 'absolute_status_chance', n: 'Status Chance (absolute)', l: '触发几率（绝对加成）', pct: 0 },
  { k: 'status_damage', n: 'Status Damage', l: '状态伤害', pct: 1 },
  { k: 'vuln_status_damage', n: 'Vulnerability Status Damage', l: '易伤状态伤害', pct: 1 },
  { k: 'speed', n: 'Fire Rate / Attack Speed', l: '射速 / 攻速', pct: 1 },
  { k: 'multishot', n: 'Multishot', l: '多重', pct: 0 },
  { k: 'magazineSize', n: 'Magazine Size', l: '弹匣容量', pct: 1 },
  { k: 'reloadTime', n: 'Reload Time', l: '装填速度', pct: 1 },
  { k: 'mult_for_head', n: 'Headshot Damage', l: '爆头伤害', pct: 1 },
  { k: 'headshot_mult', n: 'Weak Point Damage', l: '弱点伤害', pct: 1 },
  { k: 'initialCombo', n: 'Initial Combo', l: '初始连击', pct: 0 },
  { k: 'dmgVulnerability', n: 'Damage Vulnerability', l: '伤害易伤', pct: 1 },
  { k: 'heatInherit', n: 'Heat Inherit', l: '火焰继承', pct: 1 },
  { k: 'heatAdd', n: 'Add Heat Instance', l: '附加火焰实例', pct: 1 },
];

function applyCustom(list) {
  const cs = W.customStats || (W.customStats = {});
  for (const k in cs) delete cs[k];
  const out = {};
  for (const it of list || []) {
    const meta = CUSTOM_ATTR.find(a => a.k === it.k);
    const v = Number(it.v);
    if (!meta || !isFinite(v) || v === 0) continue;
    const val = meta.pct ? v / 100 : v;
    W.setCustomStat(it.k, val);
    out[it.k] = v;
  }
  return out;
}

// ---------------------------------------------------------------- 紫卡
//
// 站点不把紫卡放在 modsProps 里：它是弹窗临时构造的 modsProps[9999]，
// 由 showRiven() 从 #rivenSettings 的四个输入块读出来。
// 这里的属性表与站点源码里的那张一致（含 addt 归类）。

const RIVEN_ATTR = {
  crit_chance: { name: 'Critical Chance' },
  crit_mult: { name: 'Critical Multiplier' },
  multishot: { name: 'Multishot' },
  status_chance: { name: 'Status Chance' },
  base: { name: 'Damage' },
  speed: { name: 'Fire Rate / Attack Speed' },
  Cold: { name: 'Cold', addt: 'element' },
  Heat: { name: 'Heat', addt: 'element' },
  Electricity: { name: 'Electricity', addt: 'element' },
  Toxin: { name: 'Toxin', addt: 'element' },
  Impact: { name: 'Impact', addt: 'phys' },
  Puncture: { name: 'Puncture', addt: 'phys' },
  Slash: { name: 'Slash', addt: 'phys' },
  addViral: { name: 'Viral' },
  addBlast: { name: 'Blast' },
  addGas: { name: 'Gas' },
  addMagnetic: { name: 'Magnetic' },
  addRadiation: { name: 'Radiation' },
  addCorrosive: { name: 'Corrosive' },
  status_damage: { name: 'Status Damage' },
  Corpus: { name: 'Damage to Corpus', addt: 'SMITE' },
  Grineer: { name: 'Damage to Grineer', addt: 'SMITE' },
  Infested: { name: 'Damage to Infested', addt: 'SMITE' },
  Scaldra: { name: 'Damage to Scaldra', addt: 'SMITE' },
  Techrot: { name: 'Damage to Techrot', addt: 'SMITE' },
  crit_chance_weakp: { name: 'Weak Point Critical Chance', addt: 'SMITE' },
  ammoCapacity: { name: 'Ammo Maximum' },
  ammoEff: { name: 'Ammo Efficiency' },
  mult_for_head: { name: 'Weak Point Damage' },
  magazineSize: { name: 'Magazine Capacity' },
  reloadTime: { name: 'Reload Speed' },
  shot_speed: { name: 'Shot Speed' },
  comboDuration: { name: 'Combo Duration' },
  initialCombo: { name: 'Initial Combo' },
  melee_combo_eff: { name: 'Heavy Attack Efficiency' },
  range: { name: 'Range' },
  punch_through: { name: 'Punch Through' },
  zoom: { name: 'Zoom' },
  recoil: { name: 'Weapon Recoil' },
  status_duration: { name: 'Status Duration' },
};

// 近战与远程可选属性不同，站点是按 productCategory 删表实现的
const RIVEN_DROP_MELEE = ['punch_through', 'shot_speed', 'reloadTime', 'magazineSize', 'ammoCapacity', 'multishot', 'ammoEff'];
const RIVEN_DROP_RANGED = ['range', 'melee_combo_eff', 'initialCombo', 'comboDuration'];

function rivenAttrs(melee) {
  if (melee == null) melee = (W.currWeaponInitial || W.currWeapon || {}).productCategory === 'Melee';
  const drop = melee ? RIVEN_DROP_MELEE : RIVEN_DROP_RANGED;
  return Object.keys(RIVEN_ATTR)
    .filter(k => !drop.includes(k))
    .map(k => ({
      k, n: RIVEN_ATTR[k].name, l: loc(RIVEN_ATTR[k].name), g: RIVEN_ATTR[k].addt || 'misc',
      // 站点 showRiven 对这三类做不同换算：原值 / 减 1 / 除 100
      u: ['Corpus', 'Grineer', 'Infested', 'Scaldra', 'Techrot'].includes(k) ? 'x'
        : ['comboDuration', 'initialCombo', 'range', 'punch_through'].includes(k) ? 's' : '%',
    }));
}

// props: [{p:'crit_chance', v:60}, ...] 最多四条，v 是用户填的原始数字
function setRiven(props) {
  const list = (props || []).filter(x => x && x.p && RIVEN_ATTR[x.p] && Number(x.v)).slice(0, 4);
  const blocks = W.$('#rivenSettings').find('.rivenSettingsInputBlock');
  blocks.each((i, el) => {
    const box = W.$(el);
    const inp = box.find('.customDropdownInput');
    const val = box.find('.rivenSettingsIAVal');
    const it = list[i];
    if (!it) {
      inp.attr('data-type', '').attr('data-addt', '').text('Select property').data('type', '').data('addt', '');
      val.val('');
      return;
    }
    const meta = RIVEN_ATTR[it.p];
    inp.attr('data-type', it.p).attr('data-addt', meta.addt || '')
      .data('type', it.p).data('addt', meta.addt || '').text(meta.name);
    val.val(String(Number(it.v)));
  });
  W.showRiven();
  const rv = W.modsProps[9999];
  if (!rv || !rv.action || !Object.keys(rv.action).length) return null;
  return rv;
}

function putRiven(slot, props) {
  const rv = setRiven(props);
  if (!rv) return false;
  W.modsPanel[slot] = {
    name: 'Riven',
    actions: JSON.parse(JSON.stringify(rv.action)),
    tags: rv.tags,
    info: '',
  };
  W.invalidateModStatsCache();
  return true;
}

// 架势槽是 9。装了架势后，站点的连段命中表存在 actions.stances 里，
// 由 #stanceAttackList 当前选中项决定每次 10 秒窗口打几下。
function stanceList() {
  const cell = W.modsPanel[9];
  if (!cell || !cell.actions || !cell.actions.stances) return [];
  return Object.keys(cell.actions.stances);
}

function setStance(name) {
  const names = stanceList();
  const box = W.$('#stanceAttackList');
  box.empty();
  if (!names.length) return null;
  for (const n of names) box.append(W.$('<option>').attr('data-name', n).text(n));
  const pick = names.includes(name) ? name : names[0];
  const idx = names.indexOf(pick);
  box[0].selectedIndex = idx;
  W.__wfoptStanceCombo = pick;
  return pick;
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
  //
  // Keep this mapping identical to the site's options handler:
  //   optHeavy      -> comboСounterVal
  //   optMeleeCombo -> comboСounterSettingsVal.{is_set,val}
  // The earlier harness had these two controls reversed (and replaced the
  // settings object with a number), which made a local comparison request
  // unlike the actual website UI.  Reset these mutable globals on every run
  // because the kernel intentionally keeps one loaded website instance.
  w.combo_counterInitial = 11;
  w.combo_counter = 11;
  w.comboСounterVal = o.heavyStart != null ? Number(o.heavyStart) : 12;
  w.comboСounterSettingsVal = o.meleeCombo != null
    ? { is_set: true, val: Number(o.meleeCombo) }
    : { is_set: false, val: 12 };
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
  // 结果区取的是 currWeapon.info[攻击].queue_<层>（站点标作 "Random queue dps"）。
  // 注意生命层的字段名是 queue_hp，不是 queue_health —— 后者不存在。
  const FIELD = { health: 'queue_hp', armor: 'queue_armor', shield: 'queue_shield', overguard: 'queue_overguard' };
  for (const name of Object.keys(info)) {
    const it = info[name] || {};
    const row = { name, l: loc(name), dps: {}, ttk: {}, total: {} };
    for (const d of ['health', 'armor', 'shield', 'overguard']) {
      const v = it[FIELD[d]];
      if (v != null && isFinite(v) && v > 0) row.dps[d] = Math.round(v);
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

  const lost = applyMods(req.mods, req.riven);
  const lostIncarnon = applyIncarnon(req.incarnon || req.incarnonPerks);
  applyOpts(req.opts);
  applyCustom(req.custom);
  const combinedAttacks = applyCombinedAttacks(req.combinedAttacks);
  W.invalidateModStatsCache();

  // 近战：架势决定连段命中数，必须在 reCalc 之前选好。
  const stances = stanceList();
  const stance = stances.length ? setStance(req.stance) : null;

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
    queueLen: W.queueLength,
    combinedAttacks,
    stances,
    stance,
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
    lostIncarnon,
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

module.exports = {
  boot, calc, weapons, enemies, mods, weaponInfo, rivenAttrs, loc,
  customAttrs: () => CUSTOM_ATTR.map(a => ({ k: a.k, n: a.n, l: a.l, pct: a.pct })),
  get W() { return W; },
};
