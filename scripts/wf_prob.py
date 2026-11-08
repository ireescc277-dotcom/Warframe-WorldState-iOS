#!/usr/bin/env python3
"""Read probabilities out of the history store.

    python3 wf_prob.py --top 20                # by observation count
    python3 wf_prob.py --prefix fis|VoidT3|    # everything under 中纪 fissures
    python3 wf_prob.py --json out.json         # machine-readable dump

`p_model` is the Poisson fit (1 - e^(-lambda t)); `p_empirical` is the share of
observed gaps that were <= t. With little data they disagree, and the empirical
one is the safer read — it makes no assumption about arrivals being memoryless.

Neither is printed until there are 2 days of uptime and 3 arrivals per target;
below that the horizon cells show `-`. One arrival in a 20-minute window yields
a perfectly valid 49%-within-15-minutes, and it would be a lie.
"""

import argparse
import json
import os
import sys

import wf_store

HORIZON_LABEL = [
    (900, "15m"),
    (1800, "30m"),
    (3600, "1h"),
    (7200, "2h"),
    (21600, "6h"),
    (86400, "24h"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=os.environ.get("WF_DB", "/opt/wf-monitor/wf_history.db"))
    parser.add_argument("--prefix", default=None, help="target prefix, e.g. 'fis|VoidT3|'")
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--min-occurrences", type=int, default=1)
    parser.add_argument("--json", default=None, help="write full stats to this path")
    args = parser.parse_args()

    conn = wf_store.init_db(args.db)
    stats = wf_store.target_stats(conn, prefix=args.prefix)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(stats, fh, ensure_ascii=False, indent=1)
        print("wrote %s (%d targets)" % (args.json, len(stats["targets"])))

    arrivals = sum(entry["occurrences"] for entry in stats["targets"])
    print(
        "exposure %.2f days / %d polls / %d rows stored / %d arrivals since recording started / %d targets"
        % (
            stats["exposure_days"],
            stats["polls"],
            stats["occurrences"],
            arrivals,
            len(stats["targets"]),
        )
    )
    if not stats["targets"]:
        print(
            "\nNo arrivals yet: everything currently on the board started before "
            "recording began, and those are deliberately not counted (they would "
            "inflate the rate). Fissures turn over in ~2h, so give it a few hours."
        )
        return 0

    head = "%-46s %6s %9s %9s  %s" % (
        "target",
        "n",
        "lam/day",
        "gap_med",
        " ".join("%6s" % label for _, label in HORIZON_LABEL),
    )
    print(head)
    print("-" * len(head))

    shown = 0
    withheld = 0
    for entry in stats["targets"]:
        if entry["occurrences"] < args.min_occurrences:
            continue
        if shown >= args.top:
            break
        shown += 1
        median = entry["median_gap_seconds"]
        median_txt = "%dm" % (median // 60) if median else "-"
        if entry["confidence"] == "insufficient":
            withheld += 1
            cells = " ".join("%6s" % "-" for _ in HORIZON_LABEL)
            mark = "  (insufficient)"
        else:
            cells = " ".join(
                "%5.1f%%" % (entry["p_model"].get(h, 0) * 100) for h, _ in HORIZON_LABEL
            )
            mark = "" if entry["confidence"] == "ok" else "  (low)"
        print(
            "%-46s %6d %9.2f %9s  %s%s"
            % (entry["target"][:46], entry["occurrences"], entry["lambda_per_day"], median_txt, cells, mark)
        )

    if withheld:
        need_days = stats["thresholds"]["min_exposure_seconds"] / 86400
        print(
            "\n%d of %d targets have too little history to score (needs %.0f days "
            "of uptime and %d arrivals). lam/day is still shown - treat it as "
            "arithmetic, not a rate."
            % (withheld, shown, need_days, stats["thresholds"]["min_arrivals"])
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
