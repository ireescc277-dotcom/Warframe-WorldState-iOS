#!/usr/bin/env python3
"""Poll Warframe world state and append occurrences to the history store.

Runs on the VPS as a systemd unit. One poll every two minutes, one transaction
per poll: if the write fails, the poll row fails with it, so the row count and the
uptime never disagree.

    python3 wf_record.py --once        # single cycle, useful for smoke tests
    python3 wf_record.py               # loop
"""

import argparse
import json
import os
import signal
import sys
import time
import urllib.error
import urllib.request

import wf_store

WORLDSTATE_URL = "https://api.warframe.com/cdn/worldState.php"
ARBITRATION_URL = "https://api.warframestat.us/pc/arbitration?language=en"
USER_AGENT = "WarframeWatch-recorder/1.0 (+history)"

STOP = False


def _stop(signum, frame):
    global STOP
    STOP = True


def fetch_json(url, timeout=20):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = response.read()
    return json.loads(payload.decode("utf-8")), len(payload)


def one_cycle(conn, node_meta, interval):
    ts = int(time.time())
    started = time.monotonic()

    try:
        state, size = fetch_json(WORLDSTATE_URL)
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        ms = int((time.monotonic() - started) * 1000)
        wf_store.record_poll(conn, ts, False, ms=ms, note=str(exc)[:200])
        conn.commit()
        print("poll %d FAILED: %s" % (ts, exc), flush=True)
        return False

    # Arbitration is a separate service and often down or placeholder; a failure
    # there must not fail the poll, which is about the official feed.
    arbitration = None
    try:
        arbitration, _ = fetch_json(ARBITRATION_URL, timeout=10)
    except Exception:
        pass

    rows = wf_store.extract_rows(state, node_meta, ts, arbitration=arbitration)
    ms = int((time.monotonic() - started) * 1000)

    try:
        wf_store.record_poll(conn, ts, True, ms=ms, byte_count=size)
        changed = wf_store.write_rows(conn, rows)
        conn.commit()
    except Exception as exc:
        conn.rollback()
        print("poll %d WRITE FAILED: %s" % (ts, exc), flush=True)
        return False

    print(
        "poll %d ok %dB %dms rows=%d touched=%d"
        % (ts, size, ms, len(rows), changed),
        flush=True,
    )
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=os.environ.get("WF_DB", "/opt/wf-monitor/wf_history.db"))
    parser.add_argument("--dict", default=os.environ.get("WF_DICT", "/opt/wf-monitor/node_meta.json"))
    parser.add_argument("--interval", type=int, default=120)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    node_meta = wf_store.load_node_meta(args.dict)
    conn = wf_store.init_db(args.db)
    print("store=%s dict=%d nodes interval=%ds" % (args.db, len(node_meta), args.interval), flush=True)

    if args.once:
        return 0 if one_cycle(conn, node_meta, args.interval) else 1

    while not STOP:
        one_cycle(conn, node_meta, args.interval)
        # Align to the next interval boundary so rows land on round minutes.
        sleep_for = args.interval - (time.time() % args.interval)
        deadline = time.time() + sleep_for
        while not STOP and time.time() < deadline:
            time.sleep(min(1.0, max(0.0, deadline - time.time())))

    conn.close()
    print("stopped", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
