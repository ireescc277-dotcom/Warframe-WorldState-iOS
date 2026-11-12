#!/usr/bin/env node
/*
 * Development/CI target-state parity runner.
 *
 * This is intentionally separate from compare_damagekit.js.  A party-size
 * choice changes a target's health pool, not its per-hit DPS.  Treating a
 * weapon DPS number as proof of this option would make a no-op look correct.
 * The script asks the checked-in website kernel and the Swift CLI to build the
 * exact same target state, then compares health, armor, shield, and Overguard.
 * It is tooling only; the iOS app neither imports nor executes JavaScript.
 */
'use strict';

const child = require('child_process');
const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.resolve(__dirname, '..');
const PACKAGE = path.join(ROOT, 'Packages', 'DamageKit');
const DATA_ROOT = path.join(ROOT, 'web', 'app', 'site');
const CASE_FILE = path.join(PACKAGE, 'Parity', 'target-state-cases.json');

function runDamageKit(testCase) {
  const request = {
    weapon: 'Braton',
    enemy: testCase.enemy,
    level: testCase.level,
    build: { mods: [] },
    options: {
      window: 1,
      steelPath: !!testCase.steel,
      eximus: !!testCase.eximus,
      squadSize: Number(testCase.party) || 1,
    },
  };
  const result = child.spawnSync(
    'swift',
    ['run', '-c', 'debug', 'damagekit-cli', '-', '--data-root', DATA_ROOT, '--compact'],
    { cwd: PACKAGE, input: JSON.stringify(request), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 },
  );
  if (result.status !== 0) {
    throw new Error(`DamageKit failed: ${(result.stderr || result.stdout || '').trim()}`);
  }
  return JSON.parse((result.stdout || '').trim()).enemyStats;
}

async function runWebsite(testCase) {
  const result = await K.calc({
    weapon: 'Braton',
    enemy: testCase.enemy,
    level: testCase.level,
    steel: !!testCase.steel,
    eximus: !!testCase.eximus,
    party: Number(testCase.party) || 1,
    mods: {},
    opts: { allConds: false, queueLength: 1 },
  });
  return result.target;
}

function compare(site, native, tolerance) {
  const pairs = [
    ['health', 'hp'],
    ['armor', 'ar'],
    ['shield', 'sh'],
    ['overguard', 'og'],
  ];
  const fields = pairs.map(([nativeKey, siteKey]) => {
    const website = Number(site?.[siteKey] ?? 0);
    const damageKit = Number(native?.[nativeKey] ?? 0);
    const relativeDifference = Math.abs(damageKit - website) / Math.max(Math.abs(website), 1);
    return { field: nativeKey, website, damageKit, relativeDifference };
  });
  return { tolerance, matches: fields.every(row => Number.isFinite(row.website)
      && Number.isFinite(row.damageKit) && row.relativeDifference <= tolerance), fields };
}

async function main() {
  const fixture = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  if (!Array.isArray(fixture.cases) || !fixture.cases.length) {
    throw new Error('target-state fixture has no cases');
  }
  await K.boot();
  const rows = [];
  for (const testCase of fixture.cases) {
    process.stderr.write(`[target-parity] ${testCase.id}\n`);
    try {
      // The website kernel owns mutable global DOM state, so keep the two
      // runs ordered.  This is a parity observation, not a performance path.
      const website = await runWebsite(testCase);
      const damageKit = runDamageKit(testCase);
      const agreement = compare(website, damageKit, Number(testCase.tolerance ?? 0.005));
      rows.push({ id: testCase.id, enemy: testCase.enemy, party: testCase.party,
        status: agreement.matches ? 'pass' : 'unresolved', agreement });
    } catch (error) {
      rows.push({ id: testCase.id, enemy: testCase.enemy, party: testCase.party,
        status: 'runner-error', error: error.message });
    }
  }
  const passed = rows.filter(row => row.status === 'pass');
  const report = {
    fixture: path.relative(ROOT, CASE_FILE).replace(/\\/g, '/'),
    passed: passed.length,
    unresolved: rows.length - passed.length,
    cases: rows,
  };
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
  if (report.unresolved) process.exitCode = 1;
}

main().catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
