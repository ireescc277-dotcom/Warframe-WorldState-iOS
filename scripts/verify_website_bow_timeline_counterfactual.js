#!/usr/bin/env node
/*
 * Runs the two normal bow parity fixtures through the checked-in website
 * source twice.  The second run changes only the queue scheduler's bow
 * branch in memory: charged bows use their already-calculated
 * charge-plus-reload cadence and do not add a second generic magazine reload.
 *
 * No website file is written, and neither branch is used by the iOS app.  The
 * counterfactual isolates whether the large normal-build discrepancy really
 * comes from the website's bow timeline instead of being inferred from a
 * separate no-crit test case.
 */
'use strict';

const child = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const KERNEL_PATH = path.join(ROOT, 'server', 'kernel.js');
const MIN_PATH = path.join(ROOT, 'server', 'site', 'min.js');
const PACKAGE = path.join(ROOT, 'Packages', 'DamageKit');
const DATA_ROOT = path.join(ROOT, 'server', 'site');
const CASE_FILE = path.join(PACKAGE, 'Parity', 'website-cases.json');
const CASE_IDS = [
  'paris-prime-charged-shot-lancer-l50',
  'kuva-bramma-radial-lancer-l50',
];
const SAMPLE_COUNT = 61;
const verify = process.argv.includes('--verify');
const EPSILON = 1e-9;

// In createDmgQueue's inner scheduler the shipped branch first calculates
// Ra=1/(charge+reload), then later performs the ordinary one-round-magazine
// reload.  The replacement preserves all damage, proc, and RNG code.  It
// only gives charged bows an explicit shot count and suppresses that second
// generic reload.
const SHIPPED_BOW_BRANCH = 'let Ua;Ua=Ia&&0===wa?Infinity:Math.max(1,Math.floor(ja/na));if(H&&Infinity!==ja){';
const CORRECTED_BOW_BRANCH = 'let Ua;Ua=Ia&&0===wa?Infinity:Math.max(1,Math.floor(ja/na));if((currWeapon.categories.includes("primary-bow")||"Balefire Charger (Hildryn)"===currWeapon.name)&&O){if(K<qa)return{shotTimes:[],shotInfos:[],reloadInfos:[],totalReloads:0,totalShots:0};Ca=Math.floor((K-qa)*Ra)+1;Ia=!0}else if(H&&Infinity!==ja){';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function closeTo(actual, expected, label) {
  assert(Math.abs(actual - expected) <= EPSILON * Math.max(1, Math.abs(expected)),
    `${label}: expected ${expected}, got ${actual}`);
}

function mean(values) {
  return values.reduce((sum, value) => sum + value, 0) / Math.max(values.length, 1);
}

function relativeDifference(left, right) {
  return Math.abs(left - right) / Math.max(Math.abs(right), 1e-9);
}

function queueDirect(rows) {
  return rows.reduce((sum, row) => sum
    + Number(row?.curr_dmg || 0)
    + Number(row?.xataTotal || 0)
    + Number(row?.dmgOnStatusEff || 0)
    + Number(row?.toxicLash?.direct_hit || 0), 0);
}

function queueTotalDps(rows, queueLength) {
  return rows.reduce((sum, row) => sum + Number(row?.totalDmg || 0), 0) / queueLength;
}

function uniqueTimes(rows) {
  return [...new Set(rows.map(row => Number(row?.timeM))
    .filter(Number.isFinite)
    .map(time => Number(time.toFixed(9))))]
    .sort((left, right) => left - right);
}

function expectedTimes(charge, reload, window, includeExtraReload) {
  const cycle = charge + reload * (includeExtraReload ? 2 : 1);
  const result = [];
  for (let time = charge; time < window - EPSILON; time += cycle) {
    result.push(Number(time.toFixed(9)));
  }
  return result;
}

function sameTimes(actual, expected) {
  return actual.length === expected.length
    && actual.every((time, index) => Math.abs(time - expected[index]) <= EPSILON);
}

function loadKernel(correctBowTimeline) {
  const shippedSource = fs.readFileSync(MIN_PATH, 'utf8');
  assert(shippedSource.includes(SHIPPED_BOW_BRANCH),
    'website bow scheduler branch changed; review the counterfactual');
  const source = correctBowTimeline
    ? shippedSource.replace(SHIPPED_BOW_BRANCH, CORRECTED_BOW_BRANCH)
    : shippedSource;
  if (correctBowTimeline) {
    assert(source !== shippedSource, 'unable to replace website bow scheduler branch');
    assert(!source.includes(SHIPPED_BOW_BRANCH), 'website bow scheduler replacement was incomplete');
  }

  const originalReadFileSync = fs.readFileSync;
  fs.readFileSync = function interceptedRead(file, ...args) {
    if (typeof file === 'string' && path.resolve(file) === MIN_PATH) return source;
    return originalReadFileSync.call(fs, file, ...args);
  };

  const cacheKey = require.resolve(KERNEL_PATH);
  delete require.cache[cacheKey];
  try {
    return require(KERNEL_PATH);
  } finally {
    fs.readFileSync = originalReadFileSync;
  }
}

async function websiteSample(kernel, testCase, seed) {
  const strategist = kernel.W?.WFOpt;
  assert(strategist?.enableStrat && strategist?.disableStrat,
    'website deterministic strategy is unavailable');
  strategist.enableStrat(seed);
  try {
    const response = await kernel.calc(testCase.site);
    assert(!response.lostMods?.length, `${testCase.id}: website rejected a Mod`);
    const attack = (response.attacks || []).find(row => row.name === testCase.attack);
    assert(attack, `${testCase.id}: website attack missing`);
    const rows = kernel.W?.arrInfo?.armor?.[attack.name];
    assert(Array.isArray(rows), `${testCase.id}: website armor queue missing`);
    const weaponAttack = (kernel.W?.currWeapon?.attacks || [])
      .find(row => row.name === testCase.attack);
    assert(weaponAttack, `${testCase.id}: active website attack missing`);
    return {
      direct: queueDirect(rows),
      totalDps: queueTotalDps(rows, Number(kernel.W.queueLength)),
      times: uniqueTimes(rows),
      charge: Number(weaponAttack.charge_time),
      reload: Number(kernel.W.currWeapon.reloadTime),
      magazine: Number(kernel.W.currWeapon.magazineSize),
      projectileRows: rows.length,
    };
  } finally {
    strategist.disableStrat();
  }
}

async function websiteMetrics(kernel, testCase) {
  const samples = [];
  for (let seed = 1; seed <= SAMPLE_COUNT; seed += 1) {
    samples.push(await websiteSample(kernel, testCase, seed));
  }
  const representative = samples[0];
  return {
    direct: mean(samples.map(row => row.direct)),
    totalDps: mean(samples.map(row => row.totalDps)),
    timeline: {
      charge: representative.charge,
      reload: representative.reload,
      magazine: representative.magazine,
      projectileRowsAtSeed1: representative.projectileRows,
      times: representative.times,
    },
  };
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
  const attack = (output.attacks || []).find(row => row.attack === testCase.attack);
  assert(attack, `${testCase.id}: DamageKit attack missing`);
  return {
    direct: Number(attack.targetDirectDamage),
    totalDps: Number(attack.targetDps),
    shots: Number(attack.shots),
  };
}

function fixture(suite, id) {
  const testCase = suite.cases.find(entry => entry.id === id);
  assert(testCase, `missing parity fixture ${id}`);
  return testCase;
}

async function main() {
  const suite = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  const shipped = loadKernel(false);
  const corrected = loadKernel(true);
  await Promise.all([shipped.boot(), corrected.boot()]);

  const results = [];
  for (const id of CASE_IDS) {
    const testCase = fixture(suite, id);
    const [site, counterfactual] = await Promise.all([
      websiteMetrics(shipped, testCase),
      websiteMetrics(corrected, testCase),
    ]);
    const native = nativeMetrics(testCase);
    const window = Number(testCase.site?.opts?.queueLength);
    const expectedShipped = expectedTimes(site.timeline.charge, site.timeline.reload, window, true);
    const expectedCounterfactual = expectedTimes(
      counterfactual.timeline.charge, counterfactual.timeline.reload, window, false,
    );
    assert(site.timeline.magazine === 1, `${id}: expected one-arrow magazine`);
    assert(counterfactual.timeline.magazine === 1, `${id}: counterfactual magazine changed`);
    assert(sameTimes(site.timeline.times, expectedShipped),
      `${id}: shipped website timeline no longer matches charge plus two reloads`);
    assert(sameTimes(counterfactual.timeline.times, expectedCounterfactual),
      `${id}: corrected website timeline does not match charge plus reload`);
    assert(native.shots === expectedCounterfactual.length,
      `${id}: DamageKit shot count differs from documented bow cadence`);

    results.push({
      id,
      window,
      native,
      shipped: {
        ...site,
        directRelativeDifference: relativeDifference(native.direct, site.direct),
        totalRelativeDifference: relativeDifference(native.totalDps, site.totalDps),
      },
      correctedWebsiteTimelineOnly: {
        ...counterfactual,
        directRelativeDifference: relativeDifference(native.direct, counterfactual.direct),
        totalRelativeDifference: relativeDifference(native.totalDps, counterfactual.totalDps),
      },
    });
  }

  if (verify) {
    for (const result of results) {
      assert(result.shipped.directRelativeDifference > 0.05,
        `${result.id}: shipped direct output unexpectedly within 5%`);
      assert(result.correctedWebsiteTimelineOnly.directRelativeDifference <= 0.05,
        `${result.id}: bow-timeline-only counterfactual direct output remains outside 5%`);
      assert(result.correctedWebsiteTimelineOnly.totalRelativeDifference <= 0.05,
        `${result.id}: bow-timeline-only counterfactual total output remains outside 5%`);
    }
  }

  process.stdout.write(JSON.stringify({
    samples: SAMPLE_COUNT,
    verified: verify,
    results,
  }, null, 2) + '\n');
}

main().catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
