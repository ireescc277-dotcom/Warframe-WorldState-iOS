'use strict';
// 前端：只负责选择与展示。所有数值来自服务端 kernel.js（站点本体脚本）。
//
// 状态 S 的形状就是 /api/calc 的请求体：
//   {weapon, enemy, level, steel, eximus, party, mods:{"0":"Serration"}, opts:{...}}
// mods 的键是站点的槽位号，武器 0-10、战甲 11-17 / 23-27，同一个字典。

const $ = id => document.getElementById(id);
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const S = {
  weapon: null,
  wmeta: null,
  enemy: null,
  level: 100,
  steel: false,
  eximus: false,
  party: 1,
  mods: {},        // slot -> mod 英文名（计算只认英文名）
  stance: null,    // 近战架势招式（架势 mod 装在 9 号槽）
  riven: [],       // 紫卡四条属性 [{p:'crit_chance', v:120}]，对应 mods 里的 'Riven'
  custom: [],      // 自定义属性 [{k:'base', v:50}]
  opts: {
    strength: 100, headshot: false, stealth: false, allConds: true,
    heavy: false, heavyStart: 12, meleeCombo: 12,
    abilityCombo: null, sniperCombo: null,
    virus: { on: false, stacks: 10 },
    rhino: null, mirage: null, xata: null, tlash: null, nourish: null, flatCrit: null,
    armor: null, statusCount: null, perStatusMul: false, madurai: false,
    queueLength: 20,
  },
};

let META = { weapons: [], enemies: [] };
let MOD_LOC = {};        // 英文名 -> 中文名，列表用
let LAST = null;
let CALC_SEQ = 0;
let CALC_T = 0;

// ---------------------------------------------------------------- 数字

function fmt(v) {
  if (v == null || !isFinite(v)) return '—';
  const n = Math.abs(v);
  if (n >= 1e9) return (v / 1e9).toFixed(2) + 'G';
  if (n >= 1e6) return (v / 1e6).toFixed(2) + 'M';
  if (n >= 1e4) return Math.round(v / 1e3) + 'k';
  if (n >= 1000) return (v / 1e3).toFixed(2) + 'k';
  if (n >= 10) return Math.round(v).toLocaleString('en-US');
  return (Math.round(v * 100) / 100).toString();
}
const fmtT = v => (v == null || !isFinite(v)) ? '—' : (v < 1 ? v.toFixed(2) : v.toFixed(1)) + 's';
const modName = n => n === 'Riven' ? '紫卡' : (MOD_LOC[n] || n);

// ---------------------------------------------------------------- 启动

async function boot() {
  META = await WFK.meta();
  $('wcount').textContent = META.weapons.length + ' 把';
  $('ecount').textContent = META.enemies.length + ' 个';
  const factions = [...new Set(META.enemies.map(e => e.faction))];
  $('fchips').innerHTML = `<button class="fchip on" data-f="">全部</button>` +
    factions.map(f => `<button class="fchip" data-f="${esc(f)}">${esc(factionName(f))}</button>`).join('');
  renderOpts();
  bindPick();
  bindFrame();
  bindHeader();

  const first = META.weapons.find(w => w.n === 'Torid') || META.weapons[0];
  await setWeapon(first.n);
  setEnemy(META.enemies.find(e => e.name === 'Heavy Gunner') || META.enemies[0]);
}

const factionName = f => {
  const e = META.enemies.find(x => x.faction === f);
  return (e && e.faction_l) || f;
};

// ---------------------------------------------------------------- 武器

async function setWeapon(name) {
  if (S.weapon !== name) { S.stance = null; S.mods = {}; S.riven = []; }
  S.weapon = name;
  const wj = await WFK.weaponInfo(name);
  if (!wj) return;
  S.wmeta = wj;
  const meta = META.weapons.find(w => w.n === name) || {};
  S.wmeta.l = meta.l || name;
  $('wsearch').placeholder = S.wmeta.l;
  $('wsearch').value = '';
  $('wcount').textContent = S.wmeta.l;
  renderWCard();
  renderSlots();
  calc();
}

function renderWCard() {
  const w = S.wmeta;
  if (!w) return;
  const atk = (w.attacks || [])[0] || {};
  const dmg = atk.damage || {};
  const total = Object.values(dmg).reduce((a, b) => a + b, 0);
  const parts = Object.keys(dmg).map(k => `${DTYPE[k] || k} ${Math.round(dmg[k])}`).join(' · ');
  $('wcard').innerHTML = `
    <div class="wname">${esc(w.l || w.name)}<span class="wcat">${esc(CAT[w.category] || w.category || '')}</span></div>
    <div class="wrow"><span>攻击段</span><b>${(w.attacks || []).map(a => esc(a.name)).join(' · ')}</b></div>
    <div class="wrow"><span>基础伤害</span><b>${Math.round(total)}</b></div>
    <div class="wrow"><span>伤害类型</span><b class="sm">${esc(parts || '—')}</b></div>
    <div class="wrow"><span>暴击</span><b>${(atk.crit_chance || 0)}% ×${(atk.crit_mult || 1)}</b></div>
    <div class="wrow"><span>触发</span><b>${(atk.status_chance || 0)}%</b></div>
    <div class="wrow"><span>射速</span><b>${(atk.speed || 0)}/s</b></div>
    <div class="wrow"><span>弹匣</span><b>${w.magazineSize || '—'}${w.incarnon ? ' / 灵化 ' + (w.incMagazineSize || '?') : ''}</b></div>`;
}

const CAT = { Primary: '主武器', Secondary: '副武器', Melee: '近战', ArchGun: 'Archwing 枪械' };
const DTYPE = { impact: '冲击', puncture: '穿刺', slash: '切割', heat: '火焰', cold: '冰冻', electricity: '电击', toxin: '毒素', blast: '爆炸', radiation: '辐射', gas: '毒气', magnetic: '磁力', viral: '病毒', corrosive: '腐蚀', void: '虚空' };

function renderWList(filter, cat) {
  const q = (filter || '').toLowerCase();
  const list = META.weapons
    .filter(w => (!cat || w.cat === cat) && (!q || (w.l || '').toLowerCase().includes(q) || w.n.toLowerCase().includes(q)))
    .slice(0, 300);
  const cats = [...new Set(META.weapons.map(w => w.cat))].filter(Boolean);
  $('wlist').innerHTML =
    `<div class="fchips">${['', ...cats].map(c =>
      `<button class="fchip${(c || '') === (cat || '') ? ' on' : ''}" data-c="${esc(c)}">${esc(c ? (CAT[c] || c) : '全部')}</button>`).join('')}</div>` +
    `<div class="wlistbody">${list.map(w =>
      `<div class="lrow" data-w="${esc(w.n)}"><span class="ln">${esc(w.l || w.n)}</span><span class="lt">${esc(CAT[w.cat] || w.cat || '')}</span></div>`).join('') ||
      '<div class="lrow dim">没有匹配</div>'}</div>`;
}

function bindPick() {
  const wi = $('wsearch'), wl = $('wlist'), wp = $('pick-w');
  wi.addEventListener('focus', () => { wl.classList.add('on'); renderWList('', ''); });
  wi.addEventListener('input', () => renderWList(wi.value, ''));
  wl.addEventListener('mousedown', e => {
    const f = e.target.closest('.fchip');
    if (f) { renderWList(wi.value, f.dataset.c); return; }
    const row = e.target.closest('[data-w]');
    if (row) { wl.classList.remove('on'); wi.blur(); setWeapon(row.dataset.w); }
  });
  document.addEventListener('mousedown', e => {
    if (!wp.contains(e.target)) wl.classList.remove('on');
  });

  const ei = $('esearch'), el = $('elist'), ep = $('pick-t');
  ei.addEventListener('focus', () => { el.classList.add('on'); renderEList('', ep.dataset.f || ''); });
  ei.addEventListener('input', () => renderEList(ei.value, ep.dataset.f || ''));
  $('fchips').addEventListener('mousedown', e => {
    const f = e.target.closest('.fchip');
    if (!f) return;
    ep.dataset.f = f.dataset.f;
    [...$('fchips').children].forEach(b => b.classList.toggle('on', b === f));
    renderEList(ei.value, f.dataset.f);
  });
  $('elistbody').addEventListener('mousedown', e => {
    const row = e.target.closest('[data-e]');
    if (!row) return;
    el.classList.remove('on'); ei.blur();
    setEnemy(META.enemies.find(x => x.name === row.dataset.e));
  });
  document.addEventListener('mousedown', e => {
    if (!ep.contains(e.target)) el.classList.remove('on');
  });

  const lr = $('lvl-range'), ln = $('lvl-num');
  lr.addEventListener('input', () => { ln.value = lr.value; S.level = +lr.value; calc(); });
  ln.addEventListener('change', () => {
    const v = Math.max(1, Math.min(9999, +ln.value || 1));
    ln.value = v; lr.value = Math.min(200, v); S.level = v; calc();
  });
}

function renderEList(filter, faction) {
  const q = (filter || '').toLowerCase();
  const list = META.enemies
    .filter(e => (!faction || e.faction === faction) &&
      (!q || (e.l || '').toLowerCase().includes(q) || e.name.toLowerCase().includes(q)))
    .slice(0, 400);
  $('elistbody').innerHTML = list.map(e =>
    `<div class="lrow" data-e="${esc(e.name)}"><span class="ln">${esc(e.l || e.name)}</span><span class="lt">${esc(e.faction_l || e.faction)}</span></div>`).join('') ||
    '<div class="lrow dim">没有匹配</div>';
}

function setEnemy(e) {
  if (!e) return;
  S.enemy = e;
  $('esearch').placeholder = e.l || e.name;
  $('esearch').value = '';
  $('ecount').textContent = e.l || e.name;
  $('tname').innerHTML = `${esc(e.l || e.name)}<span class="wcat">${esc(e.faction_l || e.faction)}</span>`;
  renderEnemyFlags();
  renderEnemyStats(null);
  calc();
}

// 钢铁 / 卓越者 / 队伍人数都是这个敌人的属性，放在敌人卡里。
function renderEnemyFlags() {
  const e = S.enemy;
  if (!e) return;
  const bits = [`<label class="tflag"><input type="checkbox" id="f-steel"${S.steel ? ' checked' : ''}><span>钢铁之路</span></label>`];
  if (!e.eximusOff) {
    bits.push(`<label class="tflag"><input type="checkbox" id="f-eximus"${S.eximus ? ' checked' : ''}><span>卓越者</span></label>`);
  }
  if (e.party) {
    bits.push(`<label class="tflag"><input type="number" id="f-party" class="num" min="1" max="4" value="${S.party}"><span>队伍人数</span></label>`);
  }
  $('tflags').innerHTML = bits.join('');

  const s = $('f-steel'), x = $('f-eximus'), p = $('f-party');
  s.onchange = () => { S.steel = s.checked; calc(); };
  if (x) x.onchange = () => { S.eximus = x.checked; calc(); };
  if (p) p.onchange = () => {
    S.party = Math.max(1, Math.min(4, +p.value || 1));
    p.value = S.party; calc();
  };

  $('tnote').innerHTML = e.unique
    ? '该敌人有独特的减伤机制，计算器未必完全覆盖。'
    : '';
}

// 等级缩放后的血量只有内核知道，先按基础值显示，算完再刷新
function renderEnemyStats(target) {
  const e = S.enemy;
  if (!e) return;
  const hp = target ? target.hp : e.hp;
  const ar = target ? target.ar : e.ar;
  const sh = target ? target.sh : e.sh;
  const og = target ? target.og : 0;
  $('estat').innerHTML = `
    <div><span>生命</span><b>${fmt(hp)}</b></div>
    <div><span>护甲</span><b>${fmt(ar)}</b></div>
    <div><span>护盾</span><b>${fmt(sh)}</b></div>
    ${og ? `<div><span>超宏</span><b>${fmt(og)}</b></div>` : ''}`;
  const fac = target && target.fac;
  $('facres').innerHTML = fac
    ? '弱点 ' + Object.entries(fac).map(([k, v]) => `${esc(DTYPE[k.toLowerCase()] || k)} ×${(+v).toFixed(2)}`).join(' · ')
    : '';
}

// ---------------------------------------------------------------- 武器槽位

function slotDefs() {
  const w = S.wmeta || {};
  const melee = (w.category || '') === 'Melee';
  const out = [];
  for (let i = 0; i < 8; i++) out.push({ id: i, kind: 'main', label: 'Mod' });
  out.push({ id: 8, kind: 'exilus', label: '功能' });
  if (melee) out.push({ id: 9, kind: 'stance', label: '架势' });
  out.push({ id: 10, kind: 'arcane', label: '赋能' });
  return out;
}

const KIND_NAME = { main: '普通', exilus: '功能', stance: '架势', arcane: '武器赋能', frame: '战甲 Mod', frameArcane: '战甲赋能', aura: '光环', shard: '执政官碎片' };

function slotHTML(d) {
  const m = S.mods[d.id];
  return `<button class="slot${m ? ' has' : ''}" data-slot="${d.id}" data-kind="${d.kind}">
    <span class="sk">${d.label}</span>
    <span class="sn">${m ? esc(modName(m)) : '＋'}</span>
    ${m ? '<span class="sx" data-del="' + d.id + '">×</span>' : ''}
  </button>`;
}

function renderSlots() {
  const defs = slotDefs();
  $('slots').innerHTML = defs.map(slotHTML).join('');
  const w = S.wmeta || {};
  const used = defs.filter(d => S.mods[d.id]).length;
  $('wside').innerHTML = `
    <div class="sidehd">配卡</div>
    <div class="srow"><span>已装</span><b>${used} / ${defs.length}</b></div>
    <div class="srow"><span>灵化</span><b>${w.incarnon ? '有' : '无'}</b></div>
    <div class="srow"><span>兼容</span><b class="sm">${(w.compTags || []).map(t => esc(t)).join(' / ') || '—'}</b></div>
    <div id="stbox"></div>`;
  renderFrame();
  if (LAST) renderStanceBox(LAST);
}

// 近战装架势后，连段里打哪一套由招式决定，命中数不同、DPS 不同。
function renderStanceBox(d) {
  const box = $('stbox');
  if (!box) return;
  const list = d.stances || [];
  if (!list.length) { box.innerHTML = ''; return; }
  box.innerHTML = `<div class="srow strow"><span>招式</span>
    <select id="stsel">${list.map(n => `<option${n === d.stance ? ' selected' : ''}>${esc(n)}</option>`).join('')}</select>
  </div>`;
  $('stsel').onchange = e => { S.stance = e.target.value; calc(); };
}

// ---------------------------------------------------------------- 战甲

const FRAME_DEFS = [
  { id: 17, kind: 'aura', label: '光环', g: 'aura' },
  { id: 13, kind: 'frame', label: '战甲', g: 'mod' },
  { id: 14, kind: 'frame', label: '战甲', g: 'mod' },
  { id: 15, kind: 'frame', label: '战甲', g: 'mod' },
  { id: 16, kind: 'frame', label: '战甲', g: 'mod' },
  { id: 11, kind: 'frameArcane', label: '赋能', g: 'arcane' },
  { id: 12, kind: 'frameArcane', label: '赋能', g: 'arcane' },
  { id: 23, kind: 'shard', label: '碎片', g: 'shard' },
  { id: 24, kind: 'shard', label: '碎片', g: 'shard' },
  { id: 25, kind: 'shard', label: '碎片', g: 'shard' },
  { id: 26, kind: 'shard', label: '碎片', g: 'shard' },
  { id: 27, kind: 'shard', label: '碎片', g: 'shard' },
];

function renderFrame() {
  const groups = [
    { n: '光环', list: FRAME_DEFS.filter(d => d.g === 'aura') },
    { n: '战甲 Mod', list: FRAME_DEFS.filter(d => d.g === 'mod') },
    { n: '战甲赋能', list: FRAME_DEFS.filter(d => d.g === 'arcane') },
    { n: '执政官碎片', list: FRAME_DEFS.filter(d => d.g === 'shard') },
  ];
  $('frbody').innerHTML = groups.map(g =>
    `<div class="frg"><div class="frgh">${g.n}</div><div class="frgl">${g.list.map(slotHTML).join('')}</div></div>`).join('');
  const used = FRAME_DEFS.filter(d => S.mods[d.id]).length;
  $('fr-count').textContent = used ? `${used} / ${FRAME_DEFS.length}` : '';
}

function bindFrame() {
  $('fr-toggle').onclick = () => {
    const on = $('frame').classList.toggle('open');
    $('fr-toggle').setAttribute('aria-expanded', on ? 'true' : 'false');
  };
  $('frame').classList.add('open');
}

// 槽位点击（武器与战甲共用）
document.addEventListener('click', e => {
  const del = e.target.closest('[data-del]');
  if (del) {
    e.stopPropagation();
    delete S.mods[+del.dataset.del];
    renderSlots(); calc();
    return;
  }
  const b = e.target.closest('[data-slot]');
  if (b) openModPicker(+b.dataset.slot, b.dataset.kind);
});

// ---------------------------------------------------------------- 选卡

const PICK = { slot: null, all: [] };

async function openModPicker(slot, kind) {
  PICK.slot = slot;
  $('modal').classList.add('on');
  $('m-title').style.display = '';
  $('m-title').textContent = `槽位 ${slot} · ${KIND_NAME[kind] || kind}`;
  $('m-search').style.display = '';
  $('m-foot').innerHTML = `<button class="mbtn" id="m-riven">紫卡…</button><button class="mbtn" id="m-clear">卸下</button>`;
  $('m-list').innerHTML = '<div class="lrow dim">载入…</div>';
  $('m-search').value = '';
  $('m-riven').onclick = () => openRiven(slot);
  $('m-clear').onclick = () => {
    delete S.mods[slot];
    if (!Object.values(S.mods).includes('Riven')) S.riven = [];
    closeModal(); renderSlots(); calc();
  };
  const r = await WFK.boot();
  PICK.all = WFK.modsFor(S.weapon, slot) || [];
  for (const m of PICK.all) if (m.l && m.l !== m.n) MOD_LOC[m.n] = m.l;
  renderModList('');
  $('m-search').focus();
}

function renderModList(q) {
  q = (q || '').toLowerCase();
  const used = new Set(Object.entries(S.mods).filter(([k]) => +k !== PICK.slot).map(([, v]) => v));
  const list = PICK.all.filter(m => !used.has(m.n) &&
    (!q || (m.l || '').toLowerCase().includes(q) || m.n.toLowerCase().includes(q)));
  $('m-list').innerHTML = list.map(m => {
    const act = m.act && typeof m.act === 'object'
      ? Object.keys(m.act).filter(k => typeof m.act[k] === 'number')
          .map(k => `${STATN[k] || k} ${m.act[k] > 0 ? '+' : ''}${Math.round(m.act[k] * 1000) / 10}%`).slice(0, 3).join(' · ')
      : '';
    return `<div class="mrow" data-m="${esc(m.n)}">
      <div class="mn">${esc(modName(m.n))}${m.l && m.l !== m.n ? `<span class="men">${esc(m.n)}</span>` : ''}</div>
      <div class="ma">${esc(act || m.info || '')}</div>
    </div>`;
  }).join('') || '<div class="lrow dim">没有匹配</div>';
}

const STATN = {
  base: '伤害', crit_chance: '暴击率', crit_mult: '暴击倍率', status_chance: '触发率',
  multishot: '多重', speed: '射速', reload: '装填', magazine: '弹匣', status_dur: '状态持续',
  heat: '火焰', cold: '冰冻', electricity: '电击', toxin: '毒素', slash: '切割',
  impact: '冲击', puncture: '穿刺', combo: '连击', range: '范围', ammoEff: '弹药效率',
};

// ---------------------------------------------------------------- 自定义属性

let CST_ATTRS = [];

async function openCustom() {
  $('modal').classList.add('on');
  $('m-title').style.display = '';
  $('m-title').textContent = '自定义属性 · 面板外加成';
  $('m-search').style.display = 'none';
  $('m-list').innerHTML = '<div class="lrow dim">载入…</div>';
  if (!CST_ATTRS.length) {
    CST_ATTRS = WFK.customAttrs();
  }
  const cur = Object.fromEntries((S.custom || []).map(x => [x.k, x.v]));
  $('m-list').innerHTML = `<div class="cst">${CST_ATTRS.map(a => `
    <div class="cstrow${cur[a.k] ? ' on' : ''}">
      <label title="${esc(a.n)}">${esc(a.l)}${a.pct ? ' %' : ''}</label>
      <input type="number" step="0.1" data-k="${a.k}" value="${cur[a.k] != null ? cur[a.k] : ''}" placeholder="0">
    </div>`).join('')}</div>`;
  $('m-list').querySelectorAll('.cstrow input').forEach(inp => {
    inp.oninput = () => inp.closest('.cstrow').classList.toggle('on', !!Number(inp.value));
  });
  $('m-foot').innerHTML = `<button class="mbtn" id="cst-ok">应用</button><button class="mbtn" id="cst-reset">清空</button>`;
  $('cst-reset').onclick = () => {
    $('m-list').querySelectorAll('.cstrow input').forEach(i => { i.value = ''; i.closest('.cstrow').classList.remove('on'); });
  };
  $('cst-ok').onclick = () => {
    const out = [];
    $('m-list').querySelectorAll('.cstrow input').forEach(i => {
      const v = Number(i.value);
      if (i.value !== '' && isFinite(v) && v !== 0) out.push({ k: i.dataset.k, v });
    });
    S.custom = out;
    $('cst-n').textContent = out.length ? `${out.length} 项` : '';
    closeModal(); calc();
  };
}

$('m-search').addEventListener('input', e => renderModList(e.target.value));

// ---------------------------------------------------------------- 紫卡
//
// 站点把紫卡当作临时构造的 mod（modsProps[9999]），不在 mod 表里。
// 这里只收集 4 条属性，服务端按它自己的换算（百分比/倍数/秒）喂给内核。

let RIVEN_ATTRS = [];

async function openRiven(slot) {
  $('m-title').textContent = '紫卡 · 4 条属性';
  $('m-search').style.display = 'none';
  $('m-list').innerHTML = '<div class="lrow dim">载入…</div>';
  if (!RIVEN_ATTRS.length) {
    RIVEN_ATTRS = WFK.rivenAttrs(((S.wmeta && S.wmeta.category) || '') === 'Melee');
  }
  const cur = S.mods[slot] === 'Riven' ? (S.riven || []) : [];
  const opts = k => `<option value="">—</option>` +
    RIVEN_ATTRS.map(a => `<option value="${a.k}"${a.k === k ? ' selected' : ''}>${esc(a.l)}</option>`).join('');
  $('m-list').innerHTML = `<div class="rvt">${[0, 1, 2, 3].map(i => {
    const it = cur[i] || {};
    return `<div class="rvrow">
      <select class="rvp" data-i="${i}">${opts(it.p)}</select>
      <input class="rvv" data-i="${i}" type="number" step="0.1" placeholder="值" value="${it.v != null ? it.v : ''}">
      <span class="rvu" data-u="${i}"></span>
    </div>`;
  }).join('')}</div>
  <div class="rvnote">百分数填 60；派系写倍数填 1.5；连击持续 / 范围 / 穿透填秒数或米数。至少填一条。</div>`;

  const syncUnit = () => {
    $('m-list').querySelectorAll('.rvp').forEach(s => {
      const it = RIVEN_ATTRS.find(a => a.k === s.value);
      const u = $('m-list').querySelector(`.rvu[data-u="${s.dataset.i}"]`);
      if (u) u.textContent = it ? ({ '%': '%', x: '倍', s: '值' }[it.u] || '') : '';
    });
  };
  $('m-list').querySelectorAll('.rvp').forEach(s => { s.onchange = syncUnit; });
  syncUnit();

  $('m-foot').innerHTML = `<button class="mbtn" id="rv-ok">装备紫卡</button><button class="mbtn" id="m-clear">卸下</button>`;
  $('m-clear').onclick = () => {
    delete S.mods[slot];
    if (!Object.values(S.mods).includes('Riven')) S.riven = [];
    closeModal(); renderSlots(); calc();
  };
  $('rv-ok').onclick = () => {
    const out = [];
    $('m-list').querySelectorAll('.rvp').forEach(s => {
      const v = +$('m-list').querySelector(`.rvv[data-i="${s.dataset.i}"]`).value;
      if (s.value && isFinite(v) && v !== 0) out.push({ p: s.value, v });
    });
    if (!out.length) { banner('紫卡至少填一条属性'); return; }
    // 紫卡只能装一张
    for (const k of Object.keys(S.mods)) if (S.mods[k] === 'Riven') delete S.mods[k];
    S.riven = out;
    S.mods[slot] = 'Riven';
    closeModal(); renderSlots(); calc();
  };
}
$('m-close').onclick = closeModal;
$('modal').addEventListener('mousedown', e => { if (e.target === $('modal')) closeModal(); });
$('m-list').addEventListener('click', e => {
  const r = e.target.closest('[data-m]');
  if (!r) return;
  S.mods[PICK.slot] = r.dataset.m;
  closeModal(); renderSlots(); calc();
});
function closeModal() { $('modal').classList.remove('on'); }

// ---------------------------------------------------------------- 条件

// 站点 optionsPanel 的控件，逐项对应。
const OPTS = [
  { k: 'virus', g: '通用', n: '外部病毒', t: 'chknum', min: 0, max: 10, def: 10, u: '层' },
  { k: 'strength', g: '通用', n: '技能强度', t: 'num', min: 0, max: 1000, def: 100, u: '%' },
  { k: 'headshot', g: '通用', n: '爆头 / 弱点命中', t: 'chk' },
  { k: 'armor', g: '通用', n: '外部削甲', t: 'chknum', min: 0, max: 99, def: 50, u: '%' },
  { k: 'statusCount', g: '通用', n: '手动指定敌人状态总数', t: 'chknum', min: 1, max: 50, def: 1, u: '个' },
  { k: 'perStatusMul', g: '通用', n: '「每状态增伤」按乘算（异况超量）', t: 'chk' },
  { k: 'allConds', g: '通用', n: '所有 Mod 条件默认满足', t: 'chk' },
  { k: 'queueLength', g: '通用', n: '连续射击 / 攻击时长', t: 'num', min: 1, max: 60, def: 20, u: '秒' },

  { k: 'stealth', g: '近战', n: '潜行加成', t: 'chk' },
  { k: 'heavy', g: '近战', n: '重击（从第几段起算）', t: 'chknum', min: 1, max: 13, def: 12, u: 'x' },
  { k: 'meleeCombo', g: '近战', n: '轻击连击倍率', t: 'chknum', min: 1, max: 13, def: 12, u: 'x' },
  { k: 'abilityCombo', g: '近战', n: '技能连击倍率', t: 'chknum', min: 1, max: 12, def: 12, u: 'x' },
  { k: 'sniperCombo', g: '远程', n: '狙击连击倍率', t: 'chknum', min: 1.5, max: 100, def: 1.5, u: 'x' },

  { k: 'rhino', g: '战甲 Buff', n: '战吼（Rhino）', t: 'chknum', min: 1, max: 9999, def: 30, u: '%' },
  { k: 'mirage', g: '战甲 Buff', n: '黯然失色（Mirage）', t: 'chknum', min: 1, max: 9999, def: 30, u: '%' },
  { k: 'xata', g: '战甲 Buff', n: '真理密语（Xaku）', t: 'chknum', min: 1, max: 9999, def: 26, u: '%' },
  { k: 'tlash', g: '战甲 Buff', n: '剧毒鞭笞（Saryn）', t: 'chknum', min: 1, max: 9999, def: 30, u: '%' },
  { k: 'nourish', g: '战甲 Buff', n: '消化滋养（Grendel）', t: 'chknum', min: 1, max: 9999, def: 45, u: '%' },
  { k: 'flatCrit', g: '战甲 Buff', n: '绝对暴击几率（Kullervo / Harrow）', t: 'chknum', min: 1, max: 9999, def: 50, u: '%' },
  { k: 'madurai', g: '战甲 Buff', n: 'Madurai 物理伤害 +30%', t: 'chk' },
];

// 勾选值为 null 表示关；数值型在勾上时取上次的值
function isOn(o) {
  const v = S.opts[o.k];
  if (o.k === 'allConds') return S.opts.allConds !== false;
  if (o.k === 'virus') return !!S.opts.virus.on;
  if (o.t === 'num') return true;
  return v != null && v !== false;
}

function optVal(o) {
  if (o.k === 'virus') return S.opts.virus.stacks;
  if (o.k === 'heavy') return S.opts.heavyStart != null ? S.opts.heavyStart : o.def;
  const v = S.opts[o.k];
  return typeof v === 'number' ? v : o.def;
}

function optRow(o) {
  const checked = isOn(o) ? ' checked' : '';
  const val = optVal(o);
  const num = o.t === 'chk' ? '' :
    `<input class="num" data-kn="${o.k}" type="number" min="${o.min}" max="${o.max}"
      step="${o.max <= 20 ? 0.1 : 1}" value="${val}"${isOn(o) ? '' : ' disabled'}><span class="pc">${o.u || ''}</span>`;
  if (o.t === 'num') {
    return `<div class="orow"><span class="lb2">${o.n}</span>
      <input type="range" data-kr="${o.k}" min="${o.min}" max="${o.max}" step="1" value="${val}">${num}</div>`;
  }
  if (o.t === 'chk') {
    return `<label class="orow chk"><input type="checkbox" data-k="${o.k}"${checked}><span>${o.n}</span></label>`;
  }
  return `<div class="orow"><label class="ck"><input type="checkbox" data-k="${o.k}"${checked}>
    <span>${o.n}</span></label>${num}</div>`;
}

function renderOpts() {
  const groups = [];
  for (const o of OPTS) {
    let g = groups.find(x => x.n === o.g);
    if (!g) groups.push(g = { n: o.g, list: [] });
    g.list.push(o);
  }
  $('optgroups').innerHTML = groups.map(g =>
    `<div class="og"><div class="ogh">${g.n}</div>${g.list.map(optRow).join('')}</div>`).join('');
  bindOpts();
  syncOptCount();
}

function bindOpts() {
  for (const o of OPTS) {
    const box = document.querySelector(`[data-k="${o.k}"]`);
    const inp = document.querySelector(`[data-kn="${o.k}"]`);
    const rng = document.querySelector(`[data-kr="${o.k}"]`);
    if (box) {
      box.onchange = () => {
        if (o.k === 'allConds') {
          S.opts.allConds = box.checked;
        } else if (o.k === 'virus') {
          S.opts.virus.on = box.checked;
        } else if (o.t === 'chk') {
          S.opts[o.k] = box.checked ? true : null;
        } else {
          // chknum：关掉写 null，打开恢复上次值或默认
          S.opts[o.k] = box.checked ? (o.k === 'heavy' ? (S.opts.heavyStart || o.def) : o.def) : null;
        }
        if (inp) inp.disabled = !box.checked;
        if (rng) rng.disabled = !box.checked;
        syncOptCount(); calc();
      };
    }
    const numHandler = () => {
      let v = parseFloat(inp.value);
      if (!isFinite(v)) v = o.def;
      v = Math.max(o.min, Math.min(o.max, v));
      if (o.k === 'virus') S.opts.virus.stacks = v;
      else if (o.k === 'heavy') S.opts.heavyStart = v;
      else S.opts[o.k] = v;
      if (rng) rng.value = v;
      syncOptCount(); calc();
    };
    if (inp) inp.oninput = numHandler;
    if (rng) rng.oninput = () => { inp.value = rng.value; numHandler(); };
  }
}

const OPT_SKIP = new Set(['strength', 'queueLength', 'allConds']);
function syncOptCount() {
  const n = OPTS.filter(o => isOn(o) && !OPT_SKIP.has(o.k)).length;
  $('opt-n').textContent = n || '';
}

// ---------------------------------------------------------------- 计算

function calc() {
  if (!S.weapon || !S.enemy) return;
  clearTimeout(CALC_T);
  const seq = ++CALC_SEQ;
  CALC_T = setTimeout(async () => {
    const body = {
      weapon: S.weapon, enemy: S.enemy.name, level: S.level,
      steel: S.steel, eximus: S.eximus, party: S.party,
      stance: S.stance,
      riven: S.riven,
      custom: S.custom,
      mods: S.mods, opts: S.opts,
    };
    try {
      const d = await WFK.calc(body);
      if (seq !== CALC_SEQ) return;
      if (d.error) { banner(d.error); return; }
      LAST = d;
      renderResult(d);
    } catch (e) {
      banner('计算失败：' + e.message);
    }
  }, 120);
}

const DT = { health: '生命', armor: '护甲', shield: '护盾', overguard: '超宏' };

function renderResult(d) {
  if (d.target) renderEnemyStats(d.target);
  renderStanceBox(d);
  const rows = d.attacks || [];
  if (!rows.length) {
    $('rbar').innerHTML = '<div class="empty">这个组合没有可算的攻击段</div>';
    $('attacks').innerHTML = '';
    return;
  }

  // 每条攻击段独立成账（站点口径）。不再另立“最高一段”这种自造指标。
  const tags = [`Lv${d.level} ${esc(S.enemy ? (S.enemy.l || S.enemy.name) : d.enemy)}`];
  if (d.steel) tags.push('钢铁之路');
  if (d.eximus) tags.push('卓越者');
  if (d.party > 1) tags.push(`${d.party} 人队`);
  $('rbar').innerHTML = `<div class="rline">
    <span class="rt">${tags.join(' · ')}</span>
    <span class="rs">${rows.length} 段攻击，各自独立计算</span>
  </div>`;

  $('attacks').innerHTML = rows.map(a => {
    const defs = Object.keys(a.dps);
    return `<div class="acard">
      <div class="ahd">${esc(a.l || a.name)}<span class="atag">${defs.length} 层</span></div>
      <table class="atab">
        <thead><tr><th>目标层</th><th>队列 DPS</th><th>每发中位</th><th>TTK</th></tr></thead>
        <tbody>${defs.map(k => `<tr>
          <td>${DT[k] || k}</td>
          <td class="num">${fmt(a.dps[k])}</td>
          <td class="num dim">${fmt(a.total[k])}</td>
          <td class="num">${(a.ttk[k] == null || a.ttk[k] >= (d.queueLen || 20) - 0.02) ? '<span class="dim">' + (d.queueLen || 20) + 's 内打不死</span>' : fmtT(a.ttk[k])}</td>
        </tr>`).join('')}</tbody>
      </table>
    </div>`;
  }).join('');
}

// ---------------------------------------------------------------- 头

function bindHeader() {
  $('btn-custom').onclick = openCustom;
  $('btn-note').onclick = () => {
    $('modal').classList.add('on');
    $('m-title').style.display = '';
    $('m-title').textContent = '口径';
    $('m-search').style.display = 'none';
    $('m-foot').innerHTML = '';
    $('m-list').innerHTML = `<div class="note">
      <p>所有数值由服务端运行 warframe-damage.com 的同一份脚本得出，不是本项目的独立实现。</p>
      <p>它把整个射击 / 攻击窗口按秒切分，逐发抽取暴击、触发、多重，再把每秒伤害取<b>中位数</b>作为 DPS。所以同一配置重复算会有小幅波动，这是它本来的行为。</p>
      <p>每段攻击独立成账：直击造成的状态不会被同一把武器的爆炸段看见。</p>
      <p>生命 / 护甲 / 护盾 / 超宏四层各按自己的抗性与减伤算，数值不能直接相加。</p>
    </div>`;
  };
}

// ---------------------------------------------------------------- 杂项

let BAN_T = 0;
function banner(msg) {
  const el = $('banner');
  el.textContent = msg;
  el.classList.add('on');
  clearTimeout(BAN_T);
  BAN_T = setTimeout(() => el.classList.remove('on'), 3000);
}

boot().catch(e => banner('启动失败：' + e.message));
