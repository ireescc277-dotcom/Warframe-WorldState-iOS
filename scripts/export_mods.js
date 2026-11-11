// 从 web/app/site/min.js 里把 modsProps 这个**数据数组**抠出来，导出成 mods.json。
// 只做字面量提取（括号配对 + 字符串状态机），不执行 min.js 的任何逻辑。
// 用法: node scripts/export_mods.js
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'web/app/site/min.js');
const OUT = path.join(ROOT, 'Packages/DamageKit/Sources/DamageKit/Resources/mods.json');

const src = fs.readFileSync(SRC, 'utf8');
const marker = 'modsProps=';
const at = src.indexOf(marker);
if (at < 0) throw new Error('modsProps= not found');
let i = at + marker.length;
if (src[i] !== '[') throw new Error('expected [ after modsProps=');

// 括号配对，跳过字符串/模板串/注释
const start = i;
let depth = 0;
let quote = null;
for (; i < src.length; i++) {
  const c = src[i];
  if (quote) {
    if (c === '\\') { i++; continue; }
    if (c === quote) quote = null;
    continue;
  }
  if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
  if (c === '[' || c === '{') { depth++; continue; }
  if (c === ']' || c === '}') {
    depth--;
    if (depth === 0 && c === ']') { i++; break; }
    continue;
  }
}
const literal = src.slice(start, i);
const mods = vm.runInNewContext('(' + literal + ')', Object.create(null));
if (!Array.isArray(mods)) throw new Error('not an array');

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(mods, null, 1) + '\n', 'utf8');
console.log('mods:', mods.length, '->', path.relative(ROOT, OUT));

// 顺便打印 action 里用到的键，方便核对引擎覆盖范围
const keys = new Map();
for (const m of mods) {
  const a = m.action;
  if (!a) continue;
  for (const k of Object.keys(a)) keys.set(k, (keys.get(k) || 0) + 1);
}
const sorted = [...keys.entries()].sort((a, b) => b[1] - a[1]);
console.log('action keys:', sorted.length);
for (const [k, n] of sorted) console.log(String(n).padStart(5), k);
