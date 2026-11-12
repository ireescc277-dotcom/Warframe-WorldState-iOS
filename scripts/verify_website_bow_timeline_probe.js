#!/usr/bin/env node
/*
 * Locks a reproducible bow-timeline discrepancy in the checked-in website
 * snapshot.  This script is deliberately independent from DamageKit's output:
 * it executes the website through server/kernel.js, then records its own
 * queued timestamps for an otherwise deterministic Kuva Bramma attack.
 *
 * Community formula source:
 * https://wiki.warframe.com/w/Fire_rate#Fire_Rate_and_Charge_Time
 * For bows: Effective Fire Rate = 1 / (modded charge time + modded reload
 * time).  At charge 0.40 and reload 0.60, each complete arrow cycle is 1.00s.
 *
 * This is evidence about the website timeline only.  It is not used by the
 * iOS app and it does not turn unrelated status/DOT rows into passes.
 */
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.resolve(__dirname, '..');
const SITE = path.join(ROOT, 'server', 'site');

function roundedTimes(rows) {
  return [...new Set(rows
    .map(row => Number(row?.timeM))
    .filter(Number.isFinite)
    .map(time => Number(time.toFixed(9))))]
    .sort((left, right) => left - right);
}

function equalTimes(actual, expected, tolerance = 1e-9) {
  return actual.length === expected.length
    && actual.every((value, index) => Math.abs(value - expected[index]) <= tolerance);
}

async function main() {
  const source = fs.readFileSync(path.join(SITE, 'min.js'), 'utf8');
  // The snapshot computes the bow's 1/(charge + reload) rate, but its generic
  // one-round magazine loop subsequently enters a reload and adds reload time
  // again.  Keep both source landmarks in the probe; any source update must be
  // reviewed instead of inheriting this conclusion silently.
  assert(source.includes('&&O?Ra=1/(qa+wa)'),
    'website bow effective-rate branch changed; review the timeline evidence');
  assert(source.includes('O&&0===ub&&(qb+=qa)'),
    'website first-charge branch changed; review the timeline evidence');
  assert(source.includes('ya=H?qb:qb+1/Ra'),
    'website next-shot branch changed; review the timeline evidence');

  const manifest = JSON.parse(fs.readFileSync(path.join(SITE, 'weapons.json'), 'utf8'));
  const bramma = JSON.parse(fs.readFileSync(
    path.join(SITE, 'weapons', manifest['Kuva Bramma']), 'utf8'));
  const rawAttack = bramma.attacks.find(attack => attack.name === 'Radial Attack');
  assert(rawAttack, 'Kuva Bramma Radial Attack is missing');
  assert.strictEqual(rawAttack.charge_time, 0.4);
  assert.strictEqual(bramma.reloadTime, 0.6);
  assert.strictEqual(bramma.magazineSize, 1);
  assert(bramma.categories.includes('primary-bow'));

  // `flat_crit_chance` and `absolute_status_chance` are the website's actual
  // absolute controls.  They remove random crit/status behavior, so the trace
  // isolates timing rather than relying on a lucky stochastic seed.
  await K.calc({
    weapon: 'Kuva Bramma', enemy: 'Lancer', level: 50,
    steel: false, eximus: false, party: 1, mods: {},
    opts: { allConds: false, queueLength: 20 },
    custom: [
      { k: 'flat_crit_chance', v: -35 },
      { k: 'absolute_status_chance', v: -21 },
    ],
  });

  const attack = K.W.currWeapon.attacks.find(row => row.name === 'Radial Attack');
  assert(attack, 'website did not load Kuva Bramma Radial Attack');
  assert.strictEqual(attack.crit_chance, 0);
  assert.strictEqual(attack.status_chance, 0);

  const rows = K.W.arrInfo?.armor?.['Radial Attack'];
  assert(Array.isArray(rows), 'website armor queue for Kuva Bramma is missing');
  const siteTimes = roundedTimes(rows);
  const expectedSiteTimes = [0.4, 2, 3.6, 5.2, 6.8, 8.4, 10, 11.6, 13.2,
    14.8, 16.4, 18, 19.6];
  assert(equalTimes(siteTimes, expectedSiteTimes),
    `unexpected website timeline: ${JSON.stringify(siteTimes)}`);

  const communityTimes = Array.from({ length: 20 }, (_, index) => Number((0.4 + index).toFixed(9)));
  assert.strictEqual(communityTimes.length, 20);
  assert.strictEqual(communityTimes[0], 0.4);
  assert.strictEqual(communityTimes[1], 1.4);
  assert.strictEqual(communityTimes[19], 19.4);
  assert(!equalTimes(siteTimes, communityTimes),
    'website timeline unexpectedly matches the documented bow formula; review fixture evidence');

  const siteIntervals = siteTimes.slice(1).map((time, index) => time - siteTimes[index]);
  assert(siteIntervals.every(interval => Math.abs(interval - 1.6) <= 1e-9),
    `website interval is not charge + two reloads: ${JSON.stringify(siteIntervals)}`);

  process.stdout.write(JSON.stringify({
    weapon: bramma.name,
    attack: rawAttack.name,
    raw: { chargeTime: rawAttack.charge_time, reloadTime: bramma.reloadTime, magazine: bramma.magazineSize },
    communityCycleSeconds: 1,
    communityShotsIn20Seconds: communityTimes.length,
    communityShotTimes: communityTimes,
    websiteCycleAfterFirstSeconds: 1.6,
    websiteShotsIn20Seconds: siteTimes.length,
    websiteShotTimes: siteTimes,
  }, null, 2) + '\n');
}

main().then(() => process.exit(0)).catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exit(1);
});
