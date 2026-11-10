// 自检 2：状态模拟（病毒叠层 / 腐蚀剥甲 / DoT / 边界）
const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
global.WF = window.WF;
const __html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(__html.slice(__html.indexOf('const W = WF.w'), __html.indexOf('const state = {')));

const W = window.WF.w, M = window.WF.m, B = window.WF.b;
const fix = (v, n) => Number(v).toFixed(n);
let fails = 0;
function ok(name, cond, detail) {
  if (!cond) fails++;
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name.padEnd(34)} ${detail || ''}`);
}
function uidOf(name) {
  for (const u in M) if (M[u].n === name) return u;
  return null;
}

const tn = B.find(b => b.w.includes('TenoraPrime'));
const w = W[tn.w];
const hg = { n: 'Heavy Gunner', f: 'Grineer', fk: 'Grineer', hp: 300, ar: 500, sh: 0, bl: 1 };
const noArmor = { n: 'Lancer', f: 'Grineer', fk: 'Grineer', hp: 300, ar: 0, sh: 0, bl: 1 };

const base = JSON.parse(JSON.stringify(tn.slots[0]));
const viralSlots = JSON.parse(JSON.stringify(base));
viralSlots[5] = { m: uidOf('Contagious Spread'), lv: 5 };

const corrSlots = JSON.parse(JSON.stringify(base));
corrSlots[3] = { m: uidOf('Charged Shell'), lv: 5 };
corrSlots[5] = { m: uidOf('Contagious Spread'), lv: 5 };

console.log('=== 元素合流 ===');
const aV = compute(w, viralSlots, hg, 100, { steel: false, status: false }).A;
const aC = compute(w, corrSlots, hg, 100, { steel: false, status: false }).A;
const el = A => A.comps.map(c => c.t).sort().join('+');
console.log('  病毒组 ' + el(aV));
console.log('  腐蚀组 ' + el(aC));
ok('冰+毒 → 病毒', el(aV).includes('viral'), el(aV));
ok('电+毒 → 腐蚀', el(aC).includes('corrosive'), el(aC));

console.log('\n=== 病毒叠层 ===');
const dV = compute(w, viralSlots, hg, 100, { steel: false, status: false });
const sV = compute(w, viralSlots, hg, 100, { steel: false, status: true });
console.log(`  直伤 burst ${Math.round(dV.d.burst)} → 含状态 ${Math.round(sV.s.dps)}  (×${fix(sV.s.dps / dV.d.burst, 2)})`);
console.log(`  病毒层 ${sV.s.viralAtEnd}  DoT ${Math.round(sV.s.dotDps)}  TTK ${sV.s.kill === null ? '>10s' : fix(sV.s.kill, 2) + 's'}`);
ok('病毒叠到 10 层', sV.s.viralAtEnd >= 9, String(sV.s.viralAtEnd));
ok('含状态高于直伤', sV.s.dps > dV.d.burst, `×${fix(sV.s.dps / dV.d.burst, 2)}`);
ok('病毒层 10 时直伤乘数 ≤4.25', sV.s.directDps / dV.d.burst < 4.3, `×${fix(sV.s.directDps / dV.d.burst, 2)}`);

console.log('\n=== 腐蚀剥甲 ===');
const sC = compute(w, corrSlots, hg, 100, { steel: false, status: true });
const dC = compute(w, corrSlots, hg, 100, { steel: false, status: false });
console.log(`  腐蚀层 ${sC.s.corrAtEnd}  剥甲 ${fix(sC.s.stripAtEnd * 100, 0)}%  DPS ${Math.round(sC.s.dps)} vs 直伤 ${Math.round(dC.d.burst)}`);
ok('腐蚀层数 > 0', sC.s.corrAtEnd > 0, String(sC.s.corrAtEnd));
ok('剥甲生效', sC.s.stripAtEnd > 0.5, fix(sC.s.stripAtEnd * 100, 0) + '%');
ok('剥甲后 DPS 提升', sC.s.dps > dC.d.burst, `×${fix(sC.s.dps / dC.d.burst, 2)}`);

console.log('\n=== 触发为 0 时不应有状态 ===');
const w0 = Object.assign({}, w, { sc: 0 });
const s0 = compute(w0, viralSlots, hg, 100, { steel: false, status: true });
ok('无触发 → 无层数', s0.s.viralAtEnd === 0, String(s0.s.viralAtEnd));
ok('无触发 → DoT 为 0', s0.s.dotDps === 0, fix(s0.s.dotDps, 2));

console.log('\n=== 无甲目标 ===');
const sN = compute(w, base, noArmor, 100, { steel: false, status: false });
ok('护甲 0', sN.A.ar0 === 0, String(sN.A.ar0));
ok('无甲时到血=裸伤', Math.abs(sN.d.toHealth - sN.d.toShield) < 0.01, fix(sN.d.toHealth, 1));

console.log('\n=== 全库扫描（含状态）===');
let nan = 0, zero2 = 0, absurd = 0, n = 0;
const t0 = Date.now();
for (const b of B) {
  const ww = W[b.w];
  if (!ww) continue;
  for (const cfg of b.slots) {
    let rr;
    n++;
    try { rr = compute(ww, cfg.slice(0, 8), hg, 100, { steel: false, status: true }); }
    catch (e) { console.log('  异常', ww.n, e.message); nan++; continue; }
    if (!isFinite(rr.d.burst) || !isFinite(rr.s.dps)) { console.log('  NaN', ww.n); nan++; }
    if (rr.d.burst <= 0) zero2++;
    if (rr.s.dps > 1e9) absurd++;
  }
}
ok('无 NaN/异常', nan === 0, String(nan));
ok('无零伤配卡', zero2 === 0, String(zero2));
ok('无离谱值', absurd === 0, String(absurd));
console.log(`  ${n} 套配卡，耗时 ${Date.now() - t0} ms`);

console.log(`\n${fails === 0 ? '全部通过' : fails + ' 项失败'}`);
process.exit(fails ? 1 : 0);
