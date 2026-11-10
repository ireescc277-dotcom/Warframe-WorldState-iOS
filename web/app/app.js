'use strict';
// Warframe 伤害计算 · 前端
// 只做界面和状态，所有数值来自后端 /api/*；切换任何条件都重新请求一次。

const API = './api';

const ZH = {impact:'冲击',puncture:'穿刺',slash:'切割',heat:'火焰',cold:'冰冻',
  electricity:'电击',toxin:'毒素',blast:'爆炸',radiation:'辐射',magnetic:'磁力',
  viral:'病毒',corrosive:'腐蚀',gas:'毒气'};
const COL = {impact:'#9aa3ad',puncture:'#b98c5a',slash:'#c0504d',heat:'#e07a3f',
  cold:'#5fa8d3',electricity:'#8a6fd0',toxin:'#5aa06a',blast:'#c96f4a',
  radiation:'#c9c04a',magnetic:'#7f8fd0',viral:'#8fbf6a',corrosive:'#8fae4a',gas:'#7fae7f'};
const LABEL = {dmg:'伤害',cc:'暴击',cd:'暴伤',ms:'多重',fr:'射速',sc:'触发',
  mag:'弹匣',rl:'装填',sdur:'状态持续',sdm:'状态伤害',pt:'穿透',pspd:'弹丸速度',
  zoom:'缩放',impact:'冲击',puncture:'穿刺',slash:'切割',heat:'火焰',cold:'冰冻',
  electricity:'电击',toxin:'毒素',blast:'爆炸',radiation:'辐射',magnetic:'磁力',
  viral:'病毒',corrosive:'腐蚀',gas:'毒气',
  d_grineer:'对Grineer',d_corpus:'对Corpus',d_infested:'对Infested',
  d_corrupted:'对Orodin',d_narmer:'对Narmer',d_murmur:'对Murmur',d_sentient:'对Sentient'};
const INCLBL = {flatBaseDamage:'基础伤害+', additiveBaseDamage:'基础伤害×',
  criticalChance:'基础暴击', criticalMultiplier:'基础暴伤', criticalMultiplierSet:'暴伤设',
  critMultFlat:'暴伤+', statusChance:'基础触发', fireRate:'射速', reloadSpeed:'装填',
  magazine:'弹匣', flatMagazine:'弹匣+', multishot:'多重', projectileSpeed:'弹丸速度',
  range:'范围', recoil:'后坐', accuracy:'精度', punchThrough:'穿透',
  heavyAttackEfficiency:'重击效率', heavyAttackWindUp:'重击蓄力', comboDuration:'连击持续',
  initialCombo:'初始连击', headshotDamageBonus:'爆头伤害', devouringAttrition:'吞噬消耗',
  lastShotBaseMultishot:'末发多重', capacityMsDamageMult:'弹匣多重伤害'};
const TRIG_NOTE = {BURST:'连发：未建连发间隔', CHARGE:'蓄力：射速按蓄满计',
  DUPLEX:'双发：未建双发节奏', HELD:'持续：按连发计'};
const CAT = {LongGuns:'PRIMARY', Pistols:'SECONDARY', Melee:'MELEE',
  SentinelWeapons:'SENTINEL', SpaceGuns:'ARCH-GUN', SpaceMelee:'ARCH-MELEE'};
const FAC_ORDER = ['Grineer','Kuva Grineer','Corpus','Corpus Amalgam','Infested',
  'Infested Deimos','Orokin','Sentient','Narmer','Murmur','Scaldra','Techrot','Stalker','Neutral'];

const S = {
  meta: null, weapons: [], byUid: new Map(), enemies: [], factions: [],
  uid: null, weapon: null, slots: [], inc: null, cfg: 0,
  ei: 0, level: 100, fac: '全部',
  opt: {status: true, steel: false, extViral: 0, armorStrip: 0, window: 10,
        headshot: false, crit: true, incarnon: false, dmgBuff: 0, ccBuff: 0},
  mode: 'list', ranking: null, rankKey: '',
  mods: new Map(), view: null,
};

const $ = id => document.getElementById(id);
const STORE = 'wf.dps.v1';

function saveState() {
  try {
    localStorage.setItem(STORE, JSON.stringify({
      uid: S.uid, ei: S.ei, level: S.level, opt: S.opt, cfg: S.cfg,
    }));
  } catch (e) {}
}

function loadState() {
  try { return JSON.parse(localStorage.getItem(STORE) || 'null'); } catch (e) { return null; }
}
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g,
  c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

function fmt(n) {
  if (n == null || !isFinite(n)) return '—';
  if (n === 0) return '0';
  if (n >= 1e6) return (n / 1e6).toFixed(2) + 'M';
  if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k';
  return Math.round(n).toLocaleString('en-US');
}
const num = (v, d = 1) => Number(v).toFixed(d).replace(/\.?0+$/, '') || '0';

let banner_t = 0;
function banner(msg) {
  const el = $('banner');
  el.textContent = msg;
  el.classList.add('on');
  clearTimeout(banner_t);
  banner_t = setTimeout(() => el.classList.remove('on'), 5000);
}

let busyN = 0;
function busy(on) {
  busyN += on ? 1 : -1;
  if (busyN < 0) busyN = 0;
  $('busy').classList.toggle('on', busyN > 0);
}

async function api(path, body, signal) {
  const opt = {signal, headers: {}};
  if (body !== undefined) {
    opt.method = 'POST';
    opt.headers['Content-Type'] = 'application/json';
    opt.body = JSON.stringify(body);
  }
  const r = await fetch(API + path, opt);
  if (!r.ok) {
    let msg = 'HTTP ' + r.status;
    try { msg = (await r.json()).error || msg; } catch (e) {}
    throw new Error(msg);
  }
  return r.json();
}

// ---------------------------------------------------------------- 启动
async function boot() {
  try {
    const m = await api('/meta');
    S.meta = m.meta;
    S.weapons = m.weapons;
    S.weapons.forEach(w => S.byUid.set(w.uid, w));
    S.enemies = m.enemies;
    S.factions = m.factions;
    S.rivens = m.rivens || [];
    $('buildinfo').textContent = `数据 ${m.meta.builtAt.split(' ')[0]} · ${m.meta.weapons} 武器 / ${m.meta.builds} 套`;
    const saved = loadState();
    if (saved) {
      if (saved.opt) Object.assign(S.opt, saved.opt);
      if (Number.isFinite(saved.level)) {
        S.level = Math.max(1, Math.min(9999, saved.level));
        $('lvl-range').value = Math.min(200, S.level);
        $('lvl-num').value = S.level;
      }
      syncOptUI();
    }
    S.ei = (saved && Number.isFinite(saved.ei) && m.enemies[saved.ei]) ? saved.ei : pickEnemy();
    renderFacChips();
    renderEnemyList();
    renderWeaponList();
    const keep = !!(saved && S.byUid.has(saved.uid));
    if (keep && Number.isFinite(saved.cfg)) S.cfg = saved.cfg;
    const first = keep ? saved.uid : (S.weapons.find(w => w.e === 'Tenora Prime') || S.weapons[0]).uid;
    if (first) selectWeapon(first, keep);
    else $('bwrap').innerHTML = '<div class="empty">数据里没有带配卡的武器。</div>';
  } catch (e) {
    banner('后端连不上：' + e.message);
    $('bwrap').innerHTML = '<div class="empty">后端连不上，检查服务是否在跑。</div>';
  }
}

function pickEnemy() {
  const i = S.enemies.findIndex(e => e.n === 'Heavy Gunner');
  if (i >= 0) return i;
  const j = S.enemies.findIndex(e => e.f === 'Grineer');
  return j >= 0 ? j : 0;
}

// ---------------------------------------------------------------- 武器列表
function renderWeaponList() {
  const el = $('wlist');
  const q = $('wsearch').value.trim().toLowerCase();
  el.innerHTML = '';
  if (S.mode === 'rank') {
    $('wtitle').textContent = '排名';
    $('wcount').textContent = S.ranking ? S.ranking.length + ' 项' : '…';
    if (!S.ranking) { el.innerHTML = '<div class="empty">计算中…</div>'; return; }
    S.ranking.forEach((r, i) => {
      if (q && !r.n.toLowerCase().includes(q)) return;
      const d = document.createElement('div');
      d.className = 'item' + (r.uid === S.uid ? ' on' : '');
      d.innerHTML = `<div class="rank">${i + 1}</div><div class="nm">${esc(r.n)}</div>
        <div class="sub">${fmt(r.val)}</div>`;
      d.onclick = () => { setMode('list'); selectWeapon(r.uid); };
      el.appendChild(d);
    });
    return;
  }
  $('wtitle').textContent = '武器';
  $('wcount').textContent = S.weapons.length + ' 把';
  const frag = document.createDocumentFragment();
  for (const w of S.weapons) {
    if (q && !(w.n.toLowerCase().includes(q) || (w.e || '').toLowerCase().includes(q))) continue;
    const d = document.createElement('div');
    d.className = 'item' + (w.uid === S.uid ? ' on' : '');
    d.innerHTML = `<div class="nm">${esc(w.n)}</div>
      ${w.inc ? '<span class="tag inc">灵</span>' : ''}
      ${w.riven ? '<span class="tag">紫</span>' : ''}
      <div class="sub">${w.ncfg}</div>`;
    d.onclick = () => selectWeapon(w.uid);
    frag.appendChild(d);
  }
  el.appendChild(frag);
  const on = el.querySelector('.item.on');
  if (on) on.scrollIntoView({block: 'nearest'});
}

function setMode(m) {
  S.mode = m;
  $('btn-rank').classList.toggle('on', m === 'rank');
  $('btn-rank').textContent = m === 'rank' ? '列表' : '排名';
  if (m === 'rank') buildRanking();
  renderWeaponList();
}

async function buildRanking() {
  S.ranking = null;
  renderWeaponList();
  const key = JSON.stringify([S.ei, S.level, S.opt]);
  try {
    busy(true);
    const r = await api('/rank', {ei: S.ei, level: S.level, opt: S.opt});
    if (key !== JSON.stringify([S.ei, S.level, S.opt])) return;   // 条件已变
    S.ranking = r.rows;
    S.rankKey = key;
  } catch (e) {
    banner('排名失败：' + e.message);
  } finally {
    busy(false);
    renderWeaponList();
  }
}

// ---------------------------------------------------------------- 选中武器
async function selectWeapon(uid, keepCfg) {
  if (!uid) return;
  S.uid = uid;
  if (!keepCfg) S.cfg = 0;
  S.opt.incarnon = false;
  saveState();
  renderWeaponList();
  try {
    busy(true);
    const r = await api('/weapon?uid=' + encodeURIComponent(uid));
    S.weapon = r.weapon;
    S.inc = r.inc;
    S.allSlots = r.slots;
    S.cfg = Math.max(0, Math.min(S.cfg, r.slots.length - 1));
    S.slots = cloneSlots(r.slots[S.cfg]);
    renderBuild();
    calc();
  } catch (e) {
    banner('读取武器失败：' + e.message);
  } finally { busy(false); }
}

const cloneSlots = a => (a || []).map(s => (s ? {...s} : null));

// ---------------------------------------------------------------- 配卡面板
function renderBuild() {
  if (!S.weapon) return;
  const w = S.weapon;
  const b = $('bwrap');
  let html = `<div class="wtitle"><h2>${esc(w.z || w.n)}</h2><span class="en">${esc(w.n)}</span>`;
  if (S.inc && S.opt.incarnon) html += `<span class="pill inc">灵化形态</span>`;
  if (TRIG_NOTE[w.tr]) html += `<span class="pill">${TRIG_NOTE[w.tr]}</span>`;
  html += `</div><div class="wstats" id="wstats">${statsHtml(null)}</div>`;

  if (S.allSlots.length > 1) {
    html += '<div class="tabs">';
    S.allSlots.forEach((_, i) => {
      html += `<button data-ci="${i}" class="${i === S.cfg ? 'on' : ''}">配置 ${'ABC'[i] || i + 1}</button>`;
    });
    html += '</div>';
  }
  html += `<div class="slots" id="slots"></div>`;
  if (S.inc) {
    html += `<div class="sec" id="incpane">
      <div class="sechd"><span>灵化 · ${esc(S.inc.name)}</span>
        <span class="seg">
          <button data-v="0" class="${S.opt.incarnon ? '' : 'on'}">普通形态</button>
          <button data-v="1" class="${S.opt.incarnon ? 'on' : ''}">灵化形态</button>
        </span></div>
      <div id="inclist"></div>
      <div class="hint">节点数值加在基础值上，再走 mod 乘算；基础伤害类只在灵化形态生效。</div>
    </div>`;
  }
  html += `<div class="sec"><div class="sechd"><span>配卡明细</span></div>
    <div class="contrib" id="contrib"><div class="hint">—</div></div></div>`;
  html += `<div class="sec" id="simpane"></div>`;
  b.innerHTML = html;

  const slotsEl = $('slots');
  S.slots.forEach((s, i) => slotsEl.appendChild(slotEl(s, i)));

  b.querySelectorAll('.tabs button').forEach(btn => {
    btn.onclick = () => {
      S.cfg = +btn.dataset.ci;
      S.slots = cloneSlots(S.allSlots[S.cfg]);
      renderBuild(); calc();
    };
  });
  if (S.inc) {
    b.querySelectorAll('#incpane .seg button').forEach(btn => {
      btn.onclick = () => { S.opt.incarnon = btn.dataset.v === '1'; renderBuild(); calc(); };
    });
    renderIncList();
  }
}

function statsHtml(v) {
  const w = v ? v.weapon : (S.weapon || {});
  const rows = [
    ['基伤', num(w.td || 0, 1)],
    ['暴击', ((w.cc || 0) * 100).toFixed(0) + '% / ' + (w.cm || 1).toFixed(1) + '×'],
    ['触发', ((w.sc || 0) * 100).toFixed(1) + '%'],
    ['射速', (w.fr || 0).toFixed(2)],
    ['弹匣', w.mag || 0],
    ['装填', (w.rl || 0).toFixed(2) + 's'],
    ['多重', num(w.ms || 1, 2)],
  ];
  let h = rows.map(([k, v]) => `<div>${k} <b>${v}</b></div>`).join('');
  if (w.cat) h += `<div style="color:#4d5661">${CAT[w.cat] || w.cat}</div>`;
  return h;
}

function slotEl(s, i) {
  const d = document.createElement('div');
  if (!s) {
    d.className = 'slot empty';
    d.textContent = '+';
    d.onclick = () => openPicker(i);
    return d;
  }
  d.className = 'slot';
  if (s.bad) {
    d.innerHTML = `<div class="bad">未解析</div><div class="snm" style="color:var(--faint);font-size:10px">${esc(s.m.split('/').pop())}</div>`;
    d.onclick = () => openPicker(i);
    return d;
  }
  d.innerHTML = `<div class="snm">${esc(s.z && s.z !== s.n ? s.z : s.n)}</div>
    <div class="rkw"><button class="dn">−</button><b>${s.lv}</b><button class="up">+</button>
    <span>/ ${s.mx}</span></div>
    <button class="rm">×</button>`;
  d.querySelector('.rm').onclick = e => { e.stopPropagation(); S.slots[i] = null; renderBuild(); calc(); };
  d.querySelector('.up').onclick = e => {
    e.stopPropagation();
    if (s.lv < s.mx) { s.lv++; renderBuild(); calc(); }
  };
  d.querySelector('.dn').onclick = e => {
    e.stopPropagation();
    if (s.lv > 0) { s.lv--; renderBuild(); calc(); }
  };
  d.onclick = () => openPicker(i);
  return d;
}

function renderIncList() {
  const el = $('inclist');
  if (!el || !S.inc) return;
  const picked = S.inc.picked || [];
  el.innerHTML = picked.length ? picked.map(p => {
    const parts = Object.keys(p.sc || {}).map(k => {
      const v = p.sc[k];
      return `${INCLBL[k] || k} ${v > 0 ? '+' : ''}${num(v, 2)}`;
    });
    return `<div class="incrow"><span class="it">T${p.t}</span>
      <span class="in" title="${esc(p.d)}">${esc(p.n)}</span>
      <span class="iv">${parts.join(' · ') || '<i style="color:var(--faint)">行为型</i>'}</span></div>`;
  }).join('') : '<div class="incrow"><span class="iv">无已选节点</span></div>';
}

// ---------------------------------------------------------------- 计算
let calcT = 0, calcAbort = null, calcSeq = 0;

function calc() {
  saveState();
  clearTimeout(calcT);
  calcT = setTimeout(doCalc, 90);
}

// 把 S.opt / S.level 反映到控件上（读存档后用）
function syncOptUI() {
  const set = (sel, on) => { const b = $(sel).querySelector(`button[data-v="${on ? 1 : 0}"]`);
    if (b) $(sel).querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b)); };
  set('seg-status', S.opt.status);
  set('seg-steel', S.opt.steel);
  $('x-hd').checked = !!S.opt.headshot;
  $('x-crit').checked = S.opt.crit !== false;
  [['x-vir-r', 'x-vir', 'extViral'], ['x-arm-r', 'x-arm', 'armorStrip'],
   ['x-win-r', 'x-win', 'window'], ['x-buf-r', 'x-buf', 'dmgBuff'],
   ['x-cc-r', 'x-cc', 'ccBuff']].forEach(([r, n, k]) => {
    $(r).value = S.opt[k]; $(n).value = S.opt[k];
  });
}

async function doCalc() {
  if (!S.uid) return;
  const seq = ++calcSeq;
  if (calcAbort) calcAbort.abort();
  calcAbort = new AbortController();
  busy(true);
  try {
    const r = await api('/calc', {
      uid: S.uid, slots: S.slots, ei: S.ei, level: S.level, opt: S.opt,
    }, calcAbort.signal);
    if (seq !== calcSeq) return;
    S.view = r;
    applyView(r);
  } catch (e) {
    if (e.name !== 'AbortError') banner('计算失败：' + e.message);
  } finally {
    busy(false);
  }
}

function applyView(r) {
  $('wstats').innerHTML = statsHtml(r);
  renderContrib(r);
  renderSim(r);
  renderTargetStats(r);
  renderFac(r);
  renderResults(r);
}

function renderContrib(r) {
  const el = $('contrib');
  if (!el) return;
  if (!r.contrib.length && !r.bad.length) { el.innerHTML = '<div class="hint">空配卡</div>'; return; }
  let h = r.contrib.map(c => {
    const parts = c.st.map(x => {
      const lb = LABEL[x.k] || x.k;
      const v = x.k === 'sdur' ? num(x.v, 2) + 's' : (x.v > 0 ? '+' : '') + num(x.v, 2) + '%';
      return `${lb} ${v}`;
    });
    return `<div class="cr"><span class="cn">${esc(c.n)}</span>
      <span class="cl">Lv${c.lv}/${c.mx}</span>
      <span class="cv">${parts.join(' · ') || '<i style="color:var(--faint)">无数值（行为型）</i>'}</span></div>`;
  }).join('');
  if (r.bad.length) {
    h += `<div class="cr"><span class="cn" style="color:var(--red)">未解析 ${r.bad.length} 槽</span>
      <span class="cv">${esc(r.bad.slice(0, 4).join('、'))}${r.bad.length > 4 ? '…' : ''}</span></div>`;
  }
  el.innerHTML = h;
}

function renderSim(r) {
  const el = $('simpane');
  if (!el) return;
  const s = r.sim;
  if (!s) {
    el.innerHTML = `<div class="sechd"><span>直伤口径</span></div>
      <div class="hint">已关闭状态计算：不含病毒、腐蚀剥甲与 DoT。</div>`;
    return;
  }
  const tot = (s.directDps + s.dotDps) || 1;
  const ehp = r.target.hp + r.target.sh + r.target.og;
  const dealt = s.dps * s.dur;
  el.innerHTML = `<div class="sechd"><span>${s.window} 秒推演</span>
      <span style="text-transform:none;letter-spacing:0">${esc(r.target.n)} Lv${r.target.lv}</span></div>
    <div class="simgrid">
      <div class="cell"><span>病毒层</span><b>${s.viral}</b></div>
      <div class="cell"><span>腐蚀层</span><b>${s.corr}</b></div>
      <div class="cell"><span>剥甲</span><b>${(s.strip * 100).toFixed(0)}%</b></div>
      <div class="cell"><span>DoT 占比</span><b>${(s.dotDps / tot * 100).toFixed(0)}%</b></div>
    </div>
    <div class="bar">
      <i style="width:${(s.directDps / tot * 100).toFixed(1)}%;background:var(--gold)"></i>
      <i style="width:${(s.dotDps / tot * 100).toFixed(1)}%;background:var(--red)"></i>
    </div>
    <div class="legend">
      <span><em style="color:var(--gold2)">■</em> 直伤 ${fmt(s.directDps)}</span>
      <span><em style="color:var(--red)">■</em> DoT ${fmt(s.dotDps)}</span>
      <span>有效血量 ${fmt(ehp)}</span>
      <span>${s.window} 秒打掉 ${(dealt / ehp * 100).toFixed(1)}%</span>
    </div>`;
}

function renderTargetStats(r) {
  const t = r.target;
  $('estat').innerHTML = `
    <div><span>血量</span><b>${fmt(t.hp)}</b></div>
    <div><span>护甲</span><b>${Math.round(t.ar)}</b></div>
    <div><span>护盾</span><b>${fmt(t.sh)}</b></div>
    <div><span>护甲减伤</span><b>${(t.dr * 100).toFixed(0)}%</b></div>
    <div><span>实际等级</span><b>${t.lv}</b></div>
    <div><span>过载</span><b>${t.og ? fmt(t.og) : '—'}</b></div>`;
}

const FACMOD = {
  'Grineer': {impact:1.5, corrosive:1.5},
  'Kuva Grineer': {impact:1.5, corrosive:1.5, heat:0.5},
  'Corpus': {puncture:1.5, magnetic:1.5},
  'Corpus Amalgam': {electricity:1.5, magnetic:1.5, blast:0.5},
  'Infested': {slash:1.5, heat:1.5},
  'Infested Deimos': {blast:1.5, gas:1.5, viral:0.5},
  'Orokin': {puncture:1.5, viral:1.5, radiation:0.5},
  'Sentient': {cold:1.5, radiation:1.5, corrosive:0.5},
  'Narmer': {slash:1.5, toxin:1.5, magnetic:0.5},
  'Murmur': {electricity:1.5, radiation:1.5, viral:0.5},
  'Scaldra': {impact:1.5, corrosive:1.5},
  'Techrot': {magnetic:1.5, gas:1.5, cold:0.5},
};

function renderFac(r) {
  const fm = FACMOD[r.target.fk];
  let h;
  if (fm) {
    const plus = Object.keys(fm).filter(k => fm[k] > 1).map(k => ZH[k] || k);
    const minus = Object.keys(fm).filter(k => fm[k] < 1).map(k => ZH[k] || k);
    h = `<b>${esc(r.target.fk)}</b> 弱点 ${plus.join(' / ') || '—'}`
      + (minus.length ? ` · 抗性 ${minus.join(' / ')}` : '');
  } else {
    h = `<span style="color:#c08a5e">该目标没有阵营克制数据（按 ×1 计）</span>`;
  }
  if (r.bane) h += ` · 你的阵营卡 +${(r.bane * 100).toFixed(0)}%`;
  $('facres').innerHTML = h;
}

function renderResults(r) {
  const d = r.direct;
  $('r-burst').textContent = fmt(d.burst);
  $('r-burst-cmp').innerHTML =
    `每发 <b>${fmt(d.perShot)}</b> · 裸伤 <b>${fmt(r.raw.perShot)}</b> · 保留 <b>${(d.retain * 100).toFixed(0)}%</b>`;

  const s = r.sim;
  $('r-dps-lb').textContent = `含状态 · ${S.opt.window} 秒实战`;
  if (s) {
    $('r-dps').textContent = fmt(s.dps);
    $('r-dps-cmp').innerHTML =
      `直伤 <b>${fmt(s.directDps)}</b> · DoT <b>${fmt(s.dotDps)}</b> · 病毒 <b>${s.viral + S.opt.extViral}</b> 层`;
  } else {
    $('r-dps').textContent = '—';
    $('r-dps-cmp').textContent = '已关闭状态计算';
  }

  if (s && s.kill != null) {
    $('r-ttk').textContent = s.kill.toFixed(2) + 's';
    $('r-ttk-cmp').textContent = `${S.opt.window} 秒内击杀`;
  } else {
    $('r-ttk').textContent = '>' + S.opt.window + 's';
    $('r-ttk-cmp').textContent = `${S.opt.window} 秒未击杀`;
  }

  const rows = d.rows.slice().sort((a, b) => b.vH - a.vH);
  let h = `<table class="brk"><thead><tr><th>伤害类型</th><th>每发</th><th>阵营</th>
    <th>减伤后</th><th>到血</th><th>占比</th></tr></thead><tbody>`;
  for (const x of rows) {
    h += `<tr><td><span class="dot" style="background:${COL[x.t] || '#666'}"></span>${ZH[x.t] || x.t}</td>
      <td>${x.base.toFixed(1)}</td>
      <td class="${x.f > 1 ? 'pos' : x.f < 1 ? 'neg' : ''}">${x.f !== 1 ? '×' + x.f.toFixed(1) : '—'}</td>
      <td>${(x.dr * 100).toFixed(0)}%</td>
      <td>${x.vH.toFixed(1)}</td>
      <td>${(x.share * 100).toFixed(0)}%</td></tr>`;
  }
  h += `<tr><td style="color:var(--mute)">合计</td><td>${d.rows.reduce((a, x) => a + x.base, 0).toFixed(1)}</td>
    <td></td><td></td><td><b>${d.perShot.toFixed(1)}</b></td><td>100%</td></tr></tbody></table>`;
  $('brk').innerHTML = h;
}

// ---------------------------------------------------------------- 目标
function renderFacChips() {
  const el = $('fchips');
  const set = new Set(S.enemies.map(e => e.f));
  const list = ['全部', ...FAC_ORDER.filter(f => set.has(f)), ...[...set].filter(f => !FAC_ORDER.includes(f))];
  el.innerHTML = '';
  list.forEach(f => {
    const b = document.createElement('button');
    b.textContent = f;
    if (f === S.fac) b.className = 'on';
    b.onclick = () => {
      S.fac = f;
      el.querySelectorAll('button').forEach(x => x.classList.toggle('on', x.textContent === f));
      renderEnemyList();
    };
    el.appendChild(b);
  });
}

function renderEnemyList() {
  const el = $('elist');
  const q = $('esearch').value.trim().toLowerCase();
  el.innerHTML = '';
  const frag = document.createDocumentFragment();
  let n = 0;
  S.enemies.forEach(e => {
    if (S.fac !== '全部' && e.f !== S.fac) return;
    if (q && !e.n.toLowerCase().includes(q)) return;
    n++;
    const d = document.createElement('div');
    d.className = 'item' + (e.i === S.ei ? ' on' : '');
    d.innerHTML = `<div class="nm">${esc(e.n)}</div>${e.fk ? '' : '<span class="tag lo">无克制</span>'}`;
    d.onclick = () => { S.ei = e.i; renderEnemyList(); calc(); };
    frag.appendChild(d);
  });
  el.appendChild(frag);
  $('ecount').textContent = n + ' 个';
}

// ---------------------------------------------------------------- 选卡
let pickIdx = -1;

async function openPicker(i) {
  if (!S.view && !S.weapon) return;
  pickIdx = i;
  const cat = CAT[(S.view ? S.view.weapon.cat : S.weapon.cat)] || '';
  // 换卡时当前槽位那张要留在可选列表里，否则改不了等级以外的东西
  const used = new Set(S.slots.filter((s, k) => s && s.m && k !== i).map(s => s.m));
  showModal();
  $('m-search').style.display = '';
  $('m-title').style.display = 'none';
  $('m-search').oninput = renderPicker;
  $('m-list').innerHTML = '<div class="empty">加载…</div>';
  try {
    let list = S.mods.get(cat);
    if (!list) {
      const r = await api('/mods?cat=' + encodeURIComponent(cat));
      list = r.mods;
      S.mods.set(cat, list);
    }
    pickerRows = list.filter(m => !used.has(m.u));
    renderPicker();
  } catch (e) {
    $('m-list').innerHTML = '<div class="empty">加载失败：' + esc(e.message) + '</div>';
  }
}

let pickerRows = [];
function renderPicker() {
  const q = $('m-search').value.trim().toLowerCase();
  const el = $('m-list');
  el.innerHTML = '';
  const frag = document.createDocumentFragment();
  let n = 0;
  for (const m of pickerRows) {
    if (q && !(m.n.toLowerCase().includes(q) || (m.z || '').toLowerCase().includes(q))) continue;
    if (++n > 260) break;
    const d = document.createElement('div');
    d.className = 'mrow';
    const st = m.st.map(x => `${LABEL[x.k] || x.k} ${x.v > 0 ? '+' : ''}${num(x.v, 2)}%`).join(' · ');
    d.innerHTML = `<div class="nm">${esc(m.z && m.z !== m.n ? m.z : m.n)}</div>
      <div class="st">${esc(st)}</div>
      <div class="meta">${m.d} 点 · ${m.mx} 级</div>`;
    d.onclick = () => {
      S.slots[pickIdx] = {m: m.u, n: m.n, z: m.z, mx: m.mx, lv: m.mx, t: m.t, d: m.d, pol: m.pol};
      closeModal();
      renderBuild(); calc();
    };
    frag.appendChild(d);
  }
  el.appendChild(frag);
  $('m-foot').textContent = `${n} 个可用 · ${CAT[(S.weapon || {}).cat] || ''}`;
}

// ---------------------------------------------------------------- 弹窗
function showModal() { $('modal').classList.add('on'); $('m-search').value = ''; }
function closeModal() {
  $('modal').classList.remove('on');
  $('m-list').onclick = null;
  $('m-search').oninput = null;
}

function showRivens() {
  const R = S.rivens || [];
  showModal();
  $('m-search').style.display = 'none';
  $('m-title').style.display = '';
  $('m-title').textContent = `紫卡 ${R.length} 张 · ${R.filter(r => r.lvl >= 8).length} 张满级`;
  const withW = R.filter(r => r.compat).length;
  const rows = R.map(r => {
    const stats = r.s.length ? r.s.map(x => {
      const v = x.v == null ? '—'
        : x.abs ? (x.v >= 0 ? '+' : '') + (x.v * 10).toFixed(1)
        : (x.v >= 0 ? '+' : '') + (x.v * 100).toFixed(1) + '%';
      return `<span class="st${x.c ? ' cur' : ''}">${v} ${esc(x.n)}</span>`;
    }).join('') : '<span class="st">未开卡</span>';
    return `<div class="rvr"><div class="rvh"><b>${esc(r.nm)}</b><span class="rw">${esc(r.w)}</span>
      <span class="rvt">Lv${r.lvl}/8 · 洗 ${r.rr} · 倾向 ${r.disp}</span></div>
      <div class="rvs">${stats}</div></div>`;
  }).join('');
  $('m-list').innerHTML = `<div class="note" style="font-size:11.5px;color:var(--mute)">
      数值按 RivenParser 的公式算：<code>基准 × (1.5×倾向×10) × 1.25^负词条 × 0.9~1.1 × 词条数衰减 × (等级+1)</code>。
      倾向取 DE 导出的 <code>omegaAttenuation</code>（多数 1.2），不是游戏内每期调整后的实时值，热门武器偏乐观。
      <b>${withW}</b> 张已开卡，<b>${R.length - withW}</b> 张未开。</div>
    <div class="rvlist">${rows}</div>`;
  $('m-foot').textContent = '点击空白处关闭';
  $('m-list').onclick = closeModal;
}

function showNote() {
  showModal();
  $('m-search').style.display = 'none';
  $('m-title').style.display = '';
  $('m-title').textContent = '口径与数据来源';
  $('m-list').innerHTML = `<div class="note">
  <p><b>克制</b>：Update 36（2024-06）之后血量/护甲/护盾类型合并，克制只按阵营：弱点 ×1.5、抗性 ×0.5。旧的 Cloned Flesh / Ferrite 那套已失效。</p>
  <p><b>敌方护甲减伤</b>：<code>A ≤ 2700 → 0.9·√(A/2700)</code>，<code>A &gt; 2700 → A/(A+300)</code>。护甲按等级缩放后夹在 [200, 2700]。</p>
  <p><b>等级缩放</b>：双端点曲线 + smoothstep（L=70, U=80）。血量 q^2.12 / q^0.72，护甲 q^1.75 / q^0.75，护盾 q^1.76 / q^0.76，按阵营分叉。</p>
  <p><b>暴击</b>：按期望 <code>1 + cc·(cm−1)</code>，超过 100% 仍成立。</p>
  <p><b>状态</b>：病毒首层 +100%、每层 +25%（10 层 +325%）；腐蚀 26%/层、上限 80%、8 秒；燃烧剥甲 50% 且 50% 火焰伤/秒；流血 35% 总伤/秒无视护甲；中毒 50% 毒素伤/秒无视护盾。触发按伤害占比分配。</p>
  <p><b>灵化</b>：形态数值取自 Voidforge 的 <code>incarnon.ts</code>，进化节点取自其 wiki 解析版；节点选择来自本机 <code>SkillTree</code>。基础伤害类只在灵化形态生效。</p>
  <p><b>紫卡</b>：<code>基准 × (1.5 × 倾向 × 10) × 1.25^负词条 × lerp(0.9,1.1,Value/0x3FFFFFFF) × 词条数衰减 × (等级+1)</code>。倾向用 DE 导出的 <code>omegaAttenuation</code>（674/839 是 1.2），不是实时 disposition。</p>
  <p><b>未建模</b>：连发/蓄力节奏、范围伤害、穿透多目标、磁力对护盾的加伤、冰缓暴伤、镀层类条件叠层、赋能与战甲技能公式。</p>
  <p><b>数据</b>：武器与 mod 来自 DE PublicExport；敌人来自 warframe-damage.com 的整理版；配卡与紫卡来自本机 lastData。</p>
  </div>`;
  $('m-foot').textContent = '点击空白处关闭';
  $('m-list').onclick = closeModal;
}

$('m-close').onclick = closeModal;
$('modal').onclick = e => { if (e.target.id === 'modal') closeModal(); };
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeModal();
});

// ---------------------------------------------------------------- 交互绑定
$('wsearch').oninput = renderWeaponList;
$('esearch').oninput = renderEnemyList;

$('seg-status').onclick = e => {
  const b = e.target.closest('button');
  if (!b) return;
  S.opt.status = b.dataset.v === '1';
  $('seg-status').querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b));
  calc();
};
$('seg-steel').onclick = e => {
  const b = e.target.closest('button');
  if (!b) return;
  S.opt.steel = b.dataset.v === '1';
  $('seg-steel').querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b));
  if (S.mode === 'rank') buildRanking();
  calc();
};
$('btn-rank').onclick = () => setMode(S.mode === 'rank' ? 'list' : 'rank');
$('btn-riven').onclick = showRivens;
$('btn-note').onclick = showNote;

function bindPair(rid, nid, key, lo, hi) {
  const r = $(rid), n = $(nid);
  const sync = v => {
    v = Math.max(lo, Math.min(hi, Math.round(v) || 0));
    S.opt[key] = v;
    r.value = Math.min(hi, v); n.value = v;
    calc();
  };
  r.oninput = () => sync(+r.value);
  n.oninput = () => sync(+n.value);
}
bindPair('x-vir-r', 'x-vir', 'extViral', 0, 10);
bindPair('x-arm-r', 'x-arm', 'armorStrip', 0, 100);
bindPair('x-win-r', 'x-win', 'window', 3, 60);
bindPair('x-buf-r', 'x-buf', 'dmgBuff', 0, 500);
bindPair('x-cc-r', 'x-cc', 'ccBuff', 0, 200);

$('lvl-range').oninput = () => {
  S.level = +$('lvl-range').value; $('lvl-num').value = S.level; calc();
};
$('lvl-num').oninput = () => {
  S.level = Math.max(1, Math.min(9999, +$('lvl-num').value || 1));
  $('lvl-range').value = Math.min(200, S.level); calc();
};
$('x-hd').onchange = e => { S.opt.headshot = e.target.checked; calc(); };
$('x-crit').onchange = e => { S.opt.crit = e.target.checked; calc(); };

document.addEventListener('keydown', e => {
  if (e.key === '/' && document.activeElement.tagName !== 'INPUT') {
    e.preventDefault(); $('wsearch').focus();
  }
});

document.querySelectorAll('#tabbar button').forEach(b => {
  b.onclick = () => {
    document.body.dataset.pane = b.dataset.pane;
    document.querySelectorAll('#tabbar button').forEach(x => x.classList.toggle('on', x === b));
  };
});

boot();
