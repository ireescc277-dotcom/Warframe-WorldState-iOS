'use strict';
// 前端：只做选择与展示。所有数值来自服务端 kernel.js（站点本体脚本）。
//
// 状态 S 的形状就是 /api/calc 的请求体：
//   {weapon, enemy, level, steel, eximus, mods:{"0":"Serration"}, opts:{...}}

const $ = id => document.getElementById(id);
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const S = {
  weapon: null,
  wmeta: null,
  enemy: null,
  level: 100,
  steel: false,
  eximus: false,
  mods: {},        // slot -> mod 名
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

let META = { weapons: [], enemies: [], factions: [] };
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

// ---------------------------------------------------------------- 启动

async function boot() {
  const r = await fetch('/api/meta');
  META = await r.json();
  $('wcount').textContent = META.weapons.length + ' 把';
  $('ecount').textContent = META.enemies.length + ' 个';
  META.factions = [...new Set(META.enemies.map(e => e.faction))];
  $('fchips').innerHTML = `<button class="fchip on" data-f="">全部</button>` +
    META.factions.map(f => `<button class="fchip" data-f="${esc(f)}">${esc(f)}</button>`).join('');
  renderOpts();
  bindPick();
  bindHeader();

  const first = META.weapons.find(w => w.n === 'Torid') || META.weapons[0];
  await setWeapon(first.n);
  const hg = META.enemies.find(e => e.name === 'Heavy Gunner') || META.enemies[0];
  setEnemy(hg);
}

// ---------------------------------------------------------------- 武器

async function setWeapon(name) {
  S.weapon = name;
  S.mods = {};
  const r = await fetch('/api/weapon?name=' + encodeURIComponent(name));
  if (!r.ok) return;
  S.wmeta = await r.json();
  $('wsearch').placeholder = name;
  $('wsearch').value = '';
  $('wcount').textContent = name;
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
  const parts = Object.keys(dmg).map(k => `${k} ${Math.round(dmg[k])}`).join(' · ');
  $('wcard').innerHTML = `
    <div class="wname">${esc(w.name)}<span class="wcat">${esc(w.category || '')}</span></div>
    <div class="wrow"><span>攻击段</span><b>${(w.attacks || []).map(a => esc(a.name)).join(' · ')}</b></div>
    <div class="wrow"><span>基础伤害</span><b>${Math.round(total)}</b></div>
    <div class="wrow"><span>伤害类型</span><b class="sm">${esc(parts || '—')}</b></div>
    <div class="wrow"><span>暴击</span><b>${(atk.crit_chance || 0)}% ×${(atk.crit_mult || 1)}</b></div>
    <div class="wrow"><span>触发</span><b>${(atk.status_chance || 0)}%</b></div>
    <div class="wrow"><span>射速</span><b>${(atk.speed || 0)}/s</b></div>
    <div class="wrow"><span>弹匣</span><b>${w.magazineSize || '—'}${w.incarnon ? ' / 灵化 ' + (w.incMagazineSize || '?') : ''}</b></div>`;
}

function renderWList(filter, cat) {
  const q = (filter || '').toLowerCase();
  const list = META.weapons
    .filter(w => (!cat || w.cat === cat) && (!q || w.n.toLowerCase().includes(q)))
    .slice(0, 300);
  const cats = [...new Set(META.weapons.map(w => w.cat))].filter(Boolean);
  $('wlist').innerHTML =
    `<div class="fchips">${['', ...cats].map(c =>
      `<button class="fchip${(c || '') === (cat || '') ? ' on' : ''}" data-c="${esc(c)}">${esc(c || '全部')}</button>`).join('')}</div>` +
    `<div class="wlistbody">${list.map(w =>
      `<div class="lrow" data-w="${esc(w.n)}"><span class="ln">${esc(w.n)}</span><span class="lt">${esc(w.cat || '')}</span></div>`).join('') ||
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
    let v = Math.max(1, Math.min(9999, +ln.value || 1));
    ln.value = v; lr.value = Math.min(200, v); S.level = v; calc();
  });
}

function renderEList(filter, faction) {
  const q = (filter || '').toLowerCase();
  const list = META.enemies
    .filter(e => (!faction || e.faction === faction) && (!q || e.name.toLowerCase().includes(q)))
    .slice(0, 400);
  $('elistbody').innerHTML = list.map(e =>
    `<div class="lrow" data-e="${esc(e.name)}"><span class="ln">${esc(e.name)}</span><span class="lt">${esc(e.faction)}</span></div>`).join('') ||
    '<div class="lrow dim">没有匹配</div>';
}

function setEnemy(e) {
  if (!e) return;
  S.enemy = e;
  $('esearch').placeholder = e.name;
  $('esearch').value = '';
  $('ecount').textContent = e.name;
  $('tname').innerHTML = `${esc(e.name)}<span class="wcat">${esc(e.faction)}</span>`;
  renderEnemyStats(null);
  calc();
}

// 等级缩放后的血量只有内核知道，先按基础值显示，算完再刷新
function renderEnemyStats(target) {
  const e = S.enemy;
  if (!e) return;
  const hp = target ? target.hp : e.hp;
  const ar = target ? target.ar : e.ar;
  const sh = target ? target.sh : e.sh;
  $('estat').innerHTML = `
    <div><span>生命</span><b>${fmt(hp)}</b></div>
    <div><span>护甲</span><b>${fmt(ar)}</b></div>
    <div><span>护盾</span><b>${fmt(sh)}</b></div>`;
  const fac = target && target.fac;
  $('facres').innerHTML = fac
    ? '弱点 ' + Object.entries(fac).map(([k, v]) => `${esc(k)} ×${v}`).join(' · ')
    : '';
}

// ---------------------------------------------------------------- 槽位

function slotDefs() {
  const w = S.wmeta || {};
  const melee = (w.category || '') === 'Melee';
  const out = [];
  for (let i = 0; i < 8; i++) out.push({ id: i, kind: 'main', label: 'MOD' });
  out.push({ id: 8, kind: 'exilus', label: '功能' });
  if (melee) out.push({ id: 9, kind: 'stance', label: '架势' });
  out.push({ id: 10, kind: 'arcane', label: '赋能' });
  return out;
}

function renderSlots() {
  const defs = slotDefs();
  $('slots').innerHTML = defs.map(d => {
    const m = S.mods[d.id];
    return `<button class="slot${m ? ' has' : ''}" data-slot="${d.id}" data-kind="${d.kind}">
      <span class="sk">${d.label}</span>
      <span class="sn">${m ? esc(m) : '＋'}</span>
      ${m ? '<span class="sx" data-del="' + d.id + '">×</span>' : ''}
    </button>`;
  }).join('');
  const w = S.wmeta || {};
  $('wside').innerHTML = `
    <div class="sidehd">配卡</div>
    <div class="srow"><span>已装</span><b>${Object.keys(S.mods).length} / ${defs.length}</b></div>
    <div class="srow"><span>灵化</span><b>${w.incarnon ? '有' : '无'}</b></div>
    <div class="srow"><span>兼容</span><b class="sm">${(w.compTags || []).join(' / ') || '—'}</b></div>`;
}

$('slots').addEventListener('click', e => {
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
  $('m-title').textContent = '槽位 ' + (slot + 1) + ' · ' + ({ main: '普通', exilus: '功能', stance: '架势', arcane: '赋能' }[kind] || kind);
  $('m-search').style.display = '';
  $('m-foot').innerHTML = `<button class="mbtn" id="m-clear">卸下</button>`;
  $('m-list').innerHTML = '<div class="lrow dim">载入…</div>';
  $('m-search').value = '';
  $('m-clear').onclick = () => {
    delete S.mods[slot];
    closeModal(); renderSlots(); calc();
  };
  const r = await fetch(`/api/mods?weapon=${encodeURIComponent(S.weapon)}&slot=${slot}`);
  const d = await r.json();
  PICK.all = d.mods || [];
  renderModList('');
  $('m-search').focus();
}

function renderModList(q) {
  q = (q || '').toLowerCase();
  const used = new Set(Object.entries(S.mods).filter(([k]) => +k !== PICK.slot).map(([, v]) => v));
  const list = PICK.all.filter(m => !used.has(m.n) && (!q || m.n.toLowerCase().includes(q)));
  $('m-list').innerHTML = list.map(m => {
    const act = m.act && typeof m.act === 'object'
      ? Object.keys(m.act).filter(k => typeof m.act[k] === 'number')
          .map(k => `${k} ${m.act[k] > 0 ? '+' : ''}${m.act[k]}`).slice(0, 3).join(' · ')
      : '';
    return `<div class="mrow" data-m="${esc(m.n)}">
      <div class="mn">${esc(m.n)}</div>
      <div class="ma">${esc(act)}</div>
    </div>`;
  }).join('') || '<div class="lrow dim">没有匹配</div>';
}

$('m-search').addEventListener('input', e => renderModList(e.target.value));
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
  { k: 'headshot', g: '通用', n: '爆头 / 弱点', t: 'chk' },
  { k: 'armor', g: '通用', n: '外部削甲', t: 'chknum', min: 0, max: 99, def: 50, u: '%' },
  { k: 'statusCount', g: '通用', n: '手动指定敌人状态总数', t: 'chknum', min: 1, max: 50, def: 1, u: '个' },
  { k: 'perStatusMul', g: '通用', n: '「每状态增伤」按乘算（异况超量）', t: 'chk' },
  { k: 'allConds', g: '通用', n: '所有 mod 条件默认满足', t: 'chk' },
  { k: 'queueLength', g: '通用', n: '连续射击 / 攻击时长', t: 'num', min: 1, max: 60, def: 20, u: '秒' },

  { k: 'stealth', g: '近战', n: '潜行加成', t: 'chk' },
  { k: 'heavy', g: '近战', n: '重击', t: 'chknum', min: 1, max: 13, def: 12, u: 'x' },
  { k: 'meleeCombo', g: '近战', n: '轻击连击倍率', t: 'chknum', min: 1, max: 13, def: 12, u: 'x' },
  { k: 'abilityCombo', g: '近战', n: '技能连击倍率', t: 'chknum', min: 1, max: 12, def: 12, u: 'x' },
  { k: 'sniperCombo', g: '近战', n: '狙击连击倍率', t: 'chknum', min: 1.5, max: 100, def: 1.5, u: 'x' },

  { k: 'rhino', g: '战甲 buff', n: '战吼 (Rhino)', t: 'chknum', min: 1, max: 9999, def: 30, u: '%' },
  { k: 'mirage', g: '战甲 buff', n: '黯然失色 (Mirage)', t: 'chknum', min: 1, max: 9999, def: 30, u: '%' },
  { k: 'xata', g: '战甲 buff', n: '真理密语 (Xaku)', t: 'chknum', min: 1, max: 9999, def: 26, u: '%' },
  { k: 'tlash', g: '战甲 buff', n: '剧毒鞭笞 (Saryn)', t: 'chknum', min: 1, max: 9999, def: 30, u: '%' },
  { k: 'nourish', g: '战甲 buff', n: '消化滋养 (Grendel)', t: 'chknum', min: 1, max: 9999, def: 45, u: '%' },
  { k: 'flatCrit', g: '战甲 buff', n: '绝对暴击几率 (Kullervo / Harrow)', t: 'chknum', min: 1, max: 9999, def: 50, u: '%' },
  { k: 'madurai', g: '战甲 buff', n: 'Madurai 物理 +30%', t: 'chk' },
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
      steel: S.steel, eximus: S.eximus, mods: S.mods, opts: S.opts,
    };
    try {
      const r = await fetch('/api/calc', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      });
      const d = await r.json();
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
  const rows = d.attacks || [];
  if (!rows.length) {
    $('rbar').innerHTML = '<div class="empty">这个组合没有可算的攻击段</div>';
    $('attacks').innerHTML = '';
    return;
  }
  let best = rows[0];
  for (const a of rows) if ((a.dps.health || 0) > (best.dps.health || 0)) best = a;

  $('rbar').innerHTML = `
    <div class="fbox">
      <div class="lb">最高一段 · 对生命</div>
      <div class="big">${fmt(best.dps.health)}</div>
      <div class="cmp">${esc(best.name)}</div>
    </div>
    <div class="fbox">
      <div class="lb">击杀时间 TTK</div>
      <div class="big s">${fmtT(best.ttk.health)}</div>
      <div class="cmp">Lv${d.level} ${esc(d.enemy)}${d.steel ? ' · 钢铁' : ''}</div>
    </div>
    <div class="fbox">
      <div class="lb">攻击段数</div>
      <div class="big s">${rows.length}</div>
      <div class="cmp">每段独立计算</div>
    </div>`;

  $('attacks').innerHTML = rows.map(a => {
    const defs = Object.keys(a.dps);
    return `<div class="acard">
      <div class="ahd">${esc(a.name)}<span class="atag">${defs.length} 层</span></div>
      <table class="atab">
        <thead><tr><th>目标层</th><th>队列 DPS</th><th>每发中位</th><th>TTK</th></tr></thead>
        <tbody>${defs.map(k => `<tr>
          <td>${DT[k] || k}</td>
          <td class="num">${fmt(a.dps[k])}</td>
          <td class="num dim">${fmt(a.total[k])}</td>
          <td class="num">${fmtT(a.ttk[k])}</td>
        </tr>`).join('')}</tbody>
      </table>
    </div>`;
  }).join('');
}

// ---------------------------------------------------------------- 头

function bindHeader() {
  $('seg-steel').addEventListener('click', e => {
    const b = e.target.closest('button');
    if (!b) return;
    S.steel = b.dataset.v === '1';
    [...$('seg-steel').children].forEach(x => x.classList.toggle('on', x === b));
    calc();
  });
  $('seg-eximus').addEventListener('click', e => {
    const b = e.target.closest('button');
    if (!b) return;
    S.eximus = b.dataset.v === '1';
    [...$('seg-eximus').children].forEach(x => x.classList.toggle('on', x === b));
    calc();
  });
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
