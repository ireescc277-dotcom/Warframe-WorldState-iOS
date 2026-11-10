const fs = require('fs');
global.window = {};
eval(fs.readFileSync('web/dps/data.js', 'utf8'));
const __html = fs.readFileSync('web/dps/index.html', 'utf8');
eval(__html.slice(__html.indexOf('const DT = ['), __html.indexOf('// ---------- 状态 ----------')));
const W = window.WF.w, M = window.WF.m, B = window.WF.b;
globalThis.state = { sp: false };
const fix = (v, n) => Number(v).toFixed(n);

// 找一个 mod：按英文名
function findMod(name) {
  for (const uid in M) if (M[uid].n === name) return uid;
  return null;
}
const goal = { n: 'x', f: 'Grineer', hp: 1e9, ar: 0, sh: 0, ht: 'Flesh', at: 'none', st: 'none' };

function comps(w, mods) {
  const slots = mods.map(x => ({ m: findMod(x[0]), lv: x[1] }));
  const r = compute(w, slots, goal, 1, 'linear');
  return r;
}

console.log('=== 元素合流 ===');
const trumna = Object.keys(W).find(u => W[u].n === 'Trumna');
let r = comps(W[trumna], []);
console.log('  Trumna 裸：' + r.comps.map(c => c.t + ':' + fix(c.v, 1)).join(' '));
r = comps(W[trumna], [['Cryo Rounds', 5]]);
console.log('  天生火焰 + 冰 mod → ' + r.comps.map(c => c.t + ':' + fix(c.v, 1)).join(' '));
r = comps(W[trumna], [['Cryo Rounds', 5], ['Infected Clip', 5]]);
console.log('  + 毒 mod → ' + r.comps.map(c => c.t + ':' + fix(c.v, 1)).join(' '));

const quellor = Object.keys(W).find(u => W[u].n === 'Quellor');
r = comps(W[quellor], [['Infected Clip', 5]]);
console.log('  Quellor(天生冰) + 毒 mod → ' + r.comps.map(c => c.t + ':' + fix(c.v, 1)).join(' '));

console.log('');
console.log('=== 霰弹枪（多重 = 弹丸数）===');
const strun = Object.keys(W).find(u => W[u].n === 'Strun Prime') || Object.keys(W).find(u => W[u].n && W[u].n.includes('Strun'));
console.log('  ' + W[strun].n + ' 弹丸 ' + W[strun].ms + ' 基伤 ' + W[strun].td);
r = comps(W[strun], [['Point Blank', 5], ['Hell\'s Chamber', 5]]);
console.log('  ms ' + fix(r.ms, 2) + '  每发 ' + fix(r.perShotRaw, 0) + '  burst ' + fix(r.burst, 0));

console.log('');
console.log('=== 近战 ===');
const melee = Object.keys(W).find(u => W[u].n === 'Nikana Prime');
r = comps(W[melee], [['Pressure Point', 5], ['Fury', 5]]);
console.log('  ' + W[melee].n + ' 射速 ' + fix(r.fr, 2) + '  每发 ' + fix(r.perShotRaw, 0) + '  sustained ' + fix(r.sust, 0));

console.log('');
console.log('=== 全库跑一遍，看有没有 NaN / 0 ===');
let bad = 0, zero = 0, ok = 0;
for (const b of B) {
  const w = W[b.w];
  for (const slots of b.slots) {
    const x = compute(w, slots, goal, 1, 'linear');
    if (!isFinite(x.burst) || !isFinite(x.sust)) { bad++; continue; }
    if (x.burst <= 0) { zero++; continue; }
    ok++;
  }
}
console.log('  正常 ' + ok + ' | NaN ' + bad + ' | 零伤害 ' + zero + ' | 配卡总数 ' + B.reduce((s, b) => s + b.slots.length, 0));
