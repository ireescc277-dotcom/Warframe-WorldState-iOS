#!/usr/bin/env node
/*
 * For representative rifle / secondary / shotgun / melee / custom-buff cases,
 * execute the checked-in website twice with the same deterministic queue:
 *
 *   1. its shipped setQuantize (Modded Base / 16);
 *   2. only that helper replaced in memory with the documented /32 branch.
 *
 * This never ships in the iOS app. It is evidence that an observed direct-hit
 * difference is attributable to this one website branch, rather than a vague
 * claim based solely on a close-looking number.
 */
'use strict';

const child = require('child_process');
const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.resolve(__dirname, '..');
const PACKAGE = path.join(ROOT, 'Packages', 'DamageKit');
const DATA_ROOT = path.join(ROOT, 'server', 'site');
const CASE_FILE = path.join(PACKAGE, 'Parity', 'website-cases.json');
const verify = process.argv.includes('--verify');
const SAMPLE_COUNT = 61;
const CASE_IDS = [
  'braton-baseline-lancer-l1',
  'braton-base-crit-multishot-lancer-l50',
  'braton-viral-status-lancer-l50',
  'lex-prime-base-crit-lancer-l50',
  'lex-prime-flat-critical-chance-lancer-l50',
  'hek-pellet-crit-multishot-lancer-l50',
  'skana-melee-base-crit-lancer-l50',
  'lex-prime-custom-direct-stats-lancer-l50',
  'lex-prime-roar-lancer-l50',
  'lex-prime-toxic-lash-direct-armor-lancer-l50',
  'dex-pixia-ability-combo-lancer-l50',
  'dex-pixia-global-strength-direct-lancer-l50',
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function mean(values) {
  return values.reduce((total, value) => total + value, 0) / Math.max(values.length, 1);
}

function directLayer(testCase) {
  const match = /^(?:queueTotalDps|queueDirectTotal)\.(health|armor|shield|overguard)$/.exec(
    String(testCase.compare?.siteMetric || ''),
  );
  if (!match) throw new Error(`${testCase.id}: unsupported site metric`);
  return match[1];
}

function queueDirect(rows) {
  return rows.reduce((total, row) => total
    + Number(row?.curr_dmg || 0)
    + Number(row?.xataTotal || 0)
    + Number(row?.dmgOnStatusEff || 0)
    + Number(row?.toxicLash?.direct_hit || 0), 0);
}

function queueTotalDps(rows) {
  const queueLength = Number(K.W?.queueLength);
  if (!Number.isFinite(queueLength) || queueLength <= 0) {
    throw new Error('website queue length is not a positive number');
  }
  return rows.reduce((total, row) => total + Number(row?.totalDmg || 0), 0) / queueLength;
}

function nativeMetrics(testCase) {
  const result = child.spawnSync(
    'swift',
    ['run', '-c', 'debug', 'damagekit-cli', '-', '--data-root', DATA_ROOT, '--compact'],
    {
      cwd: PACKAGE,
      input: JSON.stringify(testCase.native),
      encoding: 'utf8',
      maxBuffer: 8 * 1024 * 1024,
    },
  );
  if (result.status !== 0) {
    throw new Error(`${testCase.id}: DamageKit failed: ${(result.stderr || result.stdout || '').trim()}`);
  }
  const output = JSON.parse((result.stdout || '').trim());
  const attack = (output.attacks || []).find(item => item.attack === testCase.attack);
  if (!attack || !Number.isFinite(attack.targetDirectDamage) || !Number.isFinite(attack.targetDps)) {
    throw new Error(`${testCase.id}: DamageKit target metrics missing`);
  }
  return {
    direct: attack.targetDirectDamage,
    totalDps: attack.targetDps,
  };
}

async function websiteMetrics(testCase, seed, denominator) {
  const strategist = K.W?.WFOpt;
  const original = K.W?.setQuantize;
  if (denominator !== null) {
    assert(typeof original === 'function', 'website setQuantize missing');
    K.W.setQuantize = (total, value) => {
      if (value === 0) return 0;
      const scale = total / denominator;
      return Math.round(value / scale) * scale;
    };
  }
  if (strategist?.enableStrat) strategist.enableStrat(seed);
  try {
    const site = await K.calc(testCase.site);
    assert(!site.lostMods?.length, `${testCase.id}: website rejected a Mod`);
    const attack = (site.attacks || []).find(item => item.name === testCase.attack);
    assert(attack, `${testCase.id}: website attack missing`);
    const rows = K.W?.arrInfo?.[directLayer(testCase)]?.[attack.name];
    assert(Array.isArray(rows), `${testCase.id}: website direct queue missing`);
    return {
      direct: queueDirect(rows),
      totalDps: queueTotalDps(rows),
    };
  } finally {
    if (strategist?.disableStrat) strategist.disableStrat();
    if (denominator !== null) K.W.setQuantize = original;
  }
}

async function main() {
  const source = fs.readFileSync(path.join(ROOT, 'server', 'site', 'min.js'), 'utf8');
  assert(source.includes('a/=16;return Math.round(d/a)*a'), 'website /16 branch missing');

  const suite = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  const cases = CASE_IDS.map(id => {
    const testCase = suite.cases.find(item => item.id === id);
    assert(testCase, `missing parity fixture: ${id}`);
    return testCase;
  });
  await K.boot();

  const rows = [];
  for (const testCase of cases) {
    const original = [];
    const mission = [];
    for (let seed = 1; seed <= SAMPLE_COUNT; seed += 1) {
      original.push(await websiteMetrics(testCase, seed, null));
      mission.push(await websiteMetrics(testCase, seed, 32));
    }
    const native = nativeMetrics(testCase);
    const websiteDirectMean = mean(original.map(row => row.direct));
    const patchedDirectMean = mean(mission.map(row => row.direct));
    const websiteTotalDpsMean = mean(original.map(row => row.totalDps));
    const patchedTotalDpsMean = mean(mission.map(row => row.totalDps));
    rows.push({
      id: testCase.id,
      native: native.direct,
      websiteDirectMean,
      websiteMissionGridDirectMean: patchedDirectMean,
      originalRelativeDifference: Math.abs(native.direct - websiteDirectMean) / websiteDirectMean,
      missionGridRelativeDifference: Math.abs(native.direct - patchedDirectMean) / patchedDirectMean,
      nativeTargetDps: native.totalDps,
      websiteQueueTotalDpsMean: websiteTotalDpsMean,
      websiteMissionGridQueueTotalDpsMean: patchedTotalDpsMean,
      totalOriginalRelativeDifference: Math.abs(native.totalDps - websiteTotalDpsMean) / websiteTotalDpsMean,
      totalMissionGridRelativeDifference: Math.abs(native.totalDps - patchedTotalDpsMean)
        / patchedTotalDpsMean,
    });
  }

  if (verify) {
    for (const row of rows) {
      assert(row.originalRelativeDifference > 0.05,
        `${row.id}: shipped /16 branch no longer exceeds 5%`);
      assert(row.missionGridRelativeDifference <= 0.05,
        `${row.id}: /32 counterfactual remains outside 5%`);
    }
  }
  process.stdout.write(JSON.stringify({ samples: SAMPLE_COUNT, verified: verify, cases: rows }, null, 2) + '\n');
}

main().then(() => process.exit(0)).catch(error => {
  process.stderr.write((error?.stack || String(error)) + '\n');
  process.exit(1);
});
