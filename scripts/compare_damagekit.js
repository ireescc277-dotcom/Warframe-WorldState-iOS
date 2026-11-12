#!/usr/bin/env node
/*
 * Development-only parity runner.
 *
 * It runs the checked-in warframe-damage website kernel and the Swift
 * DamageKit CLI against the exact same named weapon / enemy / Mod case.
 * The iOS app never imports this file or executes JavaScript.
 *
 * Website queues are stochastic, while the native simulator currently returns
 * an expectation.  Each case therefore runs a declared, deterministic series
 * of website strategy seeds and compares the native result with the website
 * mean.  A case passes only when that same-layer comparison is within its
 * tolerance.  A source link may document a suspected site divergence, but it
 * never turns a failing case into a pass by itself.
 *
 * Usage:
 *   node scripts/compare_damagekit.js
 *   node scripts/compare_damagekit.js --strict
 *   node scripts/compare_damagekit.js --case paris-prime-charged-shot-lancer-l50
 */
'use strict';

const child = require('child_process');
const fs = require('fs');
const path = require('path');
const K = require('../server/kernel');

const ROOT = path.resolve(__dirname, '..');
const PACKAGE = path.join(ROOT, 'Packages', 'DamageKit');
const DATA_ROOT = path.join(ROOT, 'web', 'app', 'site');
const CASE_FILE = path.join(PACKAGE, 'Parity', 'website-cases.json');
const strict = process.argv.includes('--strict');
const summaryOnly = process.argv.includes('--summary');
const caseArgument = process.argv.indexOf('--case');
const requestedCase = caseArgument >= 0 ? process.argv[caseArgument + 1] : null;
const outputArgument = process.argv.indexOf('--output');
const outputPath = outputArgument >= 0 ? process.argv[outputArgument + 1] : null;

if (caseArgument >= 0 && (!requestedCase || requestedCase.startsWith('--'))) {
  throw new Error('--case requires one exact case id');
}
if (outputArgument >= 0 && (!outputPath || outputPath.startsWith('--'))) {
  throw new Error('--output requires one destination path');
}

function numberAt(object, dottedPath) {
  return dottedPath.split('.').reduce((value, key) => value == null ? undefined : value[key], object);
}

// The website exposes two importantly different quantities for an attack:
// its displayed random-queue median (`dps.armor`, etc.) and the arithmetic
// total of the exact per-projectile queue rows that fed that display.  The
// latter is the only direct counterpart to DamageKit's continuous expected
// target DPS; comparing it prevents a median-presentation difference from
// being mislabeled as a weapon-formula difference.
//
// `queueTotalDps.armor` means sum(arrInfo.armor[attack].totalDmg) / queueLen.
// It intentionally mirrors the site source's `getDmgPerSecond` input, not an
// interpretation invented by this runner.
function websiteMetric(attack, metric) {
  const queueMatch = /^queueTotalDps\.(health|armor|shield|overguard)$/.exec(String(metric));
  const queueDirectMatch = /^queueDirectTotal\.(health|armor|shield|overguard)$/.exec(String(metric));
  if (!queueMatch && !queueDirectMatch) return numberAt(attack, metric);
  const layer = (queueMatch || queueDirectMatch)[1];
  const rows = K.W?.arrInfo?.[layer]?.[attack?.name];
  const queueLength = Number(K.W?.queueLength);
  if (!Array.isArray(rows)) return undefined;
  // The site's `getAvgQueueVal` calls these exact row fields its direct
  // component.  Keep this diagnostic metric distinct from totalDmg: an
  // end-of-window Toxic Lash/DOT tail is presentation-accounted differently
  // by the website and must not obscure validation of its immediate hit.
  if (queueDirectMatch) {
    return rows.reduce((total, row) => total
      + Number(row?.curr_dmg || 0)
      + Number(row?.xataTotal || 0)
      + Number(row?.dmgOnStatusEff || 0)
      + Number(row?.toxicLash?.direct_hit || 0), 0);
  }
  if (!Number.isFinite(queueLength) || queueLength <= 0) return undefined;
  return rows.reduce((total, row) => total + Number(row?.totalDmg || 0), 0) / queueLength;
}

function defenseLayerForMetric(metric) {
  const match = /^(?:dps|queueTotalDps|queueDirectTotal)\.(health|armor|shield|overguard)$/
    .exec(String(metric));
  return match ? match[1] : null;
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function mean(values) {
  return values.reduce((total, value) => total + value, 0) / Math.max(values.length, 1);
}

function standardDeviation(values, average) {
  if (values.length < 2) return 0;
  const variance = values.reduce((total, value) => total + (value - average) ** 2, 0)
    / values.length;
  return Math.sqrt(variance);
}

// A URL plus an assertion is only a lead, not proof that the website is
// wrong.  A case may be accepted outside the numeric tolerance only when the
// fixture records (1) the exact observable site behavior, (2) a concrete
// community/reverse-engineering source that conflicts with it, and (3) why
// that conflict explains this case.  The report keeps that status distinct
// from a numeric match so it cannot be misread as “the two outputs agree”.
function hasWebsiteDivergenceProof(proof, scope) {
  if (!proof || typeof proof !== 'object') return false;
  if (typeof proof.siteObservation !== 'string' || !proof.siteObservation.trim()) return false;
  if (typeof proof.explanation !== 'string' || !proof.explanation.trim()) return false;
  if (!Array.isArray(proof.communitySources) || !proof.communitySources.length) return false;
  // A proof can establish a narrow branch (for example, direct component
  // quantization) without saying anything about a queue total that includes
  // status timing and post-window DOT.  An omitted `scopes` remains backward
  // compatible and applies to both comparisons; new evidence should name its
  // scope explicitly.
  if (proof.scopes !== undefined
    && (!Array.isArray(proof.scopes) || !proof.scopes.includes(scope))) return false;
  return proof.communitySources.every(source => source
    && typeof source.url === 'string' && /^https:\/\//.test(source.url)
    && typeof source.claim === 'string' && source.claim.trim());
}

// DPS is only comparable when the two calculators started from the same target
// state.  The website exposes rounded target values as hp/ar/sh/og while the
// Swift result exposes the corresponding full-precision fields.  Keep this
// check separate from the damage threshold so a target-scaling disagreement
// cannot masquerade as a weapon-formula disagreement.
function compareTargetState(siteTarget, nativeStats, tolerance) {
  const fields = [
    ['health', 'hp'],
    ['armor', 'ar'],
    ['shield', 'sh'],
    ['overguard', 'og'],
  ];
  const rows = fields.map(([nativeField, siteField]) => {
    const site = Number(siteTarget?.[siteField] ?? 0);
    const damageKit = Number(nativeStats?.[nativeField] ?? 0);
    const difference = Math.abs(damageKit - site) / Math.max(Math.abs(site), 1);
    return { field: nativeField, site, damageKit, relativeDifference: difference };
  });
  return {
    tolerance,
    matches: rows.every(row => Number.isFinite(row.site)
      && Number.isFinite(row.damageKit)
      && row.relativeDifference <= tolerance),
    fields: rows,
  };
}

function normalizeAttack(name) {
  return String(name || '').toLowerCase().replace(/[^a-z0-9]/g, '')
    .replace('incarnonformradialattack', 'incarnonradialattack');
}

function findAttack(attacks, name, fieldName) {
  const wanted = normalizeAttack(name);
  const row = (attacks || []).find(attack => normalizeAttack(attack[fieldName]) === wanted);
  if (!row) throw new Error(`attack not found: ${name}`);
  return row;
}

// The local website kernel keeps the queue it actually simulated in `arrInfo`.
// It is intentionally read only for parity diagnostics: it is not part of the
// iOS calculator.  A trace is opt-in per case so ordinary reports stay compact.
function websiteShotTrace(attackName, siteMetric) {
  const layer = String(siteMetric || '').split('.')[1];
  const rows = K.W?.arrInfo?.[layer]?.[attackName];
  if (!Array.isArray(rows)) return null;

  const times = [...new Set(rows
    .map(row => Number(row?.timeM))
    .filter(Number.isFinite)
    .map(time => Number(time.toFixed(9))))]
    .sort((left, right) => left - right);
  const shotNumbers = [...new Set(rows
    .map(row => Number(row?.shotInfo?.shotNumber))
    .filter(Number.isFinite))]
    .sort((left, right) => left - right);

  return {
    defenseLayer: layer,
    queuedProjectiles: rows.length,
    uniqueShotCount: times.length,
    shotNumbers,
    uniqueShotTimes: times.slice(0, 32),
    uniqueShotTimesTruncated: times.length > 32,
  };
}

// A status-order trace answers one narrow question without interpreting the
// website result as a game rule: did a queued projectile both create a status
// and receive the newly-created stack in its own direct-damage calculation?
// This is diagnostic-only and remains outside the native app.
function websiteStatusOrderTrace(attackName, siteMetric, requestedStatus = 'viral') {
  const layer = String(siteMetric || '').split('.')[1];
  const rows = K.W?.arrInfo?.[layer]?.[attackName];
  if (!Array.isArray(rows)) return null;

  const status = String(requestedStatus).toLowerCase();
  const appliedStatuses = row => (Array.isArray(row?.statuses) ? row.statuses : [])
    .map(value => String(value).toLowerCase());
  const statusStacks = row => {
    const key = Object.keys(row?.statusOnEnemy || {})
      .find(candidate => candidate.toLowerCase() === status);
    const value = key ? row.statusOnEnemy[key] : null;
    const stacks = Number(value?.ticks ?? value?.stacks ?? value);
    return Number.isFinite(stacks) ? stacks : 0;
  };
  const summary = row => ({
    time: Number(row?.timeM),
    directDamage: Number(row?.curr_dmg),
    crit: row?.crit ?? null,
    statusesApplied: appliedStatuses(row),
    activeStatusStacks: statusStacks(row),
  });
  const rowIndex = rows.findIndex(row => appliedStatuses(row).includes(status));
  if (rowIndex < 0) {
    return { defenseLayer: layer, status, statusApplied: false };
  }

  const row = rows[rowIndex];
  const before = rows.slice(0, rowIndex);
  const priorStacks = before.reduce((maximum, candidate) => Math.max(maximum, statusStacks(candidate)), 0);
  // Use the most recent earlier hit with the same crit tier and no active
  // stack as the numerical baseline.  Multishot projectiles need not be
  // emitted in the same array position, so equality of queue timestamps is
  // informative but cannot be required for a comparable hit.
  const sameTierPreStatus = before.reverse().find(candidate =>
    candidate?.crit === row?.crit
      && statusStacks(candidate) === 0
      && !appliedStatuses(candidate).includes(status));
  const own = summary(row);
  const comparable = sameTierPreStatus ? summary(sameTierPreStatus) : null;
  const damageRatio = comparable && Number.isFinite(own.directDamage)
    && Number.isFinite(comparable.directDamage) && comparable.directDamage !== 0
    ? own.directDamage / comparable.directDamage
    : null;

  return {
    defenseLayer: layer,
    status,
    statusApplied: true,
    rowIndex,
    priorActiveStacks: priorStacks,
    statusStacksOnApplyingRow: own.activeStatusStacks,
    applyingRow: own,
    sameCritPreStatusComparison: comparable,
    comparisonSharesTimestamp: comparable
      ? Math.abs(comparable.time - own.time) <= 1e-9
      : false,
    applyingToComparisonDamageRatio: damageRatio,
  };
}

function runDamageKit(nativeRequest) {
  const processResult = child.spawnSync(
    'swift',
    ['run', '-c', 'debug', 'damagekit-cli', '-', '--data-root', DATA_ROOT, '--compact'],
    {
      cwd: PACKAGE,
      input: JSON.stringify(nativeRequest),
      encoding: 'utf8',
      maxBuffer: 8 * 1024 * 1024,
    },
  );
  if (processResult.status !== 0) {
    throw new Error(`DamageKit failed: ${(processResult.stderr || processResult.stdout || '').trim()}`);
  }
  const text = (processResult.stdout || '').trim();
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`DamageKit produced non-JSON output: ${text.slice(0, 600)}\n${error.message}`);
  }
}

// Reset the site's deterministic strategy for every invocation.  In a paired
// comparison this keeps the baseline from consuming random values before the
// configured case runs.
async function runWebsiteSample(siteRequest, attackName, siteMetric, seed) {
  const strategist = K.W?.WFOpt;
  if (strategist?.enableStrat) strategist.enableStrat(seed);
  try {
    const site = await K.calc(siteRequest);
    if (site.lostMods?.length) {
      throw new Error('website rejected configured Mod(s): ' + JSON.stringify(site.lostMods));
    }
    if (site.lostIncarnon?.length) {
      throw new Error('website rejected configured Incarnon choice(s): '
        + JSON.stringify(site.lostIncarnon));
    }
    const attack = findAttack(site.attacks, attackName, 'name');
    const value = websiteMetric(attack, siteMetric);
    if (!Number.isFinite(value)) {
      throw new Error(`website metric ${siteMetric} unavailable for ${attackName}`);
    }
    return { site, attack, value };
  } finally {
    if (strategist?.disableStrat) strategist.disableStrat();
  }
}

async function runCase(testCase) {
  const configuredSeeds = Array.isArray(testCase.siteSeeds) ? testCase.siteSeeds : null;
  const samples = Math.max(1, Number(testCase.samples || 61));
  const seeds = configuredSeeds && configuredSeeds.length
    ? configuredSeeds.map(Number)
    : Array.from({ length: samples }, (_, index) => index + 1);
  const siteMetric = testCase.compare?.siteMetric || 'dps.health';
  const nativeMetric = testCase.compare?.nativeMetric || 'dps';
  const aggregation = testCase.compare?.aggregation || 'mean';
  const defenseLayer = defenseLayerForMetric(siteMetric);
  if (!defenseLayer) {
    throw new Error(`website metric ${siteMetric} does not name one defense layer`);
  }
  const directSiteMetric = `queueDirectTotal.${defenseLayer}`;
  // `dps.<layer>` is the website UI's median after it bins stochastic queue
  // rows into seconds. DamageKit's current `targetDps` is a continuous mean,
  // so treating those two labels as the same number would make the parity
  // threshold depend on distribution shape rather than the damage formula.
  // A presentation case may explicitly use a `queueMedianDps` field once the
  // native queue renderer exists. Formula details are also reported below as
  // a direct-total comparison, which deliberately excludes DOT tail-display
  // behavior from an immediate-hit calculation.
  if (/^dps\.(health|armor|shield|overguard)$/.test(siteMetric)
      && nativeMetric !== 'queueMedianDps') {
    throw new Error(`website UI metric ${siteMetric} requires native queueMedianDps; `
      + 'use queueTotalDps.<layer> for formula parity');
  }
  // Some effect checks deliberately compare a feature's increment relative to
  // the same build without that feature.  The absolute comparison remains in
  // its own fixture; this mode never hides it.
  const relativeToBaseline = testCase.compare?.relativeToBaseline === true;
  if (relativeToBaseline && (!testCase.siteBaseline || !testCase.nativeBaseline)) {
    throw new Error('relativeToBaseline requires siteBaseline and nativeBaseline');
  }
  const siteValues = [];
  const siteBaselineValues = [];
  const directSiteValues = [];
  const directSiteBaselineValues = [];
  let siteTarget = null;
  let siteShotTrace = null;
  let siteStatusOrderTrace = null;

  for (const seed of seeds) {
    const sample = await runWebsiteSample(testCase.site, testCase.attack, siteMetric, seed);
    if (!siteTarget) {
      siteTarget = sample.site.target;
    }
    // `arrInfo` belongs to the just-completed website run, so capture the
    // optional source trace before running a paired baseline.
    if (testCase.captureShotTrace && !siteShotTrace) {
      siteShotTrace = websiteShotTrace(sample.attack.name, siteMetric);
    }
    if (testCase.captureStatusOrderTrace && !siteStatusOrderTrace) {
      const requestedStatus = typeof testCase.captureStatusOrderTrace === 'string'
        ? testCase.captureStatusOrderTrace
        : 'viral';
      siteStatusOrderTrace = websiteStatusOrderTrace(sample.attack.name, siteMetric, requestedStatus);
    }
    siteValues.push(sample.value);
    const directValue = websiteMetric(sample.attack, directSiteMetric);
    if (!Number.isFinite(directValue)) {
      throw new Error(`website metric ${directSiteMetric} unavailable for ${testCase.attack}`);
    }
    directSiteValues.push(directValue);
    if (relativeToBaseline) {
      const baseline = await runWebsiteSample(testCase.siteBaseline, testCase.attack, siteMetric, seed);
      siteBaselineValues.push(baseline.value);
      const directBaselineValue = websiteMetric(baseline.attack, directSiteMetric);
      if (!Number.isFinite(directBaselineValue)) {
        throw new Error(`website baseline metric ${directSiteMetric} unavailable for ${testCase.attack}`);
      }
      directSiteBaselineValues.push(directBaselineValue);
    }
  }

  const native = runDamageKit(testCase.native);
  const nativeAttack = findAttack(native.attacks, testCase.attack, 'attack');
  const nativeRawValue = numberAt(nativeAttack, nativeMetric);
  if (!Number.isFinite(nativeRawValue)) {
    throw new Error(`DamageKit metric ${nativeMetric} unavailable for ${testCase.attack}`);
  }
  const nativeDirectRawValue = numberAt(nativeAttack, 'targetDirectDamage');
  if (!Number.isFinite(nativeDirectRawValue)) {
    throw new Error(`DamageKit targetDirectDamage unavailable for ${testCase.attack}`);
  }

  let nativeValue = nativeRawValue;
  let nativeBaselineValue = null;
  let nativeDirectValue = nativeDirectRawValue;
  let nativeDirectBaselineValue = null;
  if (relativeToBaseline) {
    const nativeBaseline = runDamageKit(testCase.nativeBaseline);
    const nativeBaselineAttack = findAttack(nativeBaseline.attacks, testCase.attack, 'attack');
    nativeBaselineValue = numberAt(nativeBaselineAttack, nativeMetric);
    if (!Number.isFinite(nativeBaselineValue) || Math.abs(nativeBaselineValue) <= 1e-12) {
      throw new Error(`DamageKit baseline metric ${nativeMetric} is unavailable or zero for ${testCase.attack}`);
    }
    nativeDirectBaselineValue = numberAt(nativeBaselineAttack, 'targetDirectDamage');
    if (!Number.isFinite(nativeDirectBaselineValue) || Math.abs(nativeDirectBaselineValue) <= 1e-12) {
      throw new Error(`DamageKit baseline targetDirectDamage is unavailable or zero for ${testCase.attack}`);
    }
  }

  const siteMean = mean(siteValues);
  const siteMedian = median(siteValues);
  const siteRawValue = aggregation === 'median' ? siteMedian : siteMean;
  if (aggregation !== 'mean' && aggregation !== 'median') {
    throw new Error(`unsupported website aggregation: ${aggregation}`);
  }
  let siteValue = siteRawValue;
  let siteBaselineValue = null;
  const directSiteMean = mean(directSiteValues);
  const directSiteMedian = median(directSiteValues);
  const directSiteRawValue = aggregation === 'median' ? directSiteMedian : directSiteMean;
  let directSiteValue = directSiteRawValue;
  let directSiteBaselineValue = null;
  if (relativeToBaseline) {
    const siteBaselineMean = mean(siteBaselineValues);
    const siteBaselineMedian = median(siteBaselineValues);
    siteBaselineValue = aggregation === 'median' ? siteBaselineMedian : siteBaselineMean;
    if (Math.abs(siteBaselineValue) <= 1e-12) {
      throw new Error(`website baseline metric ${siteMetric} is zero for ${testCase.attack}`);
    }
    siteValue = (siteRawValue - siteBaselineValue) / siteBaselineValue;
    nativeValue = (nativeRawValue - nativeBaselineValue) / nativeBaselineValue;
    const directSiteBaselineMean = mean(directSiteBaselineValues);
    const directSiteBaselineMedian = median(directSiteBaselineValues);
    directSiteBaselineValue = aggregation === 'median'
      ? directSiteBaselineMedian
      : directSiteBaselineMean;
    if (Math.abs(directSiteBaselineValue) <= 1e-12) {
      throw new Error(`website baseline metric ${directSiteMetric} is zero for ${testCase.attack}`);
    }
    directSiteValue = (directSiteRawValue - directSiteBaselineValue) / directSiteBaselineValue;
    nativeDirectValue = (nativeDirectRawValue - nativeDirectBaselineValue)
      / nativeDirectBaselineValue;
  }
  const difference = Math.abs(nativeValue - siteValue) / Math.max(Math.abs(siteValue), 1e-12);
  const directDifference = Math.abs(nativeDirectValue - directSiteValue)
    / Math.max(Math.abs(directSiteValue), 1e-12);
  const tolerance = Number(testCase.tolerance ?? 0.05);
  const targetTolerance = Number(testCase.targetTolerance ?? 0.005);
  const targetAgreement = compareTargetState(siteTarget, native.enemyStats, targetTolerance);
  const siteDivergenceEvidence = testCase.siteDivergenceEvidence;
  const websiteDivergenceProof = testCase.websiteDivergenceProof;
  const websiteTargetDivergenceProof = testCase.websiteTargetDivergenceProof;
  // A target-state proof is deliberately reported separately. It explains why
  // a weapon row cannot be compared yet; it must never turn that row into a
  // numerical damage pass merely because the site started from the wrong HP.
  const hasTargetDivergenceProof = !targetAgreement.matches
    && hasWebsiteDivergenceProof(websiteTargetDivergenceProof, 'target');
  const targetAgreementWithStatus = {
    ...targetAgreement,
    status: targetAgreement.matches
      ? 'pass'
      : hasTargetDivergenceProof
        ? 'source-backed-site-divergence'
        : 'unresolved',
  };
  const numericallyMatches = difference <= tolerance && targetAgreement.matches;
  // A formula proof cannot rescue a case whose target was not even initialized
  // to the same HP/armor/shield/overguard state.  Such a row remains a target
  // setup failure, not evidence that either damage formula is wrong.
  // A fixture whose primary metric is already the site's immediate-hit queue
  // must consume a direct-parity proof.  Treating it as generic "behavior"
  // would force authors to overstate a proof that says nothing about DOT or
  // timeline presentation merely to classify an immediate-hit comparison.
  const primaryProofScope = /^queueDirectTotal\.(health|armor|shield|overguard)$/.test(siteMetric)
    ? 'directParity'
    : 'behavior';
  const hasPrimaryDivergenceProof = hasWebsiteDivergenceProof(
    websiteDivergenceProof,
    primaryProofScope,
  )
    && targetAgreement.matches;
  const hasDirectDivergenceProof = hasWebsiteDivergenceProof(websiteDivergenceProof, 'directParity')
    && targetAgreement.matches;
  const status = numericallyMatches
    ? 'pass'
    : hasPrimaryDivergenceProof
      ? 'source-backed-site-divergence'
      : siteDivergenceEvidence?.url && siteDivergenceEvidence?.claim
        ? 'unresolved-with-site-divergence-evidence'
        : 'unresolved';
  const directStatus = directDifference <= tolerance && targetAgreement.matches
    ? 'pass'
    : hasDirectDivergenceProof
      ? 'source-backed-site-divergence'
      : siteDivergenceEvidence?.url && siteDivergenceEvidence?.claim
        ? 'unresolved-with-site-divergence-evidence'
        : 'unresolved';

  return {
    id: testCase.id,
    description: testCase.description,
    attack: testCase.attack,
    status,
    tolerance,
    site: {
      metric: siteMetric,
      aggregation,
      value: siteValue,
      relativeToBaseline,
      rawValue: relativeToBaseline ? siteRawValue : undefined,
      baselineValue: siteBaselineValue,
      deltaValue: relativeToBaseline ? siteRawValue - siteBaselineValue : undefined,
      mean: siteMean,
      median: siteMedian,
      min: Math.min(...siteValues),
      max: Math.max(...siteValues),
      standardDeviation: standardDeviation(siteValues, siteMean),
      samples: siteValues.length,
      seedSeries: configuredSeeds
        ? { count: seeds.length, values: seeds }
        : { count: seeds.length, first: seeds[0], last: seeds[seeds.length - 1] },
      shotTrace: siteShotTrace,
      statusOrderTrace: siteStatusOrderTrace,
    },
    damageKit: {
      metric: nativeMetric,
      value: nativeValue,
      rawValue: relativeToBaseline ? nativeRawValue : undefined,
      baselineValue: nativeBaselineValue,
      deltaValue: relativeToBaseline ? nativeRawValue - nativeBaselineValue : undefined,
      shots: nativeAttack.shots,
    },
    relativeDifference: difference,
    directParity: {
      metric: directSiteMetric,
      nativeMetric: 'targetDirectDamage',
      status: directStatus,
      value: directSiteValue,
      nativeValue: nativeDirectValue,
      relativeToBaseline,
      rawValue: relativeToBaseline ? directSiteRawValue : undefined,
      nativeRawValue: relativeToBaseline ? nativeDirectRawValue : undefined,
      baselineValue: directSiteBaselineValue,
      nativeBaselineValue: nativeDirectBaselineValue,
      deltaValue: relativeToBaseline ? directSiteRawValue - directSiteBaselineValue : undefined,
      nativeDeltaValue: relativeToBaseline
        ? nativeDirectRawValue - nativeDirectBaselineValue
        : undefined,
      mean: directSiteMean,
      median: directSiteMedian,
      min: Math.min(...directSiteValues),
      max: Math.max(...directSiteValues),
      standardDeviation: standardDeviation(directSiteValues, directSiteMean),
      relativeDifference: directDifference,
    },
    targetAgreement: targetAgreementWithStatus,
    siteDivergenceEvidence: siteDivergenceEvidence || null,
    websiteDivergenceProof: websiteDivergenceProof || null,
    websiteTargetDivergenceProof: websiteTargetDivergenceProof || null,
  };
}

async function main() {
  const suite = JSON.parse(fs.readFileSync(CASE_FILE, 'utf8'));
  if (!Array.isArray(suite.cases) || !suite.cases.length) {
    throw new Error('parity case file contains no cases');
  }
  const selectedCases = requestedCase
    ? suite.cases.filter(testCase => testCase.id === requestedCase)
    : suite.cases;
  if (!selectedCases.length) {
    throw new Error(`unknown parity case: ${requestedCase}`);
  }
  await K.boot();
  const rows = [];
  for (const testCase of selectedCases) {
    process.stderr.write(`[parity] ${testCase.id}\n`);
    try {
      rows.push(await runCase(testCase));
    } catch (error) {
      rows.push({ id: testCase.id, description: testCase.description, status: 'runner-error', error: error.message });
    }
  }
  const accepted = rows.filter(row => row.status === 'pass'
    || row.status === 'source-backed-site-divergence');
  const sourceBackedDivergences = rows.filter(row => row.status === 'source-backed-site-divergence');
  const unresolved = rows.filter(row => !accepted.includes(row));
  const directAccepted = rows.filter(row => row.directParity
    && (row.directParity.status === 'pass'
      || row.directParity.status === 'source-backed-site-divergence'));
  const directSourceBackedDivergences = rows.filter(row => row.directParity
    && row.directParity.status === 'source-backed-site-divergence');
  const directUnresolved = rows.filter(row => !row.directParity || !directAccepted.includes(row));
  const targetSourceBackedDivergences = rows.filter(row => row.targetAgreement
    && row.targetAgreement.status === 'source-backed-site-divergence');
  const report = {
    generatedAt: new Date().toISOString(),
    caseFile: path.relative(ROOT, CASE_FILE).replace(/\\/g, '/'),
    threshold: 'The primary comparison records website queue behavior on the same defense layer. directParity separately compares the same queued immediate-hit total with DamageKit targetDirectDamage, excluding DOT-tail presentation behavior. Either comparison is accepted only within tolerance on the same initialized target state, or with a fixture carrying a concrete community formula source that explains a website divergence. A source-backed divergence is reported separately and never means the values matched.',
    accepted: accepted.length,
    passed: rows.filter(row => row.status === 'pass').length,
    sourceBackedDivergences: sourceBackedDivergences.length,
    unresolved: unresolved.length,
    directAccepted: directAccepted.length,
    directPassed: rows.filter(row => row.directParity?.status === 'pass').length,
    directSourceBackedDivergences: directSourceBackedDivergences.length,
    directUnresolved: directUnresolved.length,
    targetSourceBackedDivergences: targetSourceBackedDivergences.length,
    cases: rows,
  };
  // The full per-seed diagnostic can be large.  CI and interactive progress
  // checks need a compact, lossless pass/fail view without writing a report
  // file or hiding unresolved rows behind a total count.
  const output = summaryOnly
    ? {
      ...report,
      cases: rows.map(row => ({
        id: row.id,
        status: row.status,
        behaviorPercent: Number.isFinite(row.relativeDifference)
          ? row.relativeDifference * 100
          : null,
        directStatus: row.directParity?.status ?? null,
        directPercent: Number.isFinite(row.directParity?.relativeDifference)
          ? row.directParity.relativeDifference * 100
          : null,
        targetMatches: row.targetAgreement?.matches ?? false,
        targetStatus: row.targetAgreement?.status ?? null,
        error: row.error ?? null,
      })),
    }
    : report;
  const rendered = JSON.stringify(output, null, 2) + '\n';
  if (outputPath) {
    fs.writeFileSync(path.resolve(outputPath), rendered, 'utf8');
    process.stderr.write(`[parity] wrote ${path.resolve(outputPath)}\n`);
  } else {
    process.stdout.write(rendered);
  }
  if (strict && (unresolved.length || directUnresolved.length)) process.exitCode = 1;
}

main().catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
