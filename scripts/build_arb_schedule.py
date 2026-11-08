#!/usr/bin/env python3
"""把仲裁排程切成 App 能直接用的未来窗口。

仲裁不是随机的：browse.wf 的 `arbys.txt` 是一张确定性的轮换表，每小时
一个节点，已经排到 2029 年。所以对仲裁算「24 小时内出现的概率」是降级，
真正该显示的是「下一场几点、哪个节点」。

这个脚本做两件事：
* 拉最新的排程（本地拿不到 AlecaFrame 缓存时也能跑，直接问 browse.wf）
* 按 App 建树时用的同一份白名单过滤节点，只留下界面上点得到的

    python scripts/build_arb_schedule.py --days 30
    python scripts/build_arb_schedule.py --source local --check

输出 `data/world/arb.json`，由 `wf_publish.py` 推到 VPS 的背包同一目录。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DICT = os.path.join(ROOT, "WarframeWatch", "Resources", "DefaultDict.json")
OUT = os.path.join(ROOT, "data", "world", "arb.json")

REMOTE = "https://browse.wf/arbys.txt"
UA = "WarframeWatch/1.3 (+https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS)"
HOUR = 3600

# 与 WatchTree.swift 的 arbitrationModeKeys 保持一致：仲裁只跑无尽任务。
MODES = {
    "MT_SURVIVAL", "MT_DEFENSE", "MT_TERRITORY", "MT_EXCAVATE", "MT_ARTIFACT",
    "MT_EVACUATION", "MT_PURIFY", "MT_MIRROR_DEFENSE", "MT_CORRUPTION",
    "MT_VOID_CASCADE", "MT_VOID_ARMAGEDDON", "MT_ALCHEMY",
}


def local_forecast() -> str | None:
    base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~/AppData/Local")
    path = os.path.join(base, "AlecaFrame", "arbitrations", "forecast.json")
    return path if os.path.exists(path) else None


def fetch_remote(timeout: int = 25) -> list[tuple[int, str]] | None:
    request = urllib.request.Request(REMOTE, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                return None
            text = response.read().decode("utf-8", "replace")
    except Exception as exc:                        # 网络问题不该让整条链路停
        print("browse.wf 拉取失败：%s" % exc, file=sys.stderr)
        return None
    return parse(text)


def parse(text: str) -> list[tuple[int, str]]:
    rows: list[tuple[int, str]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        ts, _, node = line.partition(",")
        try:
            rows.append((int(ts), node.strip()))
        except ValueError:
            continue
    rows.sort()
    return rows


def load_local(path: str) -> list[tuple[int, str]]:
    with open(path, encoding="utf-8") as fh:
        payload = json.load(fh)
    raw = payload.get("schedule")
    if isinstance(raw, list):
        pairs = [(item.get("ts"), item.get("node")) for item in raw if isinstance(item, dict)]
        return sorted((int(t), str(n)) for t, n in pairs if t and n)
    return parse(raw or "")


def load_nodes() -> tuple[set[str], dict[str, str]]:
    """返回 App 界面里存在的仲裁节点，以及 node -> mode 的映射。"""
    with open(DICT, encoding="utf-8") as fh:
        nodes = json.load(fh)["nodes"]
    keep: dict[str, str] = {}
    for node_id, info in nodes.items():
        mode = info.get("mt")
        if mode not in MODES:
            continue
        if not info.get("planet"):
            continue
        if node_id.startswith("CrewBattleNode"):    # 空战节点不进仲裁树
            continue
        keep[node_id] = mode
    return set(keep), keep


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=30, help="往后取多少天，默认 30")
    parser.add_argument("--out", default=OUT)
    parser.add_argument("--source", choices=["auto", "remote", "local"], default="auto")
    parser.add_argument("--forecast", default=None, help="AlecaFrame 的 forecast.json 路径")
    parser.add_argument("--check", action="store_true", help="只打印覆盖率，不写文件")
    args = parser.parse_args()

    now = int(time.time())
    rows: list[tuple[int, str]] | None = None

    if args.source in ("auto", "remote"):
        rows = fetch_remote()
        if rows:
            source = "browse.wf"
    if not rows and args.source in ("auto", "local"):
        path = args.forecast or local_forecast()
        if path:
            rows = load_local(path)
            source = "local:" + os.path.basename(path)
    if not rows:
        print("没有可用的排程来源", file=sys.stderr)
        return 1

    keep, modes = load_nodes()

    # 从上一整点开始，App 才有「当前场次」可算
    start = (now // HOUR) * HOUR - HOUR
    end = now + args.days * 86400
    window = [(t, n) for t, n in rows if start <= t <= end]

    kept = [(t, n) for t, n in window if n in keep]
    dropped = sorted({n for _, n in window} - keep)

    slots = [{"t": t, "n": n} for t, n in kept]
    doc = {
        "builtAt": now,
        "slot": HOUR,
        "source": source,
        "days": args.days,
        "slots": slots,
    }

    by_node: dict[str, int] = {}
    for _, n in kept:
        by_node[n] = by_node.get(n, 0) + 1

    print(
        "%s · %d 条 · %d 个节点 · %.1f 天（%s → %s）"
        % (
            source,
            len(slots),
            len(by_node),
            (kept[-1][0] - kept[0][0]) / 86400 if kept else 0,
            time.strftime("%m-%d %H:%M", time.gmtime(kept[0][0])) if kept else "-",
            time.strftime("%m-%d %H:%M", time.gmtime(kept[-1][0])) if kept else "-",
        )
    )
    if dropped:
        print("  %d 个节点不在仲裁树里，已丢弃：%s" % (len(dropped), ", ".join(dropped[:6])))
    if by_node:
        low = min(by_node.items(), key=lambda kv: kv[1])
        print("  每个节点 %d–%d 次；最少的是 %s" % (low[1], max(by_node.values()), low[0]))

    if args.check:
        return 0

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(args.out)
    print("  → %s（%d KB）" % (os.path.relpath(args.out, ROOT), max(size // 1024, 1)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
