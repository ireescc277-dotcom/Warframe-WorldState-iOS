#!/usr/bin/env node
/*
 * Reproduces the remaining Laetum B queue-total divergence in the checked-in
 * warframe-damage snapshot.  The direct-hit total already matches; this probe
 * looks only at the website's Gas presentation branch and proves that it
 * credits a full Gas pulse to every projectile row, including rows less than
 * one second apart.
 *
 * This is diagnostic evidence, not production calculator code.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.resolve(__dirname, '..');
const CASE_FILE = path.join(ROOT, 'Packages', 'DamageKit', 'Parity', 'website-cases.json');
const WEBSITE_SOURCE = path.join(ROOT, 'server', 'site', 'min.js');
const CASE_ID = 'laetum-config-b-eximus-sp999-site-all-conditions';
const EPSILON = 1e-7;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function closeTo(actual, expected, label) {
  assert(Math.abs(actual - expected) <= EPSILON * Math.max(1, Math.abs(expected)),
    `${label}: expected ${expected}, got ${actual}`);
}

function fixture() {
  const suite = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  const testCase = suite.cases.find(entry => entry.id === CASE_ID);
  assert(testCase, `missing parity fixture ${CASE_ID}`);
  return testCase;
}

function gasWitness(row, index) {
  const gas = row?.status?.gas;
  const stacks = Number(row?.statusOnEnemy?.gas?.ticks);
  const direct = Number(row?.curr_dmg);
  const total = Number(row?.totalDmg);
  const tick = Number(row?.isNC ? gas?.nc : gas?.d);
  const time = Number(row?.timeM);
  if (![stacks, direct, total, tick, time].every(Number.isFinite) || stacks <= 0 || tick <= 0) {
    return null;
  }
  const credited = total - direct;
  if (Math.abs(credited - stacks * tick) > EPSILON * Math.max(1, Math.abs(credited))) {
    return null;
  }
  return { index, time, direct, total, activeGasStacks: stacks, gasPulse: tick, credited };
}

async function main() {
  const source = fs.readFileSync(WEBSITE_SOURCE, 'utf8');
  // This exact branch derives Ga from the active Gas-stack count, then folds
  // Ga full pulses into every queued projectile row (`kb`/`Tb`), rather than
  // scheduling a pulse by time.
  assert(source.includes('const Ga=d[A].hasOwnProperty("gas")?d[A].gas.ticks:statusDuration[va].curr_duration'),
    'website Gas stack branch missing');
  assert(source.includes('N||(kb+=Ga*arrInfo[h][z][A].status[X[V]].d,Tb+=Ga*arrInfo[h][z][A].status[X[V]].nc,N=!0)'),
    'website Gas queued-total branch missing');

  const testCase = fixture();
  await K.boot();
  const strategist = K.W?.WFOpt;
  assert(strategist?.enableStrat && strategist?.disableStrat,
    'website deterministic strategy is unavailable');
  strategist.enableStrat(1);
  try {
    const response = await K.calc(testCase.site);
    assert(!response.lostMods?.length, 'website rejected a Laetum Mod');
    const rows = K.W?.arrInfo?.armor?.[testCase.attack];
    assert(Array.isArray(rows) && rows.length > 0, 'Laetum armor queue missing');
    const window = Number(K.W.queueLength);
    const candidates = rows.map(gasWitness).filter(Boolean)
      .filter(row => row.time >= window - 1 && row.time < window);
    assert(candidates.length >= 2, 'missing final-second Gas witnesses');

    let pair = null;
    for (let index = 1; index < candidates.length; index += 1) {
      const previous = candidates[index - 1];
      const current = candidates[index];
      const interval = current.time - previous.time;
      if (interval > 1e-9 && interval < 1 - EPSILON
        && previous.activeGasStacks === current.activeGasStacks
        && Math.abs(previous.gasPulse - current.gasPulse) <= EPSILON) {
        pair = { previous, current, interval };
        break;
      }
    }
    assert(pair, 'no sub-second pair of equivalent Gas rows found');

    // A six-second Gas duration does not permit two whole one-second Gas
    // pulses at two different times under one second apart.  The rows are
    // deliberately selected from the last queue second so no later window
    // accounting can explain their being credited now.
    closeTo(pair.previous.credited,
      pair.previous.activeGasStacks * pair.previous.gasPulse,
      'first website Gas row');
    closeTo(pair.current.credited,
      pair.current.activeGasStacks * pair.current.gasPulse,
      'second website Gas row');

    const direct = rows.reduce((sum, row) => sum
      + Number(row?.curr_dmg || 0)
      + Number(row?.xataTotal || 0)
      + Number(row?.dmgOnStatusEff || 0)
      + Number(row?.toxicLash?.direct_hit || 0), 0);
    const queuedTotal = rows.reduce((sum, row) => sum + Number(row?.totalDmg || 0), 0);

    process.stdout.write(JSON.stringify({
      id: CASE_ID,
      seed: 1,
      window,
      projectileRows: rows.length,
      direct,
      websiteQueuedTotal: queuedTotal,
      websiteStatusTotal: queuedTotal - direct,
      pair,
    }, null, 2) + '\n');
  } finally {
    strategist.disableStrat();
  }
}

main().catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
