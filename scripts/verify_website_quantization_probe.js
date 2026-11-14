#!/usr/bin/env node
/*
 * Locks a concrete, inspectable difference between the checked-in
 * warframe-damage implementation and the current community mission formula.
 *
 * This is not a claim that every website result is wrong.  It proves only the
 * direct-damage quantization branch used by the site snapshot, so fixtures can
 * scope any source-backed divergence to immediate-hit values rather than
 * masking DOT or timeline failures.
 *
 * Community formula source:
 * https://wiki.warframe.com/w/Damage_Quantization
 * The page specifies a Modded Base Damage / 32 grid.  The source snapshot's
 * `setQuantize` instead divides by 16.
 */
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.resolve(__dirname, '..');
const SITE = path.join(ROOT, 'server', 'site');

function nearestGrid(total, denominator, value) {
  const scale = total / denominator;
  return Math.round(value / scale) * scale;
}

async function main() {
  const source = fs.readFileSync(path.join(SITE, 'min.js'), 'utf8');
  const definition = /function setQuantize\(a,d\)\{if\(0===d\)return 0;a\/=(\d+);return Math\.round\(d\/a\)\*a\}/.exec(source);
  assert(definition, 'website setQuantize implementation was not found');
  const denominator = Number(definition[1]);
  assert.strictEqual(denominator, 16, 'site quantization denominator changed; review parity evidence');

  const manifest = JSON.parse(fs.readFileSync(path.join(SITE, 'weapons.json'), 'utf8'));
  // These cover an automatic rifle, secondary, shotgun, and melee weapon.
  // Each source vector is exact site data, so this does not manufacture a
  // generic rounding counterexample detached from a real playable attack.
  const fixtures = [
    {
      weapon: 'Braton',
      attack: 'Normal Attack',
      raw: { impact: 7.92, slash: 8.16, puncture: 7.92 },
      website: { impact: 7.5, slash: 7.5, puncture: 7.5 },
      mission: { impact: 8.25, slash: 8.25, puncture: 8.25 },
    },
    {
      weapon: 'Lex Prime',
      attack: 'Normal Attack',
      raw: { impact: 15, slash: 15, puncture: 120 },
      website: { impact: 18.75, slash: 18.75, puncture: 121.875 },
      mission: { impact: 14.0625, slash: 14.0625, puncture: 121.875 },
    },
    {
      weapon: 'Hek',
      attack: 'Normal Attack',
      raw: { impact: 11.25, slash: 15, puncture: 48.75 },
      website: { impact: 9.375, slash: 14.0625, puncture: 46.875 },
      mission: { impact: 11.71875, slash: 14.0625, puncture: 49.21875 },
    },
    {
      weapon: 'Skana',
      attack: 'Normal Attack',
      raw: { impact: 18, slash: 84, puncture: 18 },
      website: { impact: 15, slash: 82.5, puncture: 15 },
      mission: { impact: 18.75, slash: 82.5, puncture: 18.75 },
    },
  ];

  await K.boot();
  assert.strictEqual(typeof K.W.setQuantize, 'function');
  const probes = fixtures.map(fixture => {
    const weapon = JSON.parse(fs.readFileSync(path.join(SITE, 'weapons', manifest[fixture.weapon]), 'utf8'));
    const attack = weapon.attacks.find(row => row.name === fixture.attack);
    assert(attack, `${fixture.weapon} ${fixture.attack} missing`);
    const rawVector = Object.fromEntries(Object.entries(attack.damage).map(([type, value]) => [type, Number(value)]));
    assert.deepStrictEqual(rawVector, fixture.raw, `${fixture.weapon} source vector changed`);
    const total = Object.values(rawVector).reduce((sum, value) => sum + value, 0);
    const actualSiteVector = Object.fromEntries(Object.entries(rawVector)
      .map(([type, value]) => [type, K.W.setQuantize(total, value)]));
    const reconstructedSiteVector = Object.fromEntries(Object.entries(rawVector)
      .map(([type, value]) => [type, nearestGrid(total, denominator, value)]));
    const missionVector = Object.fromEntries(Object.entries(rawVector)
      .map(([type, value]) => [type, nearestGrid(total, 32, value)]));
    assert.deepStrictEqual(actualSiteVector, fixture.website, `${fixture.weapon} website branch changed`);
    assert.deepStrictEqual(actualSiteVector, reconstructedSiteVector);
    assert.deepStrictEqual(missionVector, fixture.mission, `${fixture.weapon} mission grid changed`);
    return {
      weapon: fixture.weapon,
      attack: fixture.attack,
      rawVector,
      moddedBaseDamage: total,
      websiteVector: actualSiteVector,
      communityMissionVector: missionVector,
    };
  });
  const braton = probes.find(probe => probe.weapon === 'Braton');
  process.stdout.write(JSON.stringify({
    websiteGridDenominator: denominator,
    communityMissionGridDenominator: 32,
    probes,
    // Preserve the original compact Braton summary for existing evidence
    // readers while exposing the independent class coverage above.
    weapon: braton.weapon,
    attack: braton.attack,
    rawVector: [braton.rawVector.impact, braton.rawVector.puncture, braton.rawVector.slash],
    moddedBaseDamage: braton.moddedBaseDamage,
    websiteVector: [braton.websiteVector.impact, braton.websiteVector.puncture, braton.websiteVector.slash],
    communityMissionVector: [
      braton.communityMissionVector.impact,
      braton.communityMissionVector.puncture,
      braton.communityMissionVector.slash,
    ],
  }, null, 2) + '\n');
}

main().then(() => process.exit(0)).catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exit(1);
});
