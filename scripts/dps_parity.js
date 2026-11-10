// 服务端内核与页面内联内核的对拍。
// 页面里那段是既有的、已经用 5 个自检跑过的实现；server/engine.js 是从它
// 机械抽出来的。这里对全部配卡 × 若干目标/等级/开关逐项比数，任何一项
// 不相等就说明抽取过程改坏了东西。
const fs = require('fs');
const path = require('path');
const {makeEngine} = require(path.join(__dirname, '..', 'server', 'engine.js'));

global.window = {};
eval(fs.readFileSync(path.join(__dirname, '..', 'web', 'dps', 'data.js'), 'utf8'));
const WF = window.WF;

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'dps', 'index.html'), 'utf8');
eval(html.slice(html.indexOf('const W = WF.w'), html.indexOf('const state = {')));
const ref = {compute, direct, simulate, assemble, effWeapon};

const eng = makeEngine(WF);
const W = WF.w, B = WF.b, E = WF.e;

const opts = [
  {steel: false, status: true,  extViral: 0, armorStrip: 0, window: 10,
   headshot: false, crit: true, incarnon: false, dmgBuff: 0, ccBuff: 0},
  {steel: true,  status: true,  extViral: 3, armorStrip: 50, window: 10,
   headshot: true, crit: true, incarnon: true, dmgBuff: 120, ccBuff: 40},
  {steel: false, status: false, extViral: 0, armorStrip: 0, window: 6,
   headshot: false, crit: false, incarnon: false, dmgBuff: 0, ccBuff: 0},
];
const targets = [
  E.find(e => e.n === 'Heavy Gunner'),
  E.find(e => e.n === 'Corrupted Bombard'),
  E.find(e => e.n === 'Charger'),
  {n: 'x', f: 'Grineer', hp: 1e9, ar: 0, sh: 0, fk: 'Grineer'},   // 裸伤基准
].filter(Boolean);
const levels = [1, 30, 100, 250];

const pad8 = a => { const x = (a || []).slice(0, 8); while (x.length < 8) x.push(null); return x; };
const keys = ['burst', 'sust', 'toHealth', 'toShield'];

let cases = 0, bad = 0;
const fails = [];
function cmp(label, a, b) {
  if (!Object.is(a, b) && Math.abs((a || 0) - (b || 0)) > 1e-9) {
    bad++;
    if (fails.length < 12) fails.push(`${label}: 页面 ${a} ≠ 服务端 ${b}`);
  }
}

for (const b of B) {
  const w = W[b.w];
  if (!w) continue;
  for (let ci = 0; ci < b.slots.length; ci++) {
    const slots = pad8(b.slots[ci]);
    for (const t of targets) {
      for (const lv of levels) {
        for (const o of opts) {
          const A = ref.compute(w, slots, t, lv, o, b.w);
          const Bn = eng.compute(w, slots, t, lv, o, b.w);
          cases++;
          for (const k of keys) cmp(`${b.w}/${ci}/${t.n}/${lv}/${k}`, A.d[k], Bn.d[k]);
          cmp(`${b.w}/${ci}/${t.n}/${lv}/raw`, A.A.perShotShield, Bn.A.perShotShield);
          cmp(`${b.w}/${ci}/${t.n}/${lv}/hp`, A.A.hp, Bn.A.hp);
          cmp(`${b.w}/${ci}/${t.n}/${lv}/ar`, A.A.ar0, Bn.A.ar0);
          if (o.status) {
            cmp(`${b.w}/${ci}/${t.n}/${lv}/dps`, A.s.dps, Bn.s.dps);
            cmp(`${b.w}/${ci}/${t.n}/${lv}/ddps`, A.s.directDps, Bn.s.directDps);
            cmp(`${b.w}/${ci}/${t.n}/${lv}/dot`, A.s.dotDps, Bn.s.dotDps);
            cmp(`${b.w}/${ci}/${t.n}/${lv}/kill`, A.s.kill, Bn.s.kill);
          } else {
            cmp(`${b.w}/${ci}/${t.n}/${lv}/s`, A.s, Bn.s);
          }
        }
      }
    }
  }
}

console.log(`对拍 ${cases} 组（配卡 × 目标 × 等级 × 开关），字段逐项比较`);
if (bad) {
  console.log(`不一致 ${bad} 处：`);
  fails.forEach(f => console.log('  ' + f));
  process.exit(1);
}
console.log('全部一致');
