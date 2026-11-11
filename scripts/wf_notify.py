#!/usr/bin/env python3
"""服务端蹲守：补上本地通知做不到的那一半。

App 里的本地通知只能排「时间确定」的事件——仲裁有 browse.wf 排程，周期与
重置靠 worldState 的 expiry 反推。裂隙、入侵、虚空风暴没有排程，什么时候
冒出来没人知道；iOS 又不保证后台刷新，所以 App 不打开就等不到。

这个进程跑在 VPS 上，读 recorder 已经在写的同一个 SQLite 库，不额外请求
DE，也不会因为两次采集之间的时钟差漏掉一个只存在几分钟的场次。

    python3 wf_notify.py --once     # 扫一轮，用于调试
    python3 wf_notify.py            # 常驻

watch.json 里的 paths 与 App 蹲守树是同一套写法（见 WatchTree.swift）：

    fis|VoidT4|sp               后纪 · 钢铁之路 · 任意任务任意节点
    fis|VoidT5                  安魂裂隙
    fis|VoidT3|nm|MT_SURVIVAL   中纪 · 普通 · 生存
    inv|potato                  入侵奖励：土豆
    storm|VoidT4                后纪虚空风暴

前缀匹配，所以写得越短范围越大；路径之间是并集。

推送的粒度是「一次轮换」而不是「一个场次」。一次轮换会同时刷出 2–3 个裂隙，
逐个推等于同一句话连说三遍，所以同一批（first_seen 相差不到 batchSeconds）
合并成一条，正文列出这批的节点。`rules` 里可以调：

    "rules": {
      "batchSeconds": 180,                  // 同一批的时间窗
      "minRemainingRatio": 0.3,             // 只剩三成时间的场次不推（停机补捉）
      "quietHours": {"start": 1, "end": 8,  // 本地时间，服务器跑在 UTC
                     "utcOffset": 8, "mode": "passive"}
    }

`mode` 取 `passive`（照常进通知中心，不响铃）、`drop`（整段丢弃）或 `off`。
"""

from __future__ import annotations

import argparse
import json
import os
import smtplib
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from email.header import Header
from email.mime.text import MIMEText

DEFAULT_DB = os.environ.get("WF_DB", "/opt/wf-monitor/wf_history.db")
DEFAULT_CONFIG = os.environ.get("WF_NOTIFY_CONFIG", "/opt/wf-monitor/watch.json")
DEFAULT_STATE = os.environ.get("WF_NOTIFY_STATE", "/opt/wf-monitor/notify_state.json")
NODES = os.environ.get("WF_NODES", "/opt/wf-monitor/nodes_zh.json")

USER_AGENT = "WarframeWatch-notify/1.0"

ERA_ZH = {
    "VoidT1": "古纪", "VoidT2": "前纪", "VoidT3": "中纪",
    "VoidT4": "后纪", "VoidT5": "安魂", "VoidT6": "全能",
}

INV_ZH = {
    "catalyst": "奥罗金催化剂", "reactor": "奥罗金反应堆", "forma": "塑形块",
    "exilus_wf": "战甲特殊功能槽", "exilus_wp": "武器特殊功能槽",
    "karak_wraith": "卡拉卡·亡魂", "dera_vandal": "德拉·破坏者",
    "strun_wraith": "斯特朗·亡魂", "snipetron_vandal": "狙击特昂·破坏者",
    "latron_wraith": "拉特昂·亡魂", "twin_vipers_wraith": "双子蝰蛇·亡魂",
    "sheev": "希芙", "mutagen_mass": "突变原聚合物", "fieldron": "电磁力导管",
    "detonite": "爆燃喷射器", "riven_sliver": "裂罅碎石",
    "kavat_code": "库娃遗传密码", "nitain": "泥炭萃取物", "orokin_cell": "奥罗金电池",
}


def log(msg: str) -> None:
    stamp = datetime.now().strftime("%m-%d %H:%M:%S")
    print(f"[{stamp}] {msg}", flush=True)


# MARK: - 配置与状态


def load_json(path: str, default):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return default
    except (OSError, ValueError) as exc:
        log(f"× 读不了 {path}：{exc}")
        return default


def save_json(path: str, payload) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False)
    os.replace(tmp, path)


def load_nodes() -> dict:
    """nodeID -> {name, planet, task}，缺失就退化成用 nodeID。"""
    return load_json(NODES, {})


# MARK: - 匹配


def covered(target: str, paths: list[str]) -> str | None:
    """target 是否落在某条选中路径下。返回命中的那条，便于日志。"""
    for path in paths:
        if target == path or target.startswith(path + "|"):
            return path
    return None


def fmt_left(seconds: float) -> str:
    if seconds <= 0:
        return "即将结束"
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"剩余 {minutes} 分"
    hours, minutes = divmod(minutes, 60)
    if hours < 24:
        return f"剩余 {hours} 小时 {minutes} 分" if minutes else f"剩余 {hours} 小时"
    return f"剩余 {hours // 24} 天 {hours % 24} 小时"


def _place(row, nodes: dict) -> tuple[str, str]:
    node_id = row["node_id"] or ""
    info = nodes.get(node_id) or {}
    name = info.get("name") or node_id
    planet = info.get("planet") or row["planet"] or ""
    return name, planet


def describe(row, nodes: dict) -> tuple[str, str]:
    """把一行 occurrence 变成推送的标题与正文。"""
    return describe_batch([row], nodes)


def group_key(row):
    """哪些行算「同一件事」。

    裂隙按纪元 + 难度：一次轮换刷出的几个同纪元裂隙，对用户是同一件事。
    入侵按奖励：同一项奖励刷在三个节点上，也只需要说一次。
    """
    kind = row["kind"]
    if kind == "fissure":
        return (kind, row["era"] or "", int(row["hard"] or 0))
    if kind == "storm":
        return (kind, row["era"] or "")
    if kind == "invasion":
        return (kind, row["target"] or "")
    return (kind, row["key"])


def _remaining(rows) -> str:
    ends = [r["ends_at"] for r in rows if r["ends_at"]]
    if not ends:
        return ""
    return fmt_left(min(ends) - time.time())


def describe_batch(rows, nodes: dict) -> tuple[str, str]:
    """把同一批场次写成一条通知：标题说是什么，正文按星球列节点。"""
    rows = list(rows)
    first = rows[0]
    kind = first["kind"]
    count = len(rows)

    places: dict[str, list[str]] = {}
    for row in rows:
        name, planet = _place(row, nodes)
        places.setdefault(planet, []).append(name)

    lines: list[str] = []
    for planet in sorted(places):
        names = " / ".join(sorted(set(places[planet])))
        lines.append(f"{planet} · {names}" if planet else names)
    left = _remaining(rows)
    if left:
        lines.append(left)
    body = "\n".join(lines)

    if kind == "fissure":
        era = ERA_ZH.get(first["era"] or "", first["era"] or "")
        diff = "钢铁" if first["hard"] else "普通"
        tasks = {(nodes.get(r["node_id"] or "") or {}).get("task") or "" for r in rows}
        title = f"{era}裂隙 · {diff}"
        if len(tasks) == 1 and tasks != {""}:
            title += f" · {tasks.pop()}"
        if count > 1:
            title += f" · {count} 处"
        return title, body

    if kind == "invasion":
        reward = (first["target"] or "").split("|")[-1]
        title = f"入侵奖励：{INV_ZH.get(reward, reward)}"
        if count > 1:
            title += f" · {count} 处"
        return title, body

    if kind == "storm":
        era = ERA_ZH.get(first["era"] or "", first["era"] or "")
        title = f"{era}虚空风暴" + (f" · {count} 处" if count > 1 else "")
        return title, body

    if kind == "arbitration":
        task = (nodes.get(first["node_id"] or "") or {}).get("task") or ""
        return (f"仲裁 · {task}" if task else "仲裁"), f"{body}（回填记录，非实时）"

    return "Warframe 提醒", f"{body} {first['target']}"


# MARK: - 推送规则


def local_hour(offset: int) -> int:
    """服务器跑在 UTC，静默时段按人的作息算，所以要换算。"""
    return (datetime.now(timezone.utc).hour + offset) % 24


def quiet_mode(rules: dict) -> tuple[str | None, bool]:
    """返回 (Bark level 覆盖, 是否整条丢弃)。"""
    window = rules.get("quietHours")
    if not isinstance(window, dict):
        return None, False
    mode = (window.get("mode") or "passive").lower()
    if mode == "off":
        return None, False
    start = int(window.get("start", 1))
    end = int(window.get("end", 8))
    if start == end:
        return None, False
    hour = local_hour(int(window.get("utcOffset", 8)))
    inside = start <= hour < end if start < end else (hour >= start or hour < end)
    if not inside:
        return None, False
    return ("passive" if mode == "passive" else None), mode == "drop"


def worth_pushing(row, now: float, rules: dict) -> bool:
    """只剩三成时间的场次不推。

    这是给「服务停机后补捉」用的：重启时会把最近一小时的旧行捞出来，那些
    多半已经过半，推到手你也来不及了。
    """
    ratio = float(rules.get("minRemainingRatio") or 0.3)
    starts, ends = row["starts_at"], row["ends_at"]
    if not (starts and ends) or ends <= starts:
        return True
    return (ends - now) >= (ends - starts) * ratio


# MARK: - 推送通道


def push_bark(cfg: dict, title: str, body: str, level: str | None = None) -> bool:
    """Bark：POST /push 走 JSON。

    早先拼的是 `/key/标题/正文` 的路径式接口，中文标题一长就撞 URL 长度上限，
    而且 `call=1` 会一直响铃，不适合游戏提醒。改成 JSON 后正文原样过去，
    ttl 让过期的裂隙通知自己消失，不堆在通知中心里。

    `level` 是覆盖值，静默时段传 `passive`：照常进通知中心，不响铃不亮屏。
    """
    key = (cfg.get("key") or "").strip()
    if not key:
        return False
    server = (cfg.get("server") or "https://api.day.app").rstrip("/")
    payload = {
        "device_key": key,
        "title": title,
        "body": body,
        "group": cfg.get("group") or "warframe",
        "level": level or cfg.get("level") or "timeSensitive",
        "ttl": int(cfg.get("ttl") or 3600),
        "isArchive": 1,
    }
    if cfg.get("icon"):
        payload["icon"] = cfg["icon"]
    req = urllib.request.Request(
        server + "/push",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8", "User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            result = json.loads(resp.read().decode("utf-8") or "{}")
        if result.get("code") not in (200, None):
            log(f"× Bark 拒绝：{result.get('message')}")
            return False
        return True
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        log(f"× Bark 失败：{exc}")
        return False


def push_ntfy(cfg: dict, title: str, body: str) -> bool:
    server = (cfg.get("server") or "https://ntfy.sh").rstrip("/")
    topic = (cfg.get("topic") or "").strip()
    if not topic:
        return False
    # JSON publish：标题走 body 而不是 header，中文不会被代理截断。
    payload = json.dumps({
        "topic": topic,
        "title": title,
        "message": body,
        "priority": int(cfg.get("priority") or 4),
        "tags": cfg.get("tags") or ["video_game"],
    }, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        server + "/",
        data=payload,
        headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            resp.read()
        return True
    except (urllib.error.URLError, TimeoutError) as exc:
        log(f"× ntfy 失败：{exc}")
        return False


def push_webhook(cfg: dict, title: str, body: str, row) -> bool:
    url = (cfg.get("url") or "").strip()
    if not url:
        return False
    payload = json.dumps({
        "title": title, "body": body, "group": cfg.get("group") or "warframe",
        "kind": row["kind"], "target": row["target"], "node": row["node_id"],
    }, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url, data=payload,
        headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            resp.read()
        return True
    except (urllib.error.URLError, TimeoutError) as exc:
        log(f"× webhook 失败：{exc}")
        return False


def push_mail(cfg: dict, title: str, body: str) -> bool:
    host = cfg.get("host")
    user = cfg.get("user")
    password = cfg.get("password")
    to_addr = cfg.get("to") or user
    if not (host and user and password and to_addr):
        return False
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = Header(title, "utf-8")
    msg["From"] = user
    msg["To"] = to_addr
    try:
        port = int(cfg.get("port") or 465)
        if port == 465:
            server = smtplib.SMTP_SSL(host, port, timeout=15)
        else:
            server = smtplib.SMTP(host, port, timeout=15)
            server.starttls()
        server.login(user, password)
        server.sendmail(user, [to_addr], msg.as_string())
        server.quit()
        return True
    except Exception as exc:                       # noqa: BLE001 - 通道失败不该拖垮循环
        log(f"× 邮件失败：{exc}")
        return False


def push_all(channels: dict, title: str, body: str, row, level: str | None = None) -> bool:
    """任一通道成功就算送达，全部失败才算丢。"""
    sent = False
    if isinstance(channels.get("bark"), dict):
        sent = push_bark(channels["bark"], title, body, level) or sent
    if isinstance(channels.get("ntfy"), dict):
        sent = push_ntfy(channels["ntfy"], title, body) or sent
    if isinstance(channels.get("webhook"), dict):
        sent = push_webhook(channels["webhook"], title, body, row) or sent
    if isinstance(channels.get("mail"), dict):
        sent = push_mail(channels["mail"], title, body) or sent
    return sent


# MARK: - 主循环


def fetch_new(conn: sqlite3.Connection, cursor: int) -> list[sqlite3.Row]:
    """cursor 之后第一次出现的行。first_seen 是秒级整数，同一秒的多条一并取回，
    重复由 pushed 记账消掉。"""
    conn.row_factory = sqlite3.Row
    return conn.execute(
        """
        SELECT key, kind, target, node_id, mode, era, hard, planet,
               starts_at, ends_at, first_seen
          FROM occurrence
         WHERE first_seen >= ?
         ORDER BY first_seen
        """,
        (int(cursor),),
    ).fetchall()


def sweep(conn, config: dict, state: dict, nodes: dict, dry_run: bool = False) -> int:
    paths = [p for p in (config.get("paths") or []) if isinstance(p, str)]
    channels = config.get("channels") or {}
    rules = config.get("rules") if isinstance(config.get("rules"), dict) else {}
    # 没勾任何东西就不推。以前这里若退回到一份默认 paths，推的就是别人写的
    # 偏好，用户会以为自己关注了别的东西。
    if not paths:
        return 0

    now = int(time.time())
    # 服务停机期间攒下的老行不该补推：只认最近一小时新出现的。
    horizon = now - int(config.get("catchUpSeconds") or 3600)
    cursor = int(state.get("cursor") or now)
    if cursor < horizon:
        cursor = horizon

    rows = fetch_new(conn, cursor)
    pushed = state.get("pushed") or {}
    highest = cursor

    matched = []
    for row in rows:
        highest = max(highest, int(row["first_seen"]))
        target = row["target"] or ""
        path = covered(target, paths)
        if not path:
            continue
        if row["kind"] == "arbitration":
            # 仲裁是回填的历史记录，实时性由 App 的排程通知负责，这里不重复推。
            continue
        if row["key"] in pushed:
            continue
        if row["ends_at"] and row["ends_at"] < now:
            continue
        if int(row["first_seen"]) < horizon:
            continue
        if not worth_pushing(row, now, rules):
            pushed[row["key"]] = now
            continue
        matched.append((row, path))

    # 按「轮换」归并。一次轮换会同时刷出几个裂隙，逐个推等于同一句话连说
    # 三遍——用户看到的就是「一阵一阵地来」。
    bucket = max(30, int(rules.get("batchSeconds") or 180))
    batches: dict[tuple, list] = {}
    for row, path in matched:
        key = (group_key(row), int(row["first_seen"]) // bucket)
        batches.setdefault(key, []).append((row, path))

    level, drop = quiet_mode(rules)
    delivered = 0

    for key in sorted(batches, key=lambda k: min(int(r["first_seen"]) for r, _ in batches[k])):
        group = batches[key]
        batch_rows = [r for r, _ in group]
        title, body = describe_batch(batch_rows, nodes)

        if drop:
            for r, _ in group:
                pushed[r["key"]] = now
            log(f"· 静默时段跳过 {title} · {body.replace(chr(10), ' · ')}")
            continue

        if dry_run:
            log(f"[dry] {title} / {body.replace(chr(10), ' · ')}  ← {group[0][1]}")
            for r, _ in group:
                pushed[r["key"]] = now
            delivered += 1
            continue

        if push_all(channels, title, body, batch_rows[0], level):
            for r, _ in group:
                pushed[r["key"]] = now
            delivered += 1
            log(f"√ {title} · {body.replace(chr(10), ' · ')}")
        else:
            log(f"× 推送失败，留到下一轮重试：{title}")

    state["cursor"] = highest
    # 记账只留七天，够覆盖任何一场裂隙的完整生命周期。
    cutoff = now - 7 * 86400
    state["pushed"] = {k: v for k, v in pushed.items() if v >= cutoff}
    return delivered


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=DEFAULT_DB)
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument("--state", default=DEFAULT_STATE)
    parser.add_argument("--interval", type=int, default=30)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="只打印不推送")
    args = parser.parse_args(argv)

    config = load_json(args.config, {})
    if not config:
        log(f"× 没有配置：{args.config}")
        return 2
    state = load_json(args.state, {})
    if not state.get("cursor"):
        # 第一次跑不要回溯历史，从当下开始。
        state["cursor"] = int(time.time())
        log("首次运行，游标从当前时间开始")
    nodes = load_nodes()

    channels = config.get("channels") or {}
    enabled = [name for name, cfg in channels.items()
               if isinstance(cfg, dict) and (cfg.get("key") or cfg.get("topic")
                                             or cfg.get("url") or cfg.get("host"))]
    log(f"paths={len(config.get('paths') or [])} channels={enabled or '无'} "
        f"db={args.db}")

    conn = sqlite3.connect(args.db, timeout=10)
    try:
        if args.once:
            count = sweep(conn, config, state, nodes, dry_run=args.dry_run)
            save_json(args.state, state)
            log(f"本轮 {count} 条")
            return 0

        config_mtime = os.path.getmtime(args.config)
        while True:
            # App 改了蹲守选择会 POST 过来重写 watch.json；这里按 mtime 跟着换，
            # 不用重启服务。
            try:
                stamp = os.path.getmtime(args.config)
                if stamp != config_mtime:
                    fresh = load_json(args.config, config)
                    config, config_mtime = fresh, stamp
                    log(f"配置已更新 paths={len(config.get('paths') or [])}")
            except OSError:
                pass
            try:
                count = sweep(conn, config, state, nodes, dry_run=args.dry_run)
                # 没有命中也要推进游标，否则下次会把这一批重扫一遍。
                save_json(args.state, state)
                if count:
                    log(f"本轮推出 {count} 条")
            except sqlite3.Error as exc:
                log(f"× 读库失败：{exc}")
            time.sleep(max(5, args.interval))
    except KeyboardInterrupt:
        save_json(args.state, state)
        log("停止")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
