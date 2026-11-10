// 灵化：形态切换与进化节点的数值自检
const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
global.WF = window.WF;
const html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(html.slice(html.indexOf('const W = WF.w'), html.indexOf('const state = {')));

const W = window.WF.w, B = window.WF.b, E = window.WF.e, I = window.WF.i;
const fix = (n, d = 0) => (isFinite(n) ? n.toFixed(d) : String(n));
let fail = 0;
function ok(name, cond, got) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name.padEnd(32)} ${got}`);
  if (!cond) fail++;
}

const base = { steel: false, status: false, extViral: 0, armorStrip: 0, window: 10,
  headshot: false, crit: true, incarnon: false };
const naked = { n: 'x', f: 'Grineer', hp: 1e9, ar: 0, sh: 0, fk: 'Grineer' };

console.log('=== 灵化武器清单 ===');
for (const [uid, x] of Object.entries(I)) {
  const b = B.find(y => y.w === uid);
  console.log(`  ${x.name.padEnd(20)} tree=${x.tree}  节点=${x.picked.length}  有配卡=${!!b}`);
}
ok('灵化武器 6 把', Object.keys(I).length === 6, Object.keys(I).length);

console.log('\n=== Torid 形态切换 ===');
const tu = Object.keys(I).find(u => I[u].id === 'torid_incarnon');
const tb = B.find(y => y.w === tu);
const tw = W[tu];
console.log(`  普通: 基础 ${tw.td}  cc ${fix(tw.cc * 100)}%  cm ${tw.cm}  fr ${tw.fr}`);
const f2 = I[tu].forms[1];
console.log(`  灵化: 基础 ${f2.td}  cc ${fix(f2.cc * 100)}%  cm ${f2.cm}  fr ${f2.fr}`);

const r0 = compute(tw, tb.slots[0], naked, 100, { ...base, incarnon: false }, tu);
const r1 = compute(tw, tb.slots[0], naked, 100, { ...base, incarnon: true }, tu);
console.log(`  普通形态 burst ${fix(r0.d.burst)}  每发 ${fix(r0.d.toHealth)}`);
console.log(`  灵化形态 burst ${fix(r1.d.burst)}  每发 ${fix(r1.d.toHealth)}`);
ok('两形态结果不同', Math.abs(r1.d.burst - r0.d.burst) > 1, `${fix(r0.d.burst)} vs ${fix(r1.d.burst)}`);
ok('灵化形态基础值 51（未叠节点前）', f2.td === 51, fix(f2.td));

console.log('\n=== 节点加成是否生效 ===');
// Torid 选了 t2 "Final Fusillade" flatBaseDamage 51，只在灵化形态
const pickedNames = I[tu].picked.map(p => `T${p.t}:${p.n}`).join(', ');
console.log('  已选:', pickedNames);
const hasFlat = I[tu].picked.some(p => p.sc && p.sc.flatBaseDamage);
ok('Torid 含 flatBaseDamage 节点', hasFlat, hasFlat);
// 灵化形态下，td = (51 + 51) = 102（若 flat 生效）
console.log(`  灵化形态实际 td ${fix(r1.wp2.td)}（51 + 51 应为 102）`);
ok('flatBaseDamage 叠加到灵化形态', Math.abs(r1.wp2.td - 102) < 0.01, fix(r1.wp2.td));

console.log('\n=== 普通形态不吃基础伤害类节点 ===');
const hasCC = I[tu].picked.some(p => p.sc && p.sc.criticalChance);
const baseCC = tw.cc;
console.log(`  普通形态 cc ${fix(r0.wp2.cc * 100, 1)}%（原 ${fix(baseCC * 100, 1)}%）`);
if (hasCC) ok('普通形态仍吃暴击节点', r0.wp2.cc > baseCC, `${fix(baseCC * 100, 1)}% → ${fix(r0.wp2.cc * 100, 1)}%`);

console.log('\n=== 每把灵化武器都能算 ===');
for (const [uid, x] of Object.entries(I)) {
  const b = B.find(y => y.w === uid);
  if (!b) { console.log(`  ${x.name}: 无配卡，跳过`); continue; }
  const a = compute(W[uid], b.slots[0], naked, 100, { ...base, incarnon: false }, uid);
  const c = compute(W[uid], b.slots[0], naked, 100, { ...base, incarnon: true }, uid);
  const okv = isFinite(a.d.burst) && isFinite(c.d.burst) && a.d.burst > 0 && c.d.burst > 0;
  console.log(`  ${x.name.padEnd(20)} 普通 ${fix(a.d.burst).padStart(8)}  灵化 ${fix(c.d.burst).padStart(8)}  ${okv ? '' : '  <-- 异常'}`);
  if (!okv) fail++;
}
const bad = Object.entries(I).filter(([uid]) => {
  const b = B.find(y => y.w === uid); if (!b) return false;
  const a = compute(W[uid], b.slots[0], naked, 100, { ...base }, uid);
  const c = compute(W[uid], b.slots[0], naked, 100, { ...base, incarnon: true }, uid);
  return !(isFinite(a.d.burst) && isFinite(c.d.burst) && a.d.burst > 0 && c.d.burst > 0);
});
ok('全部有限且为正', bad.length === 0, bad.length + ' 项异常');

console.log(`\n${fail === 0 ? '全部通过' : fail + ' 项失败'}`);
process.exit(fail ? 1 : 0);
