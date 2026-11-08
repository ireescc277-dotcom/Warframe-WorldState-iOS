#!/usr/bin/env python3
"""Occurrence store for Warframe world-state events.

Design notes
------------
The point of this database is answering "how often does node X show up", so it
stores *appearances*, not snapshots. A full worldState snapshot is ~190 KB and
would be fetched every 120 s (≈140 MB/day) — almost all of it repeated. One
occurrence row is ~200 B, and a full fissure rotation adds ~30 rows, so the same
day is a few hundred KB.

Every row is keyed by the source's own `_id`, which stays constant for the whole
life of an occurrence. That makes writes idempotent: polling the same rotation
twice updates `last_seen` and nothing else, so a restart or a duplicated poll
cannot inflate the counts.

Two things make the probability honest:

* `poll` records every attempt with `ok`. Uptime is derived from those rows, not
  assumed, so downtime shrinks the denominator instead of silently recording
  "the node did not appear".
* Arrival times come from the feed's own `Activation`/`Expiry` (exact to the
  millisecond), not from when we happened to first see them.

Target keys are the same strings the iOS app's watch tree uses, which means the
app can ask about any branch it can select, and prefix matching gives the
aggregates for free (`fis|VoidT3|%` = every 中纪 fissure).
"""

import json
import math
import os
import sqlite3
import time
from datetime import datetime, timezone

# A rate needs two things before it means anything: enough wall-clock time that
# the denominator is real, and enough arrivals that the numerator is not one
# coincidence. Two days and three arrivals is the floor below which the numbers
# are withheld rather than shown with a confidence interval nobody reads.
MIN_EXPOSURE_SECONDS = 2 * 86400
MIN_ARRIVALS = 3

SCHEMA = """
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;

CREATE TABLE IF NOT EXISTS poll (
    ts    INTEGER PRIMARY KEY,
    ok    INTEGER NOT NULL,
    ms    INTEGER,
    bytes INTEGER,
    note  TEXT
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS occurrence (
    key        TEXT PRIMARY KEY,
    kind       TEXT NOT NULL,
    target     TEXT NOT NULL,
    node_id    TEXT,
    mode       TEXT,
    era        TEXT,
    hard       INTEGER NOT NULL DEFAULT 0,
    planet     TEXT,
    starts_at  INTEGER,
    ends_at    INTEGER,
    first_seen INTEGER NOT NULL,
    last_seen  INTEGER NOT NULL,
    seen       INTEGER NOT NULL DEFAULT 1,
    meta       TEXT,
    source     TEXT NOT NULL DEFAULT 'live'
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS occurrence_kind_target
    ON occurrence (kind, target, starts_at);
CREATE INDEX IF NOT EXISTS occurrence_kind_start
    ON occurrence (kind, starts_at);
CREATE INDEX IF NOT EXISTS occurrence_node
    ON occurrence (kind, node_id, starts_at);
"""

# Mirrors WatchTree.swift `invasionRewards`. Kept here because the recorder runs
# on a box that has no Swift toolchain; if the app's list changes, change both.
INVASION_REWARDS = [
    ("potato", "catalyst", ["Catalyst", "催化剂"]),
    ("potato", "reactor", ["Reactor", "反应堆"]),
    ("forma", "forma", ["Forma"]),
    ("exilus", "exilus_wf", ["ExilusAdapter", "Exilus"]),
    ("exilus", "exilus_wp", ["WeaponExilus"]),
    ("weapon", "karak_wraith", ["KarakWraith"]),
    ("weapon", "dera_vandal", ["DeraVandal"]),
    ("weapon", "strun_wraith", ["StrunWraith"]),
    ("weapon", "snipetron_vandal", ["SnipetronVandal"]),
    ("weapon", "latron_wraith", ["LatronWraith"]),
    ("weapon", "twin_vipers_wraith", ["TwinVipersWraith"]),
    ("weapon", "sheev", ["Sheev"]),
    ("resource", "mutagen_mass", ["Mutagen"]),
    ("resource", "fieldron", ["Fieldron"]),
    ("resource", "detonite", ["Detonite"]),
    ("rare", "riven_sliver", ["RivenSliver", "裂罅碎石"]),
    ("rare", "kavat_code", ["KavatCode", "Kavat"]),
    ("rare", "nitain", ["Nitain"]),
    ("rare", "orokin_cell", ["OrokinCell"]),
]

# The app normalises these two to one branch; so does the store, otherwise the
# same mission would land in two different targets.
MODE_ALIASES = {"MT_DISRUPTION": "MT_ARTIFACT"}

DEFAULT_DB = os.environ.get("WF_DB", "/opt/wf-monitor/wf_history.db")


def init_db(path=DEFAULT_DB):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    conn = sqlite3.connect(path, timeout=30)
    conn.executescript(SCHEMA)
    # 老库没有 source 列：加列比重建安全，回填的数据都是新增行。
    cols = {row[1] for row in conn.execute("PRAGMA table_info(occurrence)")}
    if "source" not in cols:
        conn.execute("ALTER TABLE occurrence ADD COLUMN source TEXT NOT NULL DEFAULT 'live'")
    conn.commit()
    return conn


# MARK: - Parsing helpers


def _ms(value):
    """`{"$date": {"$numberLong": "1794047343120"}}` -> unix seconds."""
    if not isinstance(value, dict):
        return None
    inner = value.get("$date")
    if isinstance(inner, dict):
        raw = inner.get("$numberLong")
    else:
        raw = inner
    if raw is None:
        return None
    try:
        return int(raw) // 1000
    except (TypeError, ValueError):
        return None


def _oid(entry):
    raw = entry.get("_id")
    if isinstance(raw, dict):
        raw = raw.get("$oid")
    return raw if isinstance(raw, str) else None


def _as_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, dict):
        inner = value.get("$numberLong")
        if inner is not None:
            try:
                return int(inner) != 0
            except (TypeError, ValueError):
                return False
    if isinstance(value, (int, float)):
        return value != 0
    return False


def load_node_meta(path):
    """nodeID -> {mode, planet}.

    Accepts either the app's full DefaultDict.json or the trimmed flat map the
    deploy script ships to the server, so the same loader works in both places.
    """
    with open(path, "r", encoding="utf-8") as fh:
        payload = json.load(fh)
    nodes = payload.get("nodes") if isinstance(payload.get("nodes"), dict) else payload
    meta = {}
    for node_id, info in nodes.items():
        if isinstance(info, dict):
            meta[node_id] = {"mode": info.get("mt", info.get("mode")),
                             "planet": info.get("planet")}
    return meta


def _iso_z(value):
    """`2026-11-08T04:05:30.000Z` -> unix seconds (UTC)."""
    if not value or not isinstance(value, str):
        return None
    text = value.strip().replace("Z", "+00:00")[:32]
    try:
        return int(datetime.fromisoformat(text).replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        return None


def canonical_mode(raw):
    return MODE_ALIASES.get(raw, raw)


# MARK: - Extraction


def _fissure_rows(state, node_meta, poll_ts):
    rows = []
    for entry in state.get("ActiveMissions") or []:
        oid = _oid(entry)
        node = entry.get("Node")
        era = entry.get("Modifier")
        mode = canonical_mode(entry.get("MissionType") or "")
        if not (oid and node and era and mode):
            continue
        hard = 1 if _as_bool(entry.get("Hard")) else 0
        rows.append({
            "key": oid,
            "kind": "fissure",
            "target": "fis|%s|%s|%s|%s" % (era, "sp" if hard else "nm", mode, node),
            "node_id": node,
            "mode": mode,
            "era": era,
            "hard": hard,
            "planet": (node_meta.get(node) or {}).get("planet"),
            "starts_at": _ms(entry.get("Activation")),
            "ends_at": _ms(entry.get("Expiry")),
            "first_seen": poll_ts,
            "meta": None,
        })
    return rows


def _invasion_rows(state, node_meta, poll_ts):
    rows = []
    for entry in state.get("Invasions") or []:
        oid = _oid(entry)
        node = entry.get("Node")
        if not (oid and node):
            continue
        if _as_bool(entry.get("Completed")):
            continue

        haystack = json.dumps(
            {
                "attacker": entry.get("AttackerReward"),
                "defender": entry.get("DefenderReward"),
            },
            ensure_ascii=False,
        )
        matched = [
            (category, reward_id)
            for category, reward_id, keywords in INVASION_REWARDS
            if any(kw in haystack for kw in keywords)
        ]
        starts = _ms(entry.get("Activation"))
        ends = _ms(entry.get("Expiry"))
        for category, reward_id in matched:
            rows.append({
                "key": "%s|%s" % (oid, reward_id),
                "kind": "invasion",
                "target": "inv|%s|%s" % (category, reward_id),
                "node_id": node,
                "mode": None,
                "era": None,
                "hard": 0,
                "planet": (node_meta.get(node) or {}).get("planet"),
                "starts_at": starts,
                "ends_at": ends,
                "first_seen": poll_ts,
                "meta": None,
            })
    return rows


def _storm_rows(state, node_meta, poll_ts):
    rows = []
    for entry in state.get("VoidStorms") or []:
        oid = _oid(entry)
        era = entry.get("ActiveMissionTier")
        node = entry.get("Node")
        if not (oid and era):
            continue
        rows.append({
            "key": oid,
            "kind": "storm",
            "target": "storm|%s" % era,
            "node_id": node,
            "mode": None,
            "era": era,
            "hard": 0,
            "planet": (node_meta.get(node) or {}).get("planet"),
            "starts_at": _ms(entry.get("Activation")),
            "ends_at": _ms(entry.get("Expiry")),
            "first_seen": poll_ts,
            "meta": None,
        })
    return rows


def _arbitration_rows(arb, node_meta, poll_ts):
    if not arb:
        return []
    node = arb.get("nodeKey")
    if not node or node == "SolNode000":
        return []
    if arb.get("expired") is True or (arb.get("type") or "Unknown") == "Unknown":
        return []

    info = node_meta.get(node) or {}
    mode = info.get("mode")
    planet = info.get("planet")
    if not mode or not planet:
        # A node the app cannot place in the tree cannot be matched either.
        return []

    return [{
        "key": arb.get("id") or "arb|%s|%s" % (node, arb.get("expiry") or ""),
        "kind": "arbitration",
        "target": "arb|%s|%s|%s" % (mode, planet, node),
        "node_id": node,
        "mode": mode,
        "era": None,
        "hard": 0,
        "planet": planet,
        "starts_at": _iso_z(arb.get("activation")),
        "ends_at": _iso_z(arb.get("expiry")),
        "first_seen": poll_ts,
        "meta": json.dumps({"type": arb.get("type")}, ensure_ascii=False),
    }]


def extract_rows(state, node_meta, poll_ts, arbitration=None):
    rows = []
    rows.extend(_fissure_rows(state, node_meta, poll_ts))
    rows.extend(_invasion_rows(state, node_meta, poll_ts))
    rows.extend(_storm_rows(state, node_meta, poll_ts))
    rows.extend(_arbitration_rows(arbitration, node_meta, poll_ts))
    return rows


# MARK: - Writes


UPSERT = """
INSERT INTO occurrence
    (key, kind, target, node_id, mode, era, hard, planet,
     starts_at, ends_at, first_seen, last_seen, seen, meta, source)
VALUES (:key, :kind, :target, :node_id, :mode, :era, :hard, :planet,
        :starts_at, :ends_at, :first_seen, :first_seen, 1, :meta, :source)
ON CONFLICT(key) DO UPDATE SET
    last_seen = excluded.last_seen,
    ends_at   = COALESCE(excluded.ends_at, occurrence.ends_at),
    starts_at = COALESCE(occurrence.starts_at, excluded.starts_at),
    seen      = occurrence.seen + (excluded.first_seen > occurrence.last_seen),
    meta      = COALESCE(excluded.meta, occurrence.meta)
"""


def record_poll(conn, ts, ok, ms=None, byte_count=None, note=None):
    conn.execute(
        "INSERT OR REPLACE INTO poll (ts, ok, ms, bytes, note) VALUES (?,?,?,?,?)",
        (int(ts), 1 if ok else 0, ms, byte_count, note),
    )


def write_rows(conn, rows):
    if not rows:
        return 0
    payload = [r if "source" in r else {**r, "source": "live"} for r in rows]
    before = conn.total_changes
    conn.executemany(UPSERT, payload)
    return conn.total_changes - before


# MARK: - Queries


def exposure_seconds(conn, poll_interval=120, max_gap_factor=5):
    """Seconds the recorder was actually up.

    A gap longer than `max_gap_factor` intervals is downtime, not observation,
    so it is capped instead of being counted as "nothing appeared".
    """
    cap = poll_interval * max_gap_factor
    rows = conn.execute(
        "SELECT ts FROM poll WHERE ok = 1 ORDER BY ts"
    ).fetchall()
    if len(rows) < 2:
        return 0
    total = 0
    for (prev,), (cur,) in zip(rows, rows[1:]):
        total += min(cur - prev, cap)
    return total


def target_stats(conn, prefix=None):
    """Per-target arrival statistics.

    Only arrivals that began after recording started are counted. That matters:
    on the very first poll ~26 fissures are already running, and treating them
    as arrivals inside a one-minute window would report a rate 26x too high.

    `lam` is arrivals per second of observed uptime — the Poisson rate.
    `p_model` is 1 - e^(-lam*t); `p_empirical` is the share of observed gaps
    that were <= t, which needs no assumption about memorylessness and is the
    better read while the sample is small.

    Both are withheld until the sample can carry them. One arrival in a
    20-minute window is a mathematically valid rate of ~72/day and a claimed
    49% chance within 15 minutes; it is also pure noise. `confidence` is
    "insufficient" below MIN_EXPOSURE_SECONDS or MIN_ARRIVALS, and in that
    case the p maps come back empty rather than plausible-looking.
    """
    first_ok, last_ok = conn.execute(
        "SELECT MIN(ts), MAX(ts) FROM poll WHERE ok = 1"
    ).fetchone()
    # 回填进来的仲裁历史比实际观测早一年半，窗口起点必须跟着退回去；
    # 否则那些行会被当成"观测开始之前就在跑"而被整段排除。
    back_first, back_last = conn.execute(
        "SELECT MIN(starts_at), MAX(COALESCE(ends_at, starts_at))"
        " FROM occurrence WHERE source = 'backfill'"
    ).fetchone() or (None, None)
    window_start = min([x for x in (first_ok, back_first) if x] or [0])

    clause = "AND COALESCE(starts_at, first_seen) >= ?"
    args = [window_start]
    if prefix:
        clause = "WHERE target LIKE ? " + clause
        args = [prefix + "%", window_start]
    else:
        clause = "WHERE 1 = 1 " + clause

    rows = conn.execute(
        """
        SELECT target, kind, node_id, COUNT(*) AS n,
               MIN(starts_at) AS first_at, MAX(starts_at) AS last_at,
               SUM(COALESCE(ends_at, last_seen) - COALESCE(starts_at, first_seen)) AS busy
        FROM occurrence
        %s
        GROUP BY target
        ORDER BY n DESC
        """ % clause,
        args,
    ).fetchall()

    exposure = exposure_seconds(conn)
    # 仲裁的分母不能是"我们开机了多久"，那是回填数据覆盖的时长。
    back_exposure = (back_last - back_first) if (back_first and back_last) else 0
    arb_exposure = max(exposure, back_exposure)
    horizons = (900, 1800, 3600, 7200, 21600, 86400)
    out = []

    for target, kind, node_id, n, first_at, last_at, busy in rows:
        starts = [
            r[0] for r in conn.execute(
                "SELECT COALESCE(starts_at, first_seen) FROM occurrence"
                " WHERE target = ? AND COALESCE(starts_at, first_seen) >= ?"
                " ORDER BY 1",
                (target, window_start),
            )
        ]
        gaps = [b - a for a, b in zip(starts, starts[1:]) if b > a]
        gaps.sort()

        span = arb_exposure if kind == "arbitration" else exposure
        lam = (n / span) if span else 0.0
        if span < MIN_EXPOSURE_SECONDS or n < MIN_ARRIVALS:
            confidence = "insufficient"
        elif span < MIN_EXPOSURE_SECONDS * 3.5 or n < MIN_ARRIVALS * 3:
            confidence = "low"
        else:
            confidence = "ok"
        entry = {
            "target": target,
            "kind": kind,
            "node_id": node_id,
            "occurrences": n,
            "first_at": first_at,
            "last_at": last_at,
            "busy_seconds": busy or 0,
            "confidence": confidence,
            "lambda_per_day": round(lam * 86400, 3),
            "mean_gap_seconds": int(sum(gaps) / len(gaps)) if gaps else None,
            "median_gap_seconds": gaps[len(gaps) // 2] if gaps else None,
            "p_model": {},
            "p_empirical": {},
        }
        if confidence != "insufficient":
            for h in horizons:
                entry["p_model"][h] = round(1 - math.exp(-lam * h), 4) if lam else 0.0
                if gaps:
                    entry["p_empirical"][h] = round(
                        sum(1 for g in gaps if g <= h) / len(gaps), 4
                    )
        out.append(entry)

    return {
        "exposure_seconds": exposure,
        "exposure_days": round(exposure / 86400, 3),
        "exposure_backfill_days": round(back_exposure / 86400, 3),
        "polls": conn.execute("SELECT COUNT(*) FROM poll").fetchone()[0],
        "occurrences": conn.execute("SELECT COUNT(*) FROM occurrence").fetchone()[0],
        "thresholds": {
            "min_exposure_seconds": MIN_EXPOSURE_SECONDS,
            "min_arrivals": MIN_ARRIVALS,
        },
        "targets": out,
    }
