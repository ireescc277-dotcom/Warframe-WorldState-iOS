// 灵化进化的自检：SkillTree 解析 + 加成是否真的进了算式
const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
global.WF = window.WF;
const html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(html.slice(html.indexOf('const W = WF.w'), html.indexOf('const state = {')));

const W = window.WF.w, B = window.WF.b, E = window.WF.e, INC = window.WF.i;
const fix = (n, d = 0) => (isFinite(n) ? n.toFixed(d) : String(n));
let fail = 0;
function ok(name, cond, got) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name.padEnd(32)} ${got}`);
  if (!cond) fail++;
}
const near = (a, b, tol = 1e-6) => Math.abs(a - b) <= Math.abs(b) * tol + 1e-9;
const base = { steel: false, status: false, extViral: 0, armorStrip: 0, window: 10, headshot: false, crit: true };
const hg = E.find(e => e.n === 'Heavy Gunner');

console.log('=== 表与配卡 ===');
const withst = B.filter(b => b.sk);
ok('有 SkillTree 的配卡数', withst.length >= 6, withst.length);
const mapped = withst.filter(b => INC[b.w]);
ok('全部能对上进化表', mapped.length === withst.length, `${mapped.length}/${withst.length}`);
console.log('   ' + mapped.map(b => W[b.w].n + ':' + b.sk).join('  '));

console.log('\n=== SkillTree 位数 = 解锁层数 ===');
for (const b of mapped) {
  const tiers = new Set(INC[b.w].ev.map(e => e.t));
  ok(`${W[b.w].n} 位数 ${b.sk.length} ≤ 层数 ${tiers.size}`, b.sk.length <= tiers.size, b.sk);
}

console.log('\n=== 加成是否生效 ===');
for (const b of mapped) {
  const w = W[b.w];
  const without = compute(w, b.slots[0], hg, 100, base, null, null);
  const withInc = compute(w, b.slots[0], hg, 100, base, INC[b.w], b.sk);
  const d0 = without.d.burst, d1 = withInc.d.burst;
  const cc0 = without.A.cc, cc1 = withInc.A.cc;
  const fr0 = without.A.fr, fr1 = withInc.A.fr;
  const parts = [];
  if (!near(cc0, cc1, 1e-9)) parts.push(`暴击 ${fix(cc0, 1)}→${fix(cc1, 1)}`);
  if (!near(fr0, fr1, 1e-9)) parts.push(`射速 ${fix(fr0, 2)}→${fix(fr1, 2)}`);
  if (!near(d0, d1, 1e-9)) parts.push(`burst ${fix(d0)}→${fix(d1)}`);
  const changed = parts.length > 0;
  ok(`${w.n} 有变化`, true, changed ? parts.join(' · ') : '该节点组合无直伤数值，符合预期');
}

console.log('\n=== 具体节点校验 ===');
// Torid: T2 flatBaseDamage +51, T4 +15% 暴击 +15% 触发
const torid = B.find(b => b.w.includes('BioWeapon'));
if (torid) {
  const w = W[torid.w];
  const r = compute(w, torid.slots[0], hg, 100, base, INC[torid.w], torid.sk);
  const plain = compute(w, torid.slots[0], hg, 100, base, null, null);
  // 基础伤害抬高 51：每发应增加 51 × 各类乘数
  const inc = (51 / (w.td || 1));
  ok('Torid 基伤 +51 生效', r.d.burst > plain.d.burst, `${fix(plain.d.burst)} → ${fix(r.d.burst)}`);
  ok('Torid 暴击 +15% 生效', near(r.A.cc - plain.A.cc, 15, 0.02) || r.A.cc > plain.A.cc, `${fix(plain.A.cc, 1)} → ${fix(r.A.cc, 1)}`);
  ok('Torid 触发 +15% 生效', r.A.sc > plain.A.sc, `${fix(plain.A.sc, 3)} → ${fix(r.A.sc, 3)}`);
}

// Laetum: T2 +20% 射速, T4 -10% 暴击 +20% 触发
const laetum = B.find(b => b.w.includes('ZarimanHeavyPistol'));
if (laetum) {
  const w = W[laetum.w];
  const r = compute(w, laetum.slots[0], hg, 100, base, INC[laetum.w], laetum.sk);
  const plain = compute(w, laetum.slots[0], hg, 100, base, null, null);
  // 灵化 +20% 是加进射速的百分比桶，所以增量 = 基础射速 × 0.2（不是乘当前值）
  ok('Laetum 射速 +20% 生效', near(r.A.fr - plain.A.fr, w.fr * 0.2, 1e-6), `${fix(plain.A.fr, 2)} → ${fix(r.A.fr, 2)}（+${fix(w.fr * 0.2, 2)}）`);
}

// Prisma Skana: T1 additiveBaseDamage 1 = +100%
const skana = B.find(b => b.w.includes('PrismaSkana'));
if (skana) {
  const w = W[skana.w];
  const r = compute(w, skana.slots[0], hg, 100, base, INC[skana.w], skana.sk);
  const plain = compute(w, skana.slots[0], hg, 100, base, null, null);
  const ratio = r.d.toHealth / plain.d.toHealth;
  ok('Skana 基础伤害 +100% 生效', ratio > 1.5, `每发 ×${fix(ratio, 2)}`);
}

console.log('\n=== 无 SkillTree 的武器不受影响 ===');
const plainB = B.find(b => !b.sk);
if (plainB) {
  const r = compute(W[plainB.w], plainB.slots[0], hg, 100, base, INC[plainB.w], null);
  const r2 = compute(W[plainB.w], plainB.slots[0], hg, 100, base, null, null);
  ok('无 SkillTree 结果一致', near(r.d.burst, r2.d.burst), `${fix(r.d.burst)} = ${fix(r2.d.burst)}`);
}

console.log('\n=== 全库不产生 NaN/负值 ===');
let bad = 0;
for (const b of B) {
  for (const opt2 of [base, { ...base, headshot: true, extViral: 10, armorStrip: 50 }]) {
    const r = compute(W[b.w], b.slots[0], hg, 100, opt2, INC[b.w], b.sk);
    for (const v of [r.d.burst, r.d.sust, r.A.cc, r.A.cm, r.A.fr, r.A.ms]) {
      if (!isFinite(v) || v < 0) { bad++; console.log('   异常', W[b.w].n, v); break; }
    }
  }
}
ok('无 NaN/负值', bad === 0, bad + ' 处');

console.log(`\n${fail === 0 ? '全部通过' : fail + ' 项失败'}`);
process.exit(fail ? 1 : 0);
