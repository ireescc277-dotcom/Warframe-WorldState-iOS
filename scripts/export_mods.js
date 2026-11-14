// 从 web/app/site/min.js 里把 modsProps 这个**数据数组**抠出来，导出成 mods.json。
// 只做字面量提取（括号配对 + 字符串状态机），不执行 min.js 的任何逻辑。
// 用法: node scripts/export_mods.js
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
// `server/site` is the canonical source used both by the local calculation
// kernel and by the iOS DamageData build. `web/app/site` is a copied browser
// bundle and is checked for byte parity by verify_mod_data_parity.js.
const SRC = path.join(ROOT, 'server/site/min.js');
const OUT = path.join(ROOT, 'Packages/DamageKit/Sources/DamageKit/Resources/mods.json');
// JSON objects lose their insertion order when decoded into a Swift
// Dictionary.  Stance combo order is observable UI behavior: the website
// selects the first combo when a stance is equipped.  Export this small index
// from the same `modsProps` data so the pure-Swift app can preserve it.
const STANCE_ORDER_OUT = path.join(
  ROOT,
  'Packages/DamageKit/Sources/DamageKit/Resources/stance-combo-order.json'
);
// The website has a second, observable stance table for an unmodded melee
// weapon and for every heavy attack.  Export it from the same source instead
// of maintaining a hand-copied Swift formula table.
const DEFAULT_MELEE_STANCES_OUT = path.join(
  ROOT,
  'Packages/DamageKit/Sources/DamageKit/Resources/default-melee-stances.json'
);

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

const stanceComboOrder = Object.fromEntries(
  mods
    .filter((mod) => mod.type === 'stance' && mod.action && mod.action.stances)
    .map((mod) => [mod.name, Object.keys(mod.action.stances)])
);
fs.writeFileSync(STANCE_ORDER_OUT, JSON.stringify(stanceComboOrder, null, 1) + '\n', 'utf8');
console.log('stance combo orders:', Object.keys(stanceComboOrder).length,
  '->', path.relative(ROOT, STANCE_ORDER_OUT));

function extractObjectLiteral(source, marker) {
  const markerAt = source.indexOf(marker);
  if (markerAt < 0) throw new Error(`${marker} not found`);
  let cursor = markerAt + marker.length;
  if (source[cursor] !== '{') throw new Error(`expected { after ${marker}`);
  const start = cursor;
  let depth = 0;
  let quote = null;
  for (; cursor < source.length; cursor++) {
    const character = source[cursor];
    if (quote) {
      if (character === '\\') { cursor++; continue; }
      if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'" || character === '`') { quote = character; continue; }
    if (character === '{' || character === '[') { depth++; continue; }
    if (character === '}' || character === ']') {
      depth--;
      if (depth === 0 && character === '}') return source.slice(start, cursor + 1);
    }
  }
  throw new Error(`unterminated object after ${marker}`);
}

const defaultMeleeLiteral = extractObjectLiteral(src, 'default_MeleeStances=');
// The compact source stores a few status labels as identifiers (`slash`,
// `impact`) rather than string literals.  They are data labels here, not code
// to evaluate from the site runtime.
const stanceSandbox = Object.assign(Object.create(null), {
  impact: 'impact', puncture: 'puncture', slash: 'slash', heat: 'heat',
  cold: 'cold', electricity: 'electricity', toxin: 'toxin',
});
const defaultMeleeStances = vm.runInNewContext('(' + defaultMeleeLiteral + ')', stanceSandbox);
if (!defaultMeleeStances || Array.isArray(defaultMeleeStances)) {
  throw new Error('default_MeleeStances is not an object');
}
fs.writeFileSync(DEFAULT_MELEE_STANCES_OUT,
  JSON.stringify(defaultMeleeStances, null, 1) + '\n', 'utf8');
console.log('default melee stance sequences:', Object.keys(defaultMeleeStances).length,
  '->', path.relative(ROOT, DEFAULT_MELEE_STANCES_OUT));

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
