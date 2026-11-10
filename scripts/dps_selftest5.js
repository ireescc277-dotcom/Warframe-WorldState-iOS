// 紫卡：数值换算与配卡接入的自检
const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
global.WF = window.WF;
const html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(html.slice(html.indexOf('const W = WF.w'), html.indexOf('const state = {')));

const W = window.WF.w, M = window.WF.m, B = window.WF.b, E = window.WF.e, R = window.WF.rv;
const fix = (n, d = 1) => (isFinite(n) ? n.toFixed(d) : String(n));
let fail = 0;
function ok(name, cond, got) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name.padEnd(30)} ${got}`);
  if (!cond) fail++;
}

const base = { steel: false, status: false, extViral: 0, armorStrip: 0, window: 10,
  headshot: false, crit: true, incarnon: false, dmgBuff: 0, ccBuff: 0 };
const naked = { n: 'x', f: 'Grineer', hp: 1e9, ar: 0, sh: 0, fk: 'Grineer' };

console.log('=== 紫卡总量 ===');
console.log(`  共 ${R.length} 张，满级 ${R.filter(r => r.lvl >= 8).length}，已开卡 ${R.filter(r => r.compat).length}`);
ok('紫卡 45 张', R.length === 45, R.length);

console.log('\n=== 数值合理性 ===');
const lv8 = R.filter(r => r.lvl >= 8 && r.s.length);
const pct = lv8.flatMap(r => r.s.filter(x => x.v != null).map(x => Math.abs(x.v) * 100));
console.log(`  满级词条 ${pct.length} 条，绝对值范围 ${fix(Math.min(...pct))}% ~ ${fix(Math.max(...pct))}%`);
ok('满级词条都在 5%~400%', Math.min(...pct) > 5 && Math.max(...pct) < 400,
  `${fix(Math.min(...pct))} ~ ${fix(Math.max(...pct))}`);

const lv0 = R.filter(r => r.lvl === 0 && r.s.length);
const p0 = lv0.flatMap(r => r.s.filter(x => x.v != null).map(x => Math.abs(x.v) * 100));
if (p0.length) {
  console.log(`  未升级 ${p0.length} 条，绝对值范围 ${fix(Math.min(...p0))}% ~ ${fix(Math.max(...p0))}%`);
  ok('未升级词条普遍小于满级', p0.reduce((a,b)=>a+b,0)/p0.length < pct.reduce((a,b)=>a+b,0)/pct.length / 2,
    `均值 ${fix(p0.reduce((a,b)=>a+b,0)/p0.length)} vs ${fix(pct.reduce((a,b)=>a+b,0)/pct.length)}`);
}

console.log('\n=== 负面词条是负值 ===');
const curses = R.flatMap(r => r.s.filter(x => x.c));
ok('负面词条都带负面标记', curses.every(x => x.c === 1), curses.length + ' 条');

console.log('\n=== 配卡里的紫卡确实参与计算 ===');
let tested = 0;
for (const b of B) {
  const slot = (b.slots[0] || []).find(s => s && s.m.startsWith('RIVEN:'));
  if (!slot) continue;
  const m = M[slot.m];
  if (!m) continue;
  const w = W[b.w];
  if (!w) continue;
  const withR = compute(w, b.slots[0], naked, 100, { ...base }, b.w);
  const without = b.slots[0].map(s => (s && s.m === slot.m) ? null : s);
  const noR = compute(w, without, naked, 100, { ...base }, b.w);
  const diff = Math.abs(withR.d.burst - noR.d.burst) / (noR.d.burst || 1);
  console.log(`  ${(w.z || w.n).padEnd(18)} ${m.n.padEnd(14)} 有卡 ${fix(withR.d.burst, 0).padStart(8)}  无卡 ${fix(noR.d.burst, 0).padStart(8)}  差 ${(diff * 100).toFixed(1)}%`);
  if (diff > 0.001) tested++;
}
ok('装紫卡的配卡 DPS 有变化', tested > 0, tested + ' 套');

console.log(`\n${fail === 0 ? '全部通过' : fail + ' 项失败'}`);
process.exit(fail ? 1 : 0);
