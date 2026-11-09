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


def describe(row, nodes: dict) -> tuple[str, str]:
    """把一行 occurrence 变成推送的标题与正文。"""
    kind = row["kind"]
    node_id = row["node_id"] or ""
    info = nodes.get(node_id) or {}
    name = info.get("name") or node_id
    planet = info.get("planet") or row["planet"] or ""
    where = f"{name}（{planet}）" if planet and planet not in name else name
    ends = row["ends_at"] or 0
    now = time.time()
    left = fmt_left(ends - now) if ends else ""

    if kind == "fissure":
        era = ERA_ZH.get(row["era"] or "", row["era"] or "")
        diff = "钢铁" if row["hard"] else "普通"
        task = info.get("task") or ""
        title = f"{era}裂隙 · {diff}"
        if task:
            title += f" · {task}"
        body = f"{where}\n{left}" if left else where
        return title, body

    if kind == "invasion":
        reward = (row["target"] or "").split("|")[-1]
        title = f"入侵奖励：{INV_ZH.get(reward, reward)}"
        body = f"{where}\n{left}" if left else where
        return title, body

    if kind == "storm":
        era = ERA_ZH.get(row["era"] or "", row["era"] or "")
        title = f"{era}虚空风暴"
        body = f"{where}\n{left}" if left else where
        return title, body

    if kind == "arbitration":
        task = info.get("task") or ""
        title = f"仲裁 · {task}" if task else "仲裁"
        body = f"{where}（回填记录，非实时）"
        return title, body

    return "Warframe 提醒", f"{where} {row['target']}"


# MARK: - 推送通道


def push_bark(cfg: dict, title: str, body: str) -> bool:
    key = (cfg.get("key") or "").strip()
    if not key:
        return False
    server = (cfg.get("server") or "https://api.day.app").rstrip("/")
    level = cfg.get("level") or "timeSensitive"
    group = cfg.get("group") or "warframe"
    url = (
        f"{server}/{urllib.parse.quote(key)}/"
        f"{urllib.parse.quote(title)}/{urllib.parse.quote(body)}"
        f"?group={urllib.parse.quote(group)}&level={urllib.parse.quote(level)}"
        "&call=1"
    )
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            payload = json.loads(resp.read().decode("utf-8") or "{}")
        if payload.get("code") not in (200, None):
            log(f"× Bark 拒绝：{payload.get('message')}")
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


def push_all(channels: dict, title: str, body: str, row) -> bool:
    """任一通道成功就算送达，全部失败才算丢。"""
    sent = False
    if isinstance(channels.get("bark"), dict):
        sent = push_bark(channels["bark"], title, body) or sent
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
    delivered = 0
    highest = cursor

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

        title, body = describe(row, nodes)
        if dry_run:
            log(f"[dry] {title} / {body.replace(chr(10), ' · ')}  ← {path}")
            pushed[row["key"]] = now
            delivered += 1
            continue
        if push_all(channels, title, body, row):
            pushed[row["key"]] = now
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
