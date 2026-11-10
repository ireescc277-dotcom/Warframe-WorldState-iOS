// 自检 1：护甲曲线 / 等级缩放 / 阵营克制 / 主角武器数值
const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
global.WF = window.WF;
const __html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(__html.slice(__html.indexOf('const W = WF.w'), __html.indexOf('const state = {')));

const W = window.WF.w, B = window.WF.b;
const ZH = { impact: '冲击', puncture: '穿刺', slash: '切割', heat: '火焰', cold: '冰冻',
  electricity: '电击', toxin: '毒素', blast: '爆炸', radiation: '辐射', magnetic: '磁力',
  viral: '病毒', corrosive: '腐蚀', gas: '毒气' };
const fix = (v, n) => Number(v).toFixed(n);
let fails = 0;
function check(name, got, want, tol) {
  tol = tol === undefined ? 0.01 : tol;
  const ok = Math.abs(got - want) <= tol;
  if (!ok) fails++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(30)} ${fix(got, 3)}  (期望 ${want})`);
}

console.log('=== 敌方护甲减伤曲线 ===');
check('A=0    DR', drOf(0), 0);
check('A=300  DR', drOf(300), 0.3);
check('A=1200 DR', drOf(1200), 0.6);
check('A=2700 DR', drOf(2700), 0.9);
check('A=5400 DR', drOf(5400), 5400 / 5700);

console.log('\n=== 等级缩放 ===');
check('Lv1  血量', scaleHealth(700, 1, 1), 700, 0.5);
check('Lv1  护甲', scaleArmor(500, 1, 1), 500, 0.5);
check('Lv1  护盾', scaleShield(150, 1, 1), 150, 0.5);
check('Lv100 护甲夹上限', scaleArmor(500, 100, 1), 2700, 0.5);
check('低甲夹到 200', scaleArmor(50, 1, 1), 200, 0.5);
check('无甲仍是 0', scaleArmor(0, 100, 1), 0, 0.5);
const h80 = scaleHealth(700, 80, 1), h200 = scaleHealth(700, 200, 1);
const mono = h200 > h80;
if (!mono) fails++;
console.log(`  ${mono ? 'PASS' : 'FAIL'}  血量单调 Lv80 ${Math.round(h80)} → Lv200 ${Math.round(h200)}`);

console.log('\n=== 阵营克制（Update 36 口径）===');
check('Grineer 受冲击', facMult('Grineer', 'impact'), 1.5);
check('Grineer 受腐蚀', facMult('Grineer', 'corrosive'), 1.5);
check('Grineer 无抗性', facMult('Grineer', 'heat'), 1);
check('Kuva Grineer 抗火', facMult('Kuva Grineer', 'heat'), 0.5);
check('Corpus 受磁力', facMult('Corpus', 'magnetic'), 1.5);
check('Orokin 抗辐射', facMult('Orokin', 'radiation'), 0.5);
check('Infested 受火焰', facMult('Infested', 'heat'), 1.5);
check('无阵营 → 1', facMult('', 'heat'), 1);

console.log('\n=== Tenora Prime 配置 A ===');
const tn = B.find(b => b.w.includes('TenoraPrime'));
const w = W[tn.w];
const grineer = { n: 'Heavy Gunner', f: 'Grineer', fk: 'Grineer', hp: 700, ar: 500, sh: 0, bl: 1 };
const corpus = { n: 'Crewman', f: 'Corpus', fk: 'Corpus', hp: 60, ar: 0, sh: 150, bl: 1 };
const r1 = compute(w, tn.slots[0], grineer, 100, { steel: false, status: false });
const A = r1.A;
console.log(`  多重 ${fix(A.ms, 2)}  暴击 ${fix(A.cc, 1)}% ×${fix(A.cm, 2)}  期望 ${fix(A.critMul, 3)}`);
console.log(`  触发 ${fix(A.sc * 100, 1)}%  射速 ${fix(A.fr, 2)}  弹匣 ${A.mag}  装填 ${fix(A.rl, 2)}s`);
console.log(`  护甲 ${Math.round(A.ar0)}  DR ${fix(A.dr0 * 100, 1)}%  每发到血 ${fix(r1.d.toHealth, 1)}`);
console.log(`  直伤 burst ${Math.round(r1.d.burst)}  sustained ${Math.round(r1.d.sust)}`);
console.log('  分项 ' + r1.d.rows.map(x => `${ZH[x.t]} ${fix(x.base, 1)}×${x.f}=${fix(x.vH, 1)}`).join('  '));
const impactRow = r1.d.rows.find(x => x.t === 'impact');
check('冲击吃到 ×1.5', impactRow ? impactRow.f : 0, 1.5);
const coldRow = r1.d.rows.find(x => x.t === 'cold');
check('冰伤无克制', coldRow ? coldRow.f : 0, 1);

console.log('\n=== 同配卡对 Lv100 船员（带盾无甲）===');
const r2 = compute(w, tn.slots[0], corpus, 100, { steel: false, status: false });
console.log(`  护盾 ${Math.round(r2.A.sh)}  护甲 ${Math.round(r2.A.ar0)}  每发到盾 ${fix(r2.d.toShield, 1)}  burst ${Math.round(r2.d.burst)}`);
check('无甲目标无减伤', r2.A.ar0, 0);
check('到血等于到盾', r2.d.toHealth, r2.d.toShield, 0.01);

console.log('\n=== 钢铁之路 +100 ===');
const r3 = compute(w, tn.slots[0], grineer, 100, { steel: true, status: false });
console.log(`  等级 ${r3.A.lv}  血量 ${Math.round(r3.A.hp)}  护甲 ${Math.round(r3.A.ar0)}  burst ${Math.round(r3.d.burst)}`);
if (r3.A.hp <= r1.A.hp) { fails++; console.log('  FAIL 血量未随等级上升'); }

console.log(`\n${fails === 0 ? '全部通过' : fails + ' 项失败'}`);
process.exit(fails ? 1 : 0);
