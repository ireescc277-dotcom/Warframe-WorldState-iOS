#!/usr/bin/env node
/*
 * Tests the Nourish parity fixture against an in-memory website variant that
 * changes only one ordering rule: a status created by a simultaneous hit is
 * visible from the next distinct shot time, not to the hit (or multishot
 * projectiles) that created it.  This lets us distinguish an ordering branch
 * from a generic "Nourish is different" claim.
 */
'use strict';

const child = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const KERNEL_PATH = path.join(ROOT, 'server', 'kernel.js');
const MIN_PATH = path.join(ROOT, 'server', 'site', 'min.js');
const PACKAGE = path.join(ROOT, 'Packages', 'DamageKit');
const DATA_ROOT = path.join(ROOT, 'web', 'app', 'site');
const CASE_FILE = path.join(PACKAGE, 'Parity', 'website-cases.json');
const CASE_ID = 'lex-prime-nourish-lancer-l50';
const SAMPLE_COUNT = 61;
const verify = process.argv.includes('--verify');

// `timelineStatus` currently applies a proc at index n itself.  Its callers
// calculate the direct damage of index n after reading the resulting status
// table, so the proc augments the very hit that created it.  The replacement
// keeps the full status duration and all proc behavior, but begins at the
// next *distinct* timestamp.  That matters for simultaneous multishot rows:
// they must not apply a Viral multiplier to each other either.
const SHIPPED_STATUS_START = 'D[n]+=1;--D[r]}}for(const l in t)';
const POST_HIT_STATUS_START = 'let J=n+1;for(;J<d&&a[J].time===u;J++);D[J]+=1;--D[r]}}for(const l in t)';
const EPSILON = 1e-9;

function assert(condition, message) {
  if (!condition) throw new Error(message);
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

function activeStacks(row, status) {
  const key = Object.keys(row?.statusOnEnemy || {})
    .find(candidate => candidate.toLowerCase() === status);
  const value = key ? row.statusOnEnemy[key] : null;
  const stacks = Number(value?.ticks ?? value?.stacks ?? value);
  return Number.isFinite(stacks) ? stacks : 0;
}

function statusTrace(rows, status = 'viral') {
  const appliedStatuses = row => (Array.isArray(row?.statuses) ? row.statuses : [])
    .map(value => String(value).toLowerCase());
  const rowIndex = rows.findIndex(row => appliedStatuses(row).includes(status));
  assert(rowIndex >= 0, `website never applied ${status}`);
  const row = rows[rowIndex];
  const preceding = rows.slice(0, rowIndex).reverse().find(candidate =>
    candidate?.crit === row?.crit
      && activeStacks(candidate, status) === 0
      && !appliedStatuses(candidate).includes(status));
  assert(preceding, `no comparable pre-${status} hit`);
  return {
    rowIndex,
    time: Number(row.timeM),
    direct: Number(row.curr_dmg),
    activeStacks: activeStacks(row, status),
    precedingTime: Number(preceding.timeM),
    precedingDirect: Number(preceding.curr_dmg),
    precedingActiveStacks: activeStacks(preceding, status),
    damageRatio: Number(row.curr_dmg) / Number(preceding.curr_dmg),
  };
}

function loadKernel(postHitStatus) {
  const shippedSource = fs.readFileSync(MIN_PATH, 'utf8');
  assert(shippedSource.includes(SHIPPED_STATUS_START),
    'website status timeline branch changed; review the counterfactual');
  const source = postHitStatus
    ? shippedSource.replace(SHIPPED_STATUS_START, POST_HIT_STATUS_START)
    : shippedSource;
  if (postHitStatus) {
    assert(source !== shippedSource, 'unable to replace website status timeline branch');
    assert(!source.includes(SHIPPED_STATUS_START), 'website status timeline replacement was incomplete');
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

function fixture() {
  const suite = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  const testCase = suite.cases.find(entry => entry.id === CASE_ID);
  assert(testCase, `missing parity fixture ${CASE_ID}`);
  return testCase;
}

async function websiteSample(kernel, testCase, seed, wantTrace) {
  const strategist = kernel.W?.WFOpt;
  assert(strategist?.enableStrat && strategist?.disableStrat,
    'website deterministic strategy is unavailable');
  strategist.enableStrat(seed);
  try {
    const response = await kernel.calc(testCase.site);
    assert(!response.lostMods?.length, `${CASE_ID}: website rejected a Mod`);
    const attack = (response.attacks || []).find(row => row.name === testCase.attack);
    assert(attack, `${CASE_ID}: website attack missing`);
    const rows = kernel.W?.arrInfo?.armor?.[attack.name];
    assert(Array.isArray(rows), `${CASE_ID}: website armor queue missing`);
    return {
      direct: queueDirect(rows),
      totalDps: queueTotalDps(rows, Number(kernel.W.queueLength)),
      trace: wantTrace ? statusTrace(rows) : null,
    };
  } finally {
    strategist.disableStrat();
  }
}

async function websiteMetrics(kernel, testCase) {
  const values = [];
  let trace = null;
  for (let seed = 1; seed <= SAMPLE_COUNT; seed += 1) {
    const row = await websiteSample(kernel, testCase, seed, seed === 1);
    values.push(row);
    if (row.trace) trace = row.trace;
  }
  return {
    direct: mean(values.map(row => row.direct)),
    totalDps: mean(values.map(row => row.totalDps)),
    seedOneViralTrace: trace,
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
    throw new Error(`DamageKit failed: ${(result.stderr || result.stdout || '').trim()}`);
  }
  const output = JSON.parse((result.stdout || '').trim());
  const attack = (output.attacks || []).find(row => row.attack === testCase.attack);
  assert(attack, 'DamageKit attack missing');
  return { direct: Number(attack.targetDirectDamage), totalDps: Number(attack.targetDps) };
}

async function main() {
  const testCase = fixture();
  const shipped = loadKernel(false);
  const postHit = loadKernel(true);
  await Promise.all([shipped.boot(), postHit.boot()]);
  const [shippedMetrics, postHitMetrics] = await Promise.all([
    websiteMetrics(shipped, testCase),
    websiteMetrics(postHit, testCase),
  ]);
  const native = nativeMetrics(testCase);
  const output = {
    samples: SAMPLE_COUNT,
    verified: verify,
    native,
    shipped: {
      ...shippedMetrics,
      directRelativeDifference: relativeDifference(native.direct, shippedMetrics.direct),
      totalRelativeDifference: relativeDifference(native.totalDps, shippedMetrics.totalDps),
    },
    websitePostHitStatusCounterfactual: {
      ...postHitMetrics,
      directRelativeDifference: relativeDifference(native.direct, postHitMetrics.direct),
      totalRelativeDifference: relativeDifference(native.totalDps, postHitMetrics.totalDps),
    },
  };

  if (verify) {
    assert(output.shipped.directRelativeDifference > 0.05,
      'shipped website direct output unexpectedly within 5%');
    assert(output.websitePostHitStatusCounterfactual.directRelativeDifference <= 0.05,
      'post-hit Viral counterfactual direct output remains outside 5%');
    assert(output.websitePostHitStatusCounterfactual.totalRelativeDifference <= 0.05,
      'post-hit Viral counterfactual total output remains outside 5%');
    const trace = output.shipped.seedOneViralTrace;
    assert(trace.activeStacks === 1 && trace.precedingActiveStacks === 0
      && Math.abs(trace.damageRatio - 2) <= EPSILON,
    'shipped website no longer grants the applying Viral row its own multiplier');
    const correctedTrace = output.websitePostHitStatusCounterfactual.seedOneViralTrace;
    assert(correctedTrace.activeStacks === 0 && correctedTrace.precedingActiveStacks === 0
      && Math.abs(correctedTrace.damageRatio - 1) <= EPSILON,
    'post-hit counterfactual still grants the applying Viral row its own multiplier');
  }

  process.stdout.write(JSON.stringify(output, null, 2) + '\n');
}

main().catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
