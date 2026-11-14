#!/usr/bin/env node
/*
 * Proves one narrow website presentation defect: its queued `totalDmg` folds a
 * complete Heat status duration into a row even when that duration lies beyond
 * the selected simulation window. This is an executable observation of the
 * checked-in website snapshot, not code used by the app.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function own(row, key) {
  return Object.prototype.hasOwnProperty.call(row, key) ? row[key] : undefined;
}

async function main() {
  await K.boot();
  const source = fs.readFileSync(path.join(__dirname, '..', 'server', 'site', 'min.js'), 'utf8');
  // These landmarks keep the observation tied to the snapshot whose behavior
  // is exercised below: a status amount is multiplied by its full duration,
  // then folded into the queued total for the hit row.
  assert(source.includes('getStatusDamageValue='), 'website status-value helper missing');
  assert(source.includes('curr_duration'), 'website status duration branch missing');
  assert(source.includes('totalDmg=jd'), 'website queued total assignment missing');

  const strategist = K.W?.WFOpt;
  if (strategist?.enableStrat) strategist.enableStrat(1);
  try {
    const response = await K.calc({
      weapon: 'Ignis Wraith',
      enemy: 'Charger',
      level: 1,
      steel: false,
      eximus: false,
      party: 1,
      mods: {},
      // 17 - 100 clamps crit to zero. Ignis Wraith has 29% base status;
      // adding 71 percentage points forces exactly one Heat status per hit.
      custom: [
        { k: 'flat_crit_chance', v: -100 },
        { k: 'absolute_status_chance', v: 71 },
      ],
      opts: { allConds: false, queueLength: 1 },
    });
    const attack = (response.attacks || []).find(item => item.name === 'Normal Attack');
    assert(attack, 'Ignis Wraith Normal Attack missing');
    const rows = K.W?.arrInfo?.health?.[attack.name];
    assert(Array.isArray(rows), 'website health queue missing');
    assert(rows.length === 8, `expected 8 one-second beam hits, got ${rows.length}`);

    const trace = rows.map(row => ({
      time: Number(own(row, 'timeM')),
      direct: Number(own(row, 'curr_dmg')),
      total: Number(own(row, 'totalDmg')),
      statuses: Array.isArray(own(row, 'statuses')) ? own(row, 'statuses') : [],
    }));
    const direct = trace.reduce((total, row) => total + row.direct, 0);
    const queuedTotal = trace.reduce((total, row) => total + row.total, 0);
    assert(trace.every(row => row.time >= 0 && row.time < 1), 'a queued hit escaped the 1s window');
    assert(trace.every(row => row.direct === 52.5), 'unexpected direct damage in Heat isolation');
    assert(trace.every(row => row.total === 210), 'website did not fold full Heat duration into every row');
    assert(trace.every(row => row.statuses.length === 1 && row.statuses[0] === 'heat'),
      'expected exactly one Heat status per hit');
    assert(direct === 420, `expected direct total 420, got ${direct}`);
    assert(queuedTotal === 1680, `expected queue total 1680, got ${queuedTotal}`);
    assert(queuedTotal - direct === 1260, 'unexpected Heat tail contribution');

    process.stdout.write(JSON.stringify({
      weapon: 'Ignis Wraith',
      window: 1,
      hitTimes: trace.map(row => row.time),
      direct,
      websiteQueuedTotal: queuedTotal,
      postWindowHeatTailIncludedByWebsite: queuedTotal - direct,
    }, null, 2) + '\n');
  } finally {
    if (strategist?.disableStrat) strategist.disableStrat();
  }
}

main().catch(error => {
  process.stderr.write((error?.stack || String(error)) + '\n');
  process.exitCode = 1;
});
