const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
const __html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(__html.slice(__html.indexOf('const DT = ['), __html.indexOf('// ---------- 状态 ----------')));
const W = window.WF.w, M = window.WF.m, E = window.WF.e, B = window.WF.b;
globalThis.state = { sp: false };

const pad = (s, n) => String(s).padStart(n);
const fix = (v, n) => Number(v).toFixed(n);

const tn = B.find(b => b.w.includes('TenoraPrime'));
const w = W[tn.w];
const naked = { n: 'x', f: 'Grineer', hp: 1e9, ar: 0, sh: 0, ht: 'Flesh', at: 'none', st: 'none' };
const r = compute(w, tn.slots[0], naked, 1, 'linear');

console.log('Tenora Prime 配置A');
console.log('  cc ' + fix(r.cc, 1) + '%  cm ' + fix(r.cm, 2) + '  critMul ' + fix(r.critMul, 3) + '  ms ' + r.ms);
console.log('  每发单弹 ' + fix(r.perShotRaw / r.ms, 1) + '  每发含多重 ' + fix(r.perShotRaw, 1));
console.log('  burst ' + fix(r.burst, 0) + '  sustained ' + fix(r.sust, 0));

const cases = [
  ['Lv100 重炮手', { n: 'h', f: 'Grineer', hp: 700, ar: 500, sh: 0, ht: 'Cloned Flesh', at: 'ferrite', st: 'none' }, 100],
  ['Lv100 轰击者', { n: 'b', f: 'Grineer', hp: 600, ar: 400, sh: 0, ht: 'Cloned Flesh', at: 'alloy', st: 'none' }, 100],
  ['Lv100 船员', { n: 'c', f: 'Corpus', hp: 60, ar: 0, sh: 150, ht: 'Flesh', at: 'none', st: 'shield' }, 100],
  ['Lv200 重炮手', { n: 'h', f: 'Grineer', hp: 700, ar: 500, sh: 0, ht: 'Cloned Flesh', at: 'ferrite', st: 'none' }, 200],
  ['Lv200 船员', { n: 'c', f: 'Corpus', hp: 60, ar: 0, sh: 150, ht: 'Flesh', at: 'none', st: 'shield' }, 200],
];
console.log('');
console.log('=== 换目标 ===');
for (const c of cases) {
  const x = compute(w, tn.slots[0], c[1], c[2], 'linear');
  console.log('  ' + pad(c[0], 13) + ' 甲' + pad(Math.round(x.ar), 5) + ' DR' + pad(fix(x.dr * 100, 0), 3) +
    '%  到血/发 ' + pad(fix(x.toHealth, 0), 6) + '  DPS ' + pad(fix(x.burst, 0), 6) + '  TTK ' + fix(x.ttk, 2) + 's');
}

const hg = { n: 'h', f: 'Grineer', hp: 700, ar: 500, sh: 0, ht: 'Cloned Flesh', at: 'ferrite', st: 'none' };
console.log('');
console.log('=== 同目标换护甲公式 ===');
for (const mode of ['linear', 'sqrt']) {
  const x = compute(w, tn.slots[0], hg, 100, mode);
  console.log('  ' + pad(mode, 7) + ' DR ' + fix(x.dr * 100, 1) + '%  每发 ' + fix(x.toHealth, 0) + '  DPS ' + fix(x.burst, 0));
}

// 元素合流自检：拿一把天生带元素的武器
const innate = Object.keys(W).filter(u => W[u].cat === 'LongGuns' &&
  (W[u].dmg[4] > 0 || W[u].dmg[5] > 0 || W[u].dmg[6] > 0 || W[u].dmg[3] > 0));
console.log('');
console.log('=== 天生带元素的步枪（前 5）===');
for (const u of innate.slice(0, 5)) {
  const ww = W[u];
  const parts = ['impact', 'puncture', 'slash', 'heat', 'cold', 'electricity', 'toxin']
    .map((t, i) => [t, ww.dmg[i]]).filter(x => x[1] > 0);
  console.log('  ' + pad(ww.n, 22) + ' ' + parts.map(p => p[0] + ':' + fix(p[1], 1)).join(' '));
}
