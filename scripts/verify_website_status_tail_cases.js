#!/usr/bin/env node
/*
 * Reproduces the two normal-build cases where warframe-damage's displayed
 * queue total credits a complete damaging-status duration to a hit after the
 * selected 20-second window has ended.  This is a diagnostic for the parity
 * fixtures only; the iOS application never executes this file or website JS.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.join(__dirname, '..');
const CASE_FILE = path.join(ROOT, 'Packages', 'DamageKit', 'Parity', 'website-cases.json');
const WEBSITE_SOURCE = path.join(ROOT, 'server', 'site', 'min.js');
const EPSILON = 1e-7;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function closeTo(actual, expected, label) {
  assert(Math.abs(actual - expected) <= EPSILON * Math.max(1, Math.abs(expected)),
    `${label}: expected ${expected}, got ${actual}`);
}

function fixture(suite, id) {
  const result = suite.cases.find(entry => entry.id === id);
  assert(result, `missing parity fixture ${id}`);
  return result;
}

function damagingStatus(row, wantedStatus) {
  const found = Object.entries(row?.status || {})
    .find(([name, value]) => name.toLowerCase() === wantedStatus
      && Number.isFinite(Number(value?.d)) && Number(value.d) > 0);
  assert(found, `no damaging ${wantedStatus} status on selected website row`);
  return Number(found[1].d);
}

async function observeCase(testCase, witness) {
  const strategist = K.W?.WFOpt;
  assert(strategist?.enableStrat && strategist?.disableStrat,
    'website deterministic strategy is unavailable');

  strategist.enableStrat(witness.seed);
  try {
    await K.calc(testCase.site);
    const rows = K.W?.arrInfo?.armor?.[testCase.attack];
    assert(Array.isArray(rows), `${testCase.id}: website armor queue missing`);
    const row = rows[witness.rowIndex];
    assert(row, `${testCase.id}: missing witness row ${witness.rowIndex}`);

    const time = Number(row.timeM);
    const direct = Number(row.curr_dmg);
    const total = Number(row.totalDmg);
    const perTick = damagingStatus(row, witness.status);
    assert(Number.isFinite(time) && Number.isFinite(direct) && Number.isFinite(total),
      `${testCase.id}: invalid witness values`);
    assert(time >= witness.minimumTime,
      `${testCase.id}: witness should occur in the final second, got t=${time}`);
    // Slash and Heat first tick one second after the proc.  These two witness
    // rows are deliberately late enough that zero status ticks are inside
    // the half-open [0, queueLength) simulation interval.
    const window = Number(testCase.site?.opts?.queueLength);
    assert(time + 1 > window,
      `${testCase.id}: expected the first ${witness.status} tick after the queue window`);

    const foldedStatusTotal = total - direct;
    closeTo(foldedStatusTotal, perTick * 6,
      `${testCase.id}: website should fold six complete ${witness.status} ticks into totalDmg`);

    return {
      id: testCase.id,
      seed: witness.seed,
      rowIndex: witness.rowIndex,
      time,
      queueWindow: window,
      status: witness.status,
      direct,
      websiteQueuedTotalForRow: total,
      damagingStatusPerTick: perTick,
      websitePostWindowTailIncluded: foldedStatusTotal,
      firstTickAt: time + 1,
      expectedTicksInsideWindow: 0,
    };
  } finally {
    strategist.disableStrat();
  }
}

async function main() {
  const source = fs.readFileSync(WEBSITE_SOURCE, 'utf8');
  // Tie the observed behavior to the snapshot under test: this helper
  // multiplies a status row by curr_duration before the resulting `jd` is
  // assigned to totalDmg.  The explicit six-second definitions protect the
  // witness calculation below from silently tracking a different branch.
  assert(source.includes('getStatusDamageValue='), 'website status helper missing');
  assert(source.includes('Slash:{duration:6,curr_duration:6'), 'website Slash duration missing');
  assert(source.includes('Heat:{duration:6,curr_duration:6'), 'website Heat duration missing');
  assert(source.includes('totalDmg=jd'), 'website queued total assignment missing');

  const suite = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  await K.boot();

  const observations = [];
  observations.push(await observeCase(
    fixture(suite, 'hek-galvanized-savvy-manual-status-lancer-l50'),
    { seed: 2, rowIndex: 151, status: 'slash', minimumTime: 19 },
  ));
  observations.push(await observeCase(
    fixture(suite, 'ignis-wraith-beam-status-lancer-l50'),
    { seed: 1, rowIndex: 153, status: 'heat', minimumTime: 19 },
  ));

  process.stdout.write(JSON.stringify({ observations }, null, 2) + '\n');
}

main().catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
