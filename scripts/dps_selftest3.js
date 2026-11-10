// 外部条件（病毒层数 / 剥甲 / 爆头 / 时间窗口 / 暴击开关）的自检
const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
global.WF = window.WF;
const html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(html.slice(html.indexOf('const W = WF.w'), html.indexOf('const state = {')));

const W = window.WF.w, B = window.WF.b, E = window.WF.e;
const fix = (n, d = 0) => (isFinite(n) ? n.toFixed(d) : String(n));
let fail = 0;
function ok(name, cond, got) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name.padEnd(30)} ${got}`);
  if (!cond) fail++;
}
function near(a, b, tol = 0.01) { return Math.abs(a - b) <= Math.abs(b) * tol + 1e-6; }

const build = B.find(b => b.w.includes('TenoraPrime'));
const w = W[build.w];
const hg = E.find(e => e.n === 'Heavy Gunner');
const base = { steel: false, status: true, extViral: 0, armorStrip: 0, window: 10, headshot: false, crit: true };

console.log('=== 外部病毒层数 ===');
const v0 = compute(w, build.slots[0], hg, 100, { ...base, status: false });
const rows = [];
for (const n of [0, 5, 10]) {
  const r = compute(w, build.slots[0], hg, 100, { ...base, extViral: n });
  rows.push([n, r.s ? r.s.dps : 0, r.d.burst]);
  console.log(`  外部病毒 ${String(n).padStart(2)} 层  burst ${fix(r.d.burst)}  含状态 ${fix(r.s ? r.s.dps : 0)}`);
}
ok('外部病毒不改变直伤', near(rows[0][2], rows[2][2], 1e-9), `${fix(rows[0][2])} = ${fix(rows[2][2])}`);
ok('外部病毒 10 层有增益', rows[2][1] > rows[0][1], `${fix(rows[0][1])} → ${fix(rows[2][1])}`);
// 病毒满层 ×4.25，但受腐蚀剥甲等叠加影响，取上限校验
const vGain = rows[2][1] / rows[0][1];
ok('增益不超过 ×4.25', vGain <= 4.3, `×${fix(vGain, 2)}`);

console.log('\n=== 外部剥甲 ===');
for (const s of [0, 50, 100]) {
  const r = compute(w, build.slots[0], hg, 100, { ...base, status: false, armorStrip: s });
  console.log(`  剥甲 ${String(s).padStart(3)}%  护甲 ${fix(r.A.ar0)}  DR ${fix(r.A.dr0 * 100, 1)}%  burst ${fix(r.d.burst)}`);
}
const a0 = compute(w, build.slots[0], hg, 100, { ...base, status: false, armorStrip: 0 });
const a100 = compute(w, build.slots[0], hg, 100, { ...base, status: false, armorStrip: 100 });
ok('剥甲 100% 后 DR 为 0', a100.A.dr0 === 0, fix(a100.A.dr0));
ok('剥甲 100% 等同于裸伤', near(a100.d.toHealth, a100.A.perShotShield, 1e-9), `${fix(a100.d.toHealth)} vs ${fix(a100.A.perShotShield)}`);
ok('剥甲提高 burst', a100.d.burst > a0.d.burst, `${fix(a0.d.burst)} → ${fix(a100.d.burst)}`);

console.log('\n=== 爆头 / 暴击开关 ===');
const h1 = compute(w, build.slots[0], hg, 100, { ...base, status: false });
const h2 = compute(w, build.slots[0], hg, 100, { ...base, status: false, headshot: true });
ok('爆头正好 ×2', near(h2.d.burst, h1.d.burst * 2, 1e-9), `${fix(h1.d.burst)} → ${fix(h2.d.burst)}`);
const nc = compute(w, build.slots[0], hg, 100, { ...base, status: false, crit: false });
ok('关暴击后 critMul=1', nc.A.critMul === 1, fix(nc.A.critMul));
ok('关暴击后伤害下降', nc.d.burst < h1.d.burst, `${fix(h1.d.burst)} → ${fix(nc.d.burst)}`);

console.log('\n=== 时间窗口 ===');
for (const t of [3, 10, 30]) {
  const r = compute(w, build.slots[0], hg, 200, { ...base, window: t });
  console.log(`  ${String(t).padStart(2)} 秒  含状态 DPS ${fix(r.s ? r.s.dps : 0)}  击杀 ${r.s && r.s.kill !== null ? fix(r.s.kill, 2) + 's' : '否'}`);
}
const t3 = compute(w, build.slots[0], hg, 200, { ...base, window: 3 });
const t30 = compute(w, build.slots[0], hg, 200, { ...base, window: 30 });
ok('窗口越长 DPS 越接近稳态', t30.s.dps >= t3.s.dps * 0.95, `${fix(t3.s.dps)} → ${fix(t30.s.dps)}`);

console.log('\n=== 组合：病毒10 + 剥甲100% + 爆头 ===');
const all = compute(w, build.slots[0], hg, 200, { ...base, extViral: 10, armorStrip: 100, headshot: true });
console.log(`  含状态 DPS ${fix(all.s.dps)}  击杀 ${all.s.kill !== null ? fix(all.s.kill, 2) + 's' : '否'}`);
ok('组合生效且有限', isFinite(all.s.dps) && all.s.dps > 0, fix(all.s.dps));

console.log(`\n${fail === 0 ? '全部通过' : fail + ' 项失败'}`);
process.exit(fail ? 1 : 0);
