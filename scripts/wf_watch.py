#!/usr/bin/env python3
"""盯住 AlecaFrame 的 lastData.dat，一变就把新背包推到 VPS。

链路和手工跑完全一样，只是把「什么时候跑」交给文件时间戳：

    lastData.dat 变化
        → wf_inventory.py read            解密 + 快照
        → build_inventory_view.py         生成 view.json / view.html
        → build_app_inventory.py          合并价格 → InventoryData.json
        → wf_publish.py                   上传到 /var/www/wf/<token>/

AlecaFrame 每几十秒就会重写一次这个文件，写到一半被读到就会解密失败。
所以这里不直接在变化瞬间动手：先要求 (mtime, size) 连续两次采样一致，
再交给下游（wf_inventory 自己还有 4 次重试兜底）。

价格不跟着每次背包变化重抓——那会把 835 个请求变成刷屏。默认每 12 小时
补一次缺价，其中每 24 小时全量重抓一次（835 件约 8 分钟），`--market-every 0` 关掉价格这条线。

用法：
    python scripts/wf_watch.py                   # 常驻，10 秒轮询
    python scripts/wf_watch.py --once            # 立即同步一次然后退出
    python scripts/wf_watch.py --no-publish      # 只更新本地
    python scripts/wf_watch.py --interval 30     # 改轮询间隔

发布需要环境变量 WF_VPS_HOST / WF_VPS_PASS 与 WF_PUBLISH_TOKEN
（三个都可以写在 .env.local 里，本脚本会读）。
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
DATA = os.path.join(ROOT, "data")
STATE = os.path.join(DATA, "watch_state.json")
LOG = os.path.join(DATA, "watch.log")

DEFAULT_DAT = os.path.join(os.environ.get("LOCALAPPDATA", ""), "AlecaFrame", "lastData.dat")


def log(msg: str) -> None:
    line = f"[{datetime.now().strftime('%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    os.makedirs(DATA, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def load_env() -> None:
    """`.env.local` 只在本机存在（已 gitignore），省得每次手打三个变量。"""
    path = os.path.join(ROOT, ".env.local")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key, val = key.strip(), val.strip().strip("'\"")
            if key and key not in os.environ:
                os.environ[key] = val


LOCK = os.path.join(DATA, "watch.lock")


def acquire_lock():
    """单实例。开机自启和手动双击同时发生的话，两个进程会重复推同一条。

    Windows 用 msvcrt 的字节锁，POSIX 用 fcntl；锁随进程退出自动释放，
    所以不需要清理陈旧的 pid 文件。
    """
    os.makedirs(DATA, exist_ok=True)
    handle = open(LOCK, "w")
    try:
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def fingerprint(path: str) -> tuple[int, int]:
    st = os.stat(path)
    return int(st.st_mtime), st.st_size


def run(script: str, args: list[str] | None = None) -> bool:
    cmd = [sys.executable, os.path.join(SCRIPTS, script), *(args or [])]
    started = time.time()
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                          errors="replace")
    tail = (proc.stdout or "").strip().splitlines()[-1:] or ["(无输出)"]
    if proc.returncode != 0:
        err = (proc.stderr or "").strip().splitlines()[-2:]
        log(f"× {script} 退出 {proc.returncode}：{' / '.join(err) or tail[0]}")
        return False
    log(f"√ {script} {time.time()-started:.0f}s · {tail[0][:90]}")
    return True


def read_state() -> dict:
    if not os.path.exists(STATE):
        return {}
    try:
        with open(STATE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def write_state(state: dict) -> None:
    os.makedirs(DATA, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    os.replace(tmp, STATE)


def sync(dat: str, publish: bool) -> bool:
    """走完整条链路。任一步失败就停在原地，不把半成品推上线。"""
    if not run("wf_inventory.py", ["--dat", dat, "read"]):
        return False
    if not run("build_inventory_view.py"):
        return False
    if not run("build_app_inventory.py"):
        return False
    if not publish:
        log("跳过发布（--no-publish）")
        return True
    # 排程和背包分两条线：抓不到 browse.wf 就沿用上一份，不阻断发布。
    # 6 小时以内不重复拉，排程一天只变一次。
    run("build_arb_schedule.py", ["--days", "30", "--max-age", "6"])
    if not (os.environ.get("WF_VPS_HOST") and os.environ.get("WF_VPS_PASS")):
        log("× 没有 WF_VPS_HOST / WF_VPS_PASS，无法发布")
        return False
    args = []
    token = os.environ.get("WF_PUBLISH_TOKEN")
    base = os.environ.get("WF_PUBLISH_BASE")
    if token:
        args += ["--token", token]
    if base:
        args += ["--base-url", base]
    if not run("wf_publish.py", args):
        return False
    return True


def maybe_market(state: dict) -> bool:
    """价格单独一条低频线。

    以前只补缺，等于新装备有价、老装备的价格永远停在第一次抓到的那天。
    现在改成两档：每天全量重抓一次（835 件约 8 分钟），中间每 12 小时只补缺。
    全量期间轮询会停一会儿，但背包文件不变，回来补扫就是。
    """
    every = int(state.get("marketEvery") or 0)
    if every <= 0:
        return False
    now = time.time()
    last = float(state.get("marketTs") or 0)
    if now - last < every * 3600:
        return False

    refresh = float(state.get("marketRefreshHours") or 24) * 3600
    full_due = now - float(state.get("marketFull") or 0) >= refresh
    if full_due:
        log("全量刷价（835 件，约 8 分钟）")
        if not run("wf_market.py", ["sync"]):
            return False
        state["marketFull"] = now
    else:
        log("补缺价")
        if not run("wf_market.py", ["sync", "--missing"]):
            return False
    state["marketTs"] = now
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dat", default=DEFAULT_DAT)
    parser.add_argument("--interval", type=float, default=10.0, help="轮询间隔秒")
    parser.add_argument("--once", action="store_true", help="立即同步一次然后退出")
    parser.add_argument("--no-publish", action="store_true")
    parser.add_argument("--market-every", type=float, default=12.0,
                        help="每 N 小时检查一次价格，0 关闭")
    parser.add_argument("--market-refresh", type=float, default=24.0,
                        help="每 N 小时全量重抓一次（默认 24，其余时候只补缺）")
    parser.add_argument("--force", action="store_true", help="忽略上次记录的时间戳")
    args = parser.parse_args(argv)

    load_env()
    if not os.path.exists(args.dat):
        log(f"× 找不到 {args.dat}，AlecaFrame 没装或还没同步过")
        return 2

    lock = acquire_lock()
    if lock is None:
        log("已有实例在跑，这个进程退出")
        return 0

    state = read_state()
    state["marketEvery"] = args.market_every
    state["marketRefreshHours"] = args.market_refresh

    if args.once:
        fp = fingerprint(args.dat)
        state.update(datTs=fp[0], datSize=fp[1])
        # 先刷价再构建：反过来的话新价格进不了 InventoryData.json。
        maybe_market(state)
        ok = sync(args.dat, not args.no_publish)
        write_state(state)
        return 0 if ok else 1

    log(f"开始监听 {args.dat}（每 {args.interval:.0f}s 检查）")
    last_seen = (0, 0) if args.force else (
        int(state.get("datTs") or 0), int(state.get("datSize") or 0))
    if last_seen == (0, 0):
        log("没有历史记录，先同步一次当前文件")
        ok = sync(args.dat, not args.no_publish)
        if ok:
            fp = fingerprint(args.dat)
            last_seen = fp
            state.update(datTs=fp[0], datSize=fp[1])
    maybe_market(state)
    write_state(state)

    pending: tuple[int, int] | None = None       # 上一次采样，用于判断是否稳定
    try:
        while True:
            time.sleep(args.interval)
            # 价格有更新就跟一次完整发布，否则新价要等下次背包变化才上线。
            if maybe_market(state):
                if sync(args.dat, not args.no_publish):
                    fp = fingerprint(args.dat)
                    last_seen = fp
                    state.update(datTs=fp[0], datSize=fp[1])
                write_state(state)
            try:
                fp = fingerprint(args.dat)
            except FileNotFoundError:
                continue
            if fp == last_seen:
                pending = None
                continue
            if fp != pending:
                # 还在写：记下来，下一轮再确认
                pending = fp
                continue
            pending = None
            log(f"检测到更新 size={fp[1]}，开始同步")
            if sync(args.dat, not args.no_publish):
                last_seen = fp
                state.update(datTs=fp[0], datSize=fp[1])
                maybe_market(state)
                write_state(state)
            else:
                log("同步失败，等下次文件变化再试")
    except KeyboardInterrupt:
        log("停止监听")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
