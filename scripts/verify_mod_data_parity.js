#!/usr/bin/env node
'use strict';

/*
 * Verifies the raw Mod catalogue and the default-melee-combo table used by
 * native DamageKit against the literals shipped in the warframe-damage site
 * source. It also verifies that the web bundle and the source used to build
 * the native iOS data folder are byte-for-byte the same for every calculation
 * input they share.
 *
 * This intentionally does not boot the website, invoke its calculator, or
 * overwrite any resource.  It only extracts the data literal and compares
 * every record recursively.  A successful result therefore means the native
 * app starts from the same raw input data; it says nothing about formula or
 * final-result parity.
 *
 * Usage: node scripts/verify_mod_data_parity.js
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const canonicalSite = path.join(root, 'server', 'site');
const webSite = path.join(root, 'web', 'app', 'site');
const sourcePath = path.join(canonicalSite, 'min.js');
const nativePath = path.join(root, 'Packages', 'DamageKit', 'Sources', 'DamageKit', 'Resources', 'mods.json');
const stanceOrderPath = path.join(root, 'Packages', 'DamageKit', 'Sources', 'DamageKit',
  'Resources', 'stance-combo-order.json');
const defaultMeleeStancesPath = path.join(root, 'Packages', 'DamageKit', 'Sources', 'DamageKit',
  'Resources', 'default-melee-stances.json');

function extractArrayLiteral(source, marker) {
  const markerAt = source.indexOf(marker);
  if (markerAt < 0) throw new Error(`missing marker: ${marker}`);
  let index = markerAt + marker.length;
  if (source[index] !== '[') throw new Error(`expected an array after ${marker}`);

  const start = index;
  let depth = 0;
  let quote = null;
  for (; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (character === '\\') { index += 1; continue; }
      if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'" || character === '`') {
      quote = character;
      continue;
    }
    if (character === '[' || character === '{') { depth += 1; continue; }
    if (character === ']' || character === '}') {
      depth -= 1;
      if (depth === 0 && character === ']') return source.slice(start, index + 1);
    }
  }
  throw new Error(`unterminated array after ${marker}`);
}

function extractObjectLiteral(source, marker) {
  const markerAt = source.indexOf(marker);
  if (markerAt < 0) throw new Error(`missing marker: ${marker}`);
  let index = markerAt + marker.length;
  if (source[index] !== '{') throw new Error(`expected an object after ${marker}`);

  const start = index;
  let depth = 0;
  let quote = null;
  for (; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (character === '\\') { index += 1; continue; }
      if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'" || character === '`') {
      quote = character;
      continue;
    }
    if (character === '[' || character === '{') { depth += 1; continue; }
    if (character === ']' || character === '}') {
      depth -= 1;
      if (depth === 0 && character === '}') return source.slice(start, index + 1);
    }
  }
  throw new Error(`unterminated object after ${marker}`);
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}

function digest(value) {
  return crypto.createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}

function fileDigest(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function relative(file) {
  return path.relative(root, file).replace(/\\/g, '/');
}

function compareMirroredFile(relativePath) {
  const canonicalPath = path.join(canonicalSite, relativePath);
  const webPath = path.join(webSite, relativePath);
  const canonicalExists = fs.existsSync(canonicalPath);
  const webExists = fs.existsSync(webPath);
  const equal = canonicalExists && webExists
    && fileDigest(canonicalPath) === fileDigest(webPath);
  return {
    path: relativePath.replace(/\\/g, '/'),
    canonical: relative(canonicalPath),
    web: relative(webPath),
    canonicalExists,
    webExists,
    equal,
  };
}

function firstDifference(left, right, trail = '$') {
  if (Object.is(left, right)) return null;
  if (Array.isArray(left) && Array.isArray(right)) {
    if (left.length !== right.length) return `${trail}.length: ${left.length} !== ${right.length}`;
    for (let index = 0; index < left.length; index += 1) {
      const difference = firstDifference(left[index], right[index], `${trail}[${index}]`);
      if (difference) return difference;
    }
    return null;
  }
  if (left && right && typeof left === 'object' && typeof right === 'object') {
    const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort();
    for (const key of keys) {
      if (!(key in left)) return `${trail}.${key}: missing from website`;
      if (!(key in right)) return `${trail}.${key}: missing from native resource`;
      const difference = firstDifference(left[key], right[key], `${trail}.${key}`);
      if (difference) return difference;
    }
    return null;
  }
  return `${trail}: ${JSON.stringify(left)} !== ${JSON.stringify(right)}`;
}

const websiteSource = fs.readFileSync(sourcePath, 'utf8');
const websiteLiteral = extractArrayLiteral(websiteSource, 'modsProps=');
const websiteMods = vm.runInNewContext(`(${websiteLiteral})`, Object.create(null));
const nativeMods = JSON.parse(fs.readFileSync(nativePath, 'utf8'));
const difference = firstDifference(websiteMods, nativeMods);
const websiteStanceOrder = Object.fromEntries(websiteMods
  .filter(mod => mod.type === 'stance' && mod.action && mod.action.stances)
  .map(mod => [mod.name, Object.keys(mod.action.stances)]));
const nativeStanceOrder = JSON.parse(fs.readFileSync(stanceOrderPath, 'utf8'));
const stanceOrderDifference = firstDifference(websiteStanceOrder, nativeStanceOrder,
  '$.stanceComboOrder');
const websiteDefaultMeleeLiteral = extractObjectLiteral(websiteSource, 'default_MeleeStances=');
// The minified source stores these damage-type labels as identifiers.  They
// are values in this table, not calculator code, so bind only those literals.
const websiteDefaultMeleeStances = vm.runInNewContext(`(${websiteDefaultMeleeLiteral})`, {
  impact: 'impact', puncture: 'puncture', slash: 'slash', heat: 'heat',
  cold: 'cold', electricity: 'electricity', toxin: 'toxin',
});
const nativeDefaultMeleeStances = JSON.parse(fs.readFileSync(defaultMeleeStancesPath, 'utf8'));
const defaultMeleeStanceDifference = firstDifference(
  websiteDefaultMeleeStances,
  nativeDefaultMeleeStances,
  '$.defaultMeleeStances'
);

// The iOS bundle is generated from server/site while the browser bundle is
// web/app/site.  Treat the source tree as one coherent input only when the
// formula script, raw tables, and every weapon record named by weapons.json
// match byte-for-byte.  This catches a stale copied web bundle before a
// DamageKit parity result can be mistaken for a data/formula disagreement.
const mirrorFiles = [
  'min.js',
  'weapons.json',
  'zh.js',
  'data/json/enemies-min.json',
].map(compareMirroredFile);
const canonicalManifest = JSON.parse(fs.readFileSync(path.join(canonicalSite, 'weapons.json'), 'utf8'));
const weaponMirrors = Object.entries(canonicalManifest).map(([weapon, filename]) => ({
  weapon,
  ...compareMirroredFile(path.join('weapons', filename)),
}));
const siteMirrorEqual = mirrorFiles.every(row => row.equal)
  && weaponMirrors.every(row => row.equal);

const summary = {
  source: path.relative(root, sourcePath).replace(/\\/g, '/'),
  resource: path.relative(root, nativePath).replace(/\\/g, '/'),
  websiteCount: websiteMods.length,
  nativeCount: nativeMods.length,
  websiteDigest: digest(websiteMods),
  nativeDigest: digest(nativeMods),
  equal: difference === null,
  firstDifference: difference,
  stanceOrderResource: path.relative(root, stanceOrderPath).replace(/\\/g, '/'),
  websiteStanceModCount: Object.keys(websiteStanceOrder).length,
  nativeStanceModCount: Object.keys(nativeStanceOrder).length,
  stanceComboOrderEqual: stanceOrderDifference === null,
  firstStanceComboOrderDifference: stanceOrderDifference,
  defaultMeleeStanceResource: path.relative(root, defaultMeleeStancesPath).replace(/\\/g, '/'),
  websiteDefaultMeleeStanceCount: Object.keys(websiteDefaultMeleeStances).length,
  nativeDefaultMeleeStanceCount: Object.keys(nativeDefaultMeleeStances).length,
  websiteDefaultMeleeStanceDigest: digest(websiteDefaultMeleeStances),
  nativeDefaultMeleeStanceDigest: digest(nativeDefaultMeleeStances),
  defaultMeleeStancesEqual: defaultMeleeStanceDifference === null,
  firstDefaultMeleeStanceDifference: defaultMeleeStanceDifference,
  siteMirror: {
    canonical: relative(canonicalSite),
    web: relative(webSite),
    equal: siteMirrorEqual,
    files: mirrorFiles,
    weaponCount: weaponMirrors.length,
    mismatchedWeapons: weaponMirrors.filter(row => !row.equal),
  },
};

process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
if (!summary.equal || !summary.stanceComboOrderEqual || !summary.defaultMeleeStancesEqual
    || !summary.siteMirror.equal) {
  process.exitCode = 1;
}
