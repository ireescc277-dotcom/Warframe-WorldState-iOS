#!/usr/bin/env python3
"""把 AlecaFrame 的仲裁排程灌进历史库。

仲裁每小时换一次，88 个节点轮着来。靠我们自己的 120 秒轮询去攒样本，
单个节点要两三个月才站得住；而 AlecaFrame 的 `arbitrations/forecast.json`
直接带着 2024-10 起的完整排程（来源 browse.wf/arbys.txt），一年半的历史
可以一次性补上。

两个前提：
* 只导 `starts_at <= now` 的部分，未来的排程不是历史。
* 行标 `source='backfill'`。它的分母不是"我们开机了多久"，所以
  `target_stats` 对 arbitration 单独用回填区间的长度做曝光时长；
  裂隙、入侵这些仍然只用真实 poll 的时长。

    python3 wf_arb_backfill.py --forecast forecast.json --nodes node_meta.json
    python3 wf_arb_backfill.py --dry-run
"""
import argparse
import json
import os
import sys
import time

import wf_store

HOUR = 3600


def parse_schedule(path, until):
    with open(path, encoding="utf-8") as fh:
        payload = json.load(fh)
    raw = payload.get("schedule")
    if isinstance(raw, list):                     # 有的版本直接给数组
        pairs = []
        for item in raw:
            if isinstance(item, dict):
                pairs.append((item.get("ts") or item.get("start"), item.get("node")))
            elif isinstance(item, (list, tuple)) and len(item) >= 2:
                pairs.append((item[0], item[1]))
        entries = [(int(t), str(n)) for t, n in pairs if t and n]
    else:
        entries = []
        for line in (raw or "").splitlines():
            ts, _, node = line.strip().partition(",")
            if not ts or not node:
                continue
            try:
                entries.append((int(ts), node.strip()))
            except ValueError:
                continue
    entries.sort()
    kept = [(t, n) for t, n in entries if t <= until]
    return kept, len(entries)


def build_rows(entries, node_meta):
    rows, unmapped = [], {}
    for ts, node in entries:
        info = node_meta.get(node) or {}
        mode, planet = info.get("mode"), info.get("planet")
        if not (mode and planet):
            unmapped[node] = unmapped.get(node, 0) + 1
            continue
        rows.append({
            "key": "arbhist|%d" % ts,
            "kind": "arbitration",
            "target": "arb|%s|%s|%s" % (mode, planet, node),
            "node_id": node,
            "mode": mode,
            "era": None,
            "hard": 0,
            "planet": planet,
            "starts_at": ts,
            "ends_at": ts + HOUR,
            "first_seen": ts,
            "meta": None,
            "source": "backfill",
        })
    return rows, unmapped


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=os.environ.get("WF_DB", "/opt/wf-monitor/wf_history.db"))
    parser.add_argument("--forecast", default="/opt/wf-monitor/forecast.json")
    parser.add_argument("--nodes", default="/opt/wf-monitor/node_meta.json")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    now = int(time.time())
    entries, total = parse_schedule(args.forecast, now)
    node_meta = wf_store.load_node_meta(args.nodes)
    rows, unmapped = build_rows(entries, node_meta)

    print("排程 %d 行，其中历史 %d 行（%s → %s），可映射 %d 行"
          % (total, len(entries),
             time.strftime("%Y-%m-%d", time.gmtime(entries[0][0])) if entries else "-",
             time.strftime("%Y-%m-%d", time.gmtime(entries[-1][0])) if entries else "-",
             len(rows)))
    if unmapped:
        print("节点字典里查不到的：%s" % sorted(unmapped)[:10])
    if not rows:
        return 1
    if args.dry_run:
        print("dry-run，不写库")
        return 0

    conn = wf_store.init_db(args.db)
    changed = 0
    for i in range(0, len(rows), 2000):
        chunk = rows[i:i + 2000]
        changed += wf_store.write_rows(conn, chunk)
        conn.commit()
    total_rows = conn.execute(
        "SELECT COUNT(*) FROM occurrence WHERE source = 'backfill'").fetchone()[0]
    span = conn.execute(
        "SELECT MIN(starts_at), MAX(COALESCE(ends_at, starts_at))"
        " FROM occurrence WHERE source = 'backfill'").fetchone()
    print("写入完成：本次变动 %d，库内回填行 %d，覆盖 %.1f 天"
          % (changed, total_rows, ((span[1] - span[0]) / 86400) if span[0] else 0))
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
