#!/usr/bin/env node
/*
 * Exercises the two website custom-stat controls that alter Heat.  The site
 * reports queue rows with a future DOT tail folded into `totalDmg`, so this
 * probe checks the narrow, observable branches directly instead of pretending
 * that its queue-tail display is a native continuous-DPS metric.
 *
 * `heatAdd`: independent Heat direct component, based on raw weapon damage.
 * `heatInherit`: positive value replaces the Heat DOT element-bonus pool only.
 */
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.resolve(__dirname, '..');
const SITE = path.join(ROOT, 'server', 'site');

async function calc(request) {
  await K.calc(request);
  return K.W;
}

function ignisRequest(custom) {
  return {
    weapon: 'Ignis', enemy: 'Charger', level: 1,
    steel: false, eximus: false, party: 1, mods: {},
    opts: { allConds: false, queueLength: 20 },
    // 11% base crit - 11pp and 27% base status + 73pp makes every row
    // deterministic: no crit, exactly one Heat proc.
    custom: [
      { k: 'flat_crit_chance', v: -11 },
      { k: 'absolute_status_chance', v: 73 },
      ...custom,
    ],
  };
}

async function main() {
  const source = fs.readFileSync(path.join(SITE, 'min.js'), 'utf8');
  assert(source.includes('getCustomStat("heatAdd")'),
    'website heatAdd branch changed; review native custom-stat mapping');
  assert(source.includes('"Heat"==a&&0<I?I:getStatValFromModElements(a)'),
    'website heatInherit branch changed; review native custom-stat mapping');

  let w = await calc({
    weapon: 'Sonicor', enemy: 'Charger', level: 1,
    steel: false, eximus: false, party: 1, mods: {},
    opts: { allConds: false, queueLength: 20 },
    custom: [{ k: 'heatAdd', v: 100 }],
  });
  const sonicor = w.currWeapon.attacks.find(attack => attack.name === 'Projectile Impact');
  assert(sonicor, 'Sonicor Projectile Impact is missing');
  assert.strictEqual(sonicor.damage.impact, 150);
  assert.strictEqual(sonicor.damage.heat, 150,
    'heatAdd must append a separate 100%-of-base Heat component');

  w = await calc(ignisRequest([]));
  const baseRows = w.arrInfo?.health?.['Normal Attack'];
  assert(Array.isArray(baseRows) && baseRows.length > 0, 'Ignis baseline queue missing');
  const base = baseRows[0];
  assert.strictEqual(w.currWeapon.attacks[0].crit_chance, 0);
  assert.strictEqual(w.currWeapon.attacks[0].status_chance, 100);
  assert(base.statuses.includes('heat'), 'deterministic Ignis row did not apply Heat');

  w = await calc(ignisRequest([{ k: 'heatInherit', v: 100 }]));
  const inheritedRows = w.arrInfo?.health?.['Normal Attack'];
  assert(Array.isArray(inheritedRows) && inheritedRows.length > 0, 'Ignis inherited queue missing');
  const inherited = inheritedRows[0];
  assert.strictEqual(inherited.curr_dmg, base.curr_dmg,
    'heatInherit must not change the direct hit');
  const baseTail = Number(base.totalDmg) - Number(base.curr_dmg);
  const inheritedTail = Number(inherited.totalDmg) - Number(inherited.curr_dmg);
  assert(baseTail > 0, 'baseline Heat DOT tail is missing');
  assert(Math.abs(inheritedTail / baseTail - 2) <= 1e-12,
    `heatInherit must replace the Heat DOT pool with +100% (got ${inheritedTail / baseTail})`);

  process.stdout.write(JSON.stringify({
    heatAdd: { weapon: 'Sonicor', rawBaseDamage: 150, appendedHeat: sonicor.damage.heat },
    heatInherit: {
      weapon: 'Ignis', directBefore: base.curr_dmg, directAfter: inherited.curr_dmg,
      heatDotTailBefore: baseTail, heatDotTailAfter: inheritedTail,
      heatDotTailRatio: inheritedTail / baseTail,
    },
  }, null, 2) + '\n');
}

main().then(() => process.exit(0)).catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exit(1);
});
