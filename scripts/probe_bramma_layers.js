#!/usr/bin/env node
/*
 * Diagnostic companion to the parity suite.  It deliberately changes one
 * Bramma input dimension at a time, so a large end-to-end discrepancy is not
 * mislabeled as a single formula issue.
 *
 * It executes the checked-in website kernel and the pure-Swift CLI using the
 * same data and emits a small JSON report.  Nothing in the iOS application
 * imports this file.
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
const SAMPLE_COUNT = 101;
const verify = process.argv.includes('--verify');

function mean(values) {
  return values.reduce((total, value) => total + value, 0) / Math.max(values.length, 1);
}

function standardDeviation(values, average) {
  if (values.length < 2) return 0;
  return Math.sqrt(values.reduce((total, value) => total + (value - average) ** 2, 0)
    / values.length);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function websiteTotal(rows, queueLength) {
  return rows.reduce((total, row) => total + Number(row?.totalDmg || 0), 0) / queueLength;
}

function websiteDirect(rows) {
  return rows.reduce((total, row) => total
    + Number(row?.curr_dmg || 0)
    + Number(row?.xataTotal || 0)
    + Number(row?.dmgOnStatusEff || 0)
    + Number(row?.toxicLash?.direct_hit || 0), 0);
}

function runDamageKit(request) {
  const result = child.spawnSync(
    'swift',
    ['run', '-c', 'debug', 'damagekit-cli', '-', '--data-root', DATA_ROOT, '--compact'],
    {
      cwd: PACKAGE,
      input: JSON.stringify(request),
      encoding: 'utf8',
      maxBuffer: 8 * 1024 * 1024,
    },
  );
  if (result.status !== 0) {
    throw new Error(`DamageKit failed: ${(result.stderr || result.stdout || '').trim()}`);
  }
  return JSON.parse((result.stdout || '').trim());
}

function nativeCustom(siteCustom) {
  const values = {};
  for (const item of siteCustom) {
    // The website custom panel expresses relative crit chance in percentage
    // points, while DamageKit's typed contract is the corresponding ratio.
    values[item.k] = item.k === 'flat_crit_chance' ? item.v / 100 : item.v;
  }
  return values;
}

async function websiteSamples(site, attackName) {
  const totalValues = [];
  const directValues = [];
  let trace = null;
  const strategist = K.W?.WFOpt;
  for (let seed = 1; seed <= SAMPLE_COUNT; seed += 1) {
    if (strategist?.enableStrat) strategist.enableStrat(seed);
    try {
      const response = await K.calc(site);
      const attack = (response.attacks || []).find(candidate => candidate.name === attackName);
      if (!attack) throw new Error(`website attack not found: ${attackName}`);
      const rows = K.W?.arrInfo?.armor?.[attack.name];
      const queueLength = Number(K.W?.queueLength);
      if (!Array.isArray(rows) || !Number.isFinite(queueLength) || queueLength <= 0) {
        throw new Error('website queue unavailable');
      }
      totalValues.push(websiteTotal(rows, queueLength));
      directValues.push(websiteDirect(rows));
      if (!trace) {
        trace = [...new Set(rows.map(row => Number(row?.timeM))
          .filter(Number.isFinite)
          .map(time => Number(time.toFixed(9))))]
          .sort((left, right) => left - right);
      }
    } finally {
      if (strategist?.disableStrat) strategist.disableStrat();
    }
  }
  return {
    totalMean: mean(totalValues),
    totalStandardDeviation: standardDeviation(totalValues, mean(totalValues)),
    directMean: mean(directValues),
    directStandardDeviation: standardDeviation(directValues, mean(directValues)),
    shotTimes: trace,
  };
}

async function main() {
  const suite = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  const base = suite.cases.find(testCase => testCase.id === 'kuva-bramma-radial-lancer-l50');
  if (!base) throw new Error('Kuva Bramma parity fixture is missing');

  const zeroCrit = { k: 'flat_crit_chance', v: -35 };
  const zeroStatus = { k: 'absolute_status_chance', v: -21 };
  const variants = [
    { id: 'bare-no-crit-no-status', mods: {}, custom: [zeroCrit, zeroStatus] },
    { id: 'mods-no-crit-no-status', mods: base.site.mods, custom: [zeroCrit, zeroStatus] },
    { id: 'mods-crit-no-status', mods: base.site.mods, custom: [zeroStatus] },
    { id: 'mods-no-crit-status', mods: base.site.mods, custom: [zeroCrit] },
    { id: 'mods-full', mods: base.site.mods, custom: [] },
  ];

  await K.boot();
  const report = [];
  for (const variant of variants) {
    const site = clone(base.site);
    site.mods = clone(variant.mods);
    site.custom = clone(variant.custom);
    const siteResult = await websiteSamples(site, base.attack);

    const native = clone(base.native);
    native.build.mods = Object.values(variant.mods);
    native.options = {
      ...(native.options || {}),
      customStats: nativeCustom(variant.custom),
    };
    const nativeResult = runDamageKit(native);
    const attack = (nativeResult.attacks || []).find(candidate => candidate.attack === base.attack);
    if (!attack) throw new Error(`DamageKit attack not found: ${base.attack}`);

    report.push({
      id: variant.id,
      website: siteResult,
      damageKit: {
        targetDps: attack.targetDps,
        targetDirectDamage: attack.targetDirectDamage,
        shots: attack.shots,
      },
      ratio: {
        total: attack.targetDps / siteResult.totalMean,
        direct: attack.targetDirectDamage / siteResult.directMean,
      },
      timingDecomposition: {
        websiteShots: siteResult.shotTimes.length,
        damageKitShots: attack.shots,
        ratioFromShotCount: attack.shots / Math.max(siteResult.shotTimes.length, 1),
        totalResidualAfterShotCount: attack.targetDps / siteResult.totalMean
          / (attack.shots / Math.max(siteResult.shotTimes.length, 1)) - 1,
        directResidualAfterShotCount: attack.targetDirectDamage / siteResult.directMean
          / (attack.shots / Math.max(siteResult.shotTimes.length, 1)) - 1,
      },
    });
  }
  if (verify) {
    const bare = report.find(row => row.id === 'bare-no-crit-no-status');
    const full = report.find(row => row.id === 'mods-full');
    if (!bare || !full) throw new Error('required Bramma diagnostic variants are missing');
    for (const row of report) {
      if (row.timingDecomposition.websiteShots !== 13
        || row.timingDecomposition.damageKitShots !== 20) {
        throw new Error(`${row.id}: expected website/native bow shot counts of 13/20`);
      }
    }
    // With crit and status explicitly removed, the resulting ratio must be
    // explained almost entirely by the 20-versus-13 time axis.  For the full
    // build, stochastic projectile rolls and end-window DOT are still present,
    // but any remaining difference must be below the parity tolerance after
    // that documented time-axis defect is factored out.
    if (Math.abs(bare.timingDecomposition.totalResidualAfterShotCount) > 0.002
      || Math.abs(bare.timingDecomposition.directResidualAfterShotCount) > 0.002) {
      throw new Error('Bramma bare isolation has an unexplained residual after shot-count normalization');
    }
    if (Math.abs(full.timingDecomposition.totalResidualAfterShotCount) > 0.05
      || Math.abs(full.timingDecomposition.directResidualAfterShotCount) > 0.05) {
      throw new Error('Bramma full build has a residual beyond the 5% parity tolerance');
    }
  }
  process.stdout.write(JSON.stringify({ samples: SAMPLE_COUNT, verified: verify, variants: report }, null, 2) + '\n');
}

main().catch(error => {
  process.stderr.write((error?.stack || String(error)) + '\n');
  process.exitCode = 1;
});
