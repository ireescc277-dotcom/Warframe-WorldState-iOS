#!/usr/bin/env python3
"""盯住 AlecaFrame 的 lastData.dat，一变就把新背包推到 VPS。

链路和手工跑完全一样，只是把「什么时候跑」交给文件时间戳：

    lastData.dat 变化
        → wf_inventory.py read            解密 + 快照
        → build_inventory_view.py         生成 view.json / view.html
        → build_app_inventory.py          合并价格 → InventoryData.json
        → wf_publish.py                   验证 payload 后原子发布 manifest

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
import gzip
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
DATA = os.path.join(ROOT, "data")
INVENTORY = os.path.join(DATA, "inventory")
SNAPSHOT = os.path.join(INVENTORY, "latest.json.gz")
SNAPSHOT_META = os.path.join(INVENTORY, "latest.meta.json")
APP_PAYLOAD = os.path.join(ROOT, "WarframeWatch", "Resources", "InventoryData.json")
PUBLISH_RECEIPT = os.path.join(INVENTORY, "publish_receipt.json")
SYNC_RECEIPT = os.path.join(INVENTORY, "sync_receipt.json")
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
    # Windows 子进程默认按 GBK 往管道里写，这里强制它说 UTF-8；
    # 否则日志里的中文全是 ????。
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", env=env)
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


def read_json(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            parsed = json.load(fh)
        return parsed if isinstance(parsed, dict) else {}
    except (OSError, ValueError):
        return {}


def atomic_json_write(path: str, payload: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def sha256_file(path: str, *, gzip_payload: bool = False) -> str:
    """Hash what the next stage actually consumes, not mtime or gzip headers."""
    digest = hashlib.sha256()
    opener = gzip.open if gzip_payload else open
    with opener(path, "rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def iso_mtime(path: str) -> str | None:
    try:
        return datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
    except OSError:
        return None


def begin_receipt(dat: str) -> dict:
    try:
        byte_count = os.path.getsize(dat)
    except OSError:
        byte_count = None
    receipt = {
        "schemaVersion": 1,
        "startedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        # The watcher records a fingerprint only to detect writes.  Version
        # truth below is always a SHA-256 over parsed snapshot/payload bytes.
        "input": {"mtime": iso_mtime(dat), "bytes": byte_count},
        "stages": {},
    }
    atomic_json_write(SYNC_RECEIPT, receipt)
    return receipt


def record_stage(receipt: dict, name: str, *, ok: bool, **fields) -> None:
    receipt["stages"][name] = {
        "ok": ok,
        "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **fields,
    }
    atomic_json_write(SYNC_RECEIPT, receipt)


def sync(dat: str, publish: bool) -> bool:
    """Run one verifiable, version-linked account snapshot publication.

    `sync_receipt.json` deliberately contains hashes and stage times only.  It
    gives a future investigation a precise answer to “where did this version
    stop?” without copying raw inventory, credentials, or item instance IDs to
    logs.
    """
    receipt = begin_receipt(dat)
    if not run("wf_inventory.py", ["--dat", dat, "read"]):
        record_stage(receipt, "sourceRead", ok=False, error="wf_inventory.py failed")
        return False
    if not os.path.exists(SNAPSHOT):
        record_stage(receipt, "sourceRead", ok=False, error="latest.json.gz missing")
        return False
    try:
        source_hash = sha256_file(SNAPSHOT, gzip_payload=True)
    except (OSError, gzip.BadGzipFile) as exc:
        record_stage(receipt, "sourceRead", ok=False, error=f"snapshot hash failed: {exc}")
        return False
    source_meta = read_json(SNAPSHOT_META)
    record_stage(receipt, "sourceRead", ok=True, sourceHash=source_hash,
                 sourceObservedAt=iso_mtime(SNAPSHOT),
                 capturedAt=source_meta.get("captured_at"))

    if not run("build_inventory_view.py"):
        record_stage(receipt, "inventoryView", ok=False,
                     sourceHash=source_hash, error="build_inventory_view.py failed")
        return False
    record_stage(receipt, "inventoryView", ok=True, sourceHash=source_hash)

    if not run("build_app_inventory.py"):
        record_stage(receipt, "appPayload", ok=False,
                     sourceHash=source_hash, error="build_app_inventory.py failed")
        return False
    if not os.path.exists(APP_PAYLOAD):
        record_stage(receipt, "appPayload", ok=False,
                     sourceHash=source_hash, error="InventoryData.json missing")
        return False
    try:
        payload = read_json(APP_PAYLOAD)
        payload_hash = sha256_file(APP_PAYLOAD)
        payload_source_doc = payload.get("source")
        payload_source = payload_source_doc.get("accountHash") \
            if isinstance(payload_source_doc, dict) else None
    except OSError as exc:
        record_stage(receipt, "appPayload", ok=False,
                     sourceHash=source_hash, error=f"payload hash failed: {exc}")
        return False
    if payload_source != source_hash:
        # This is the invariant that the old builtAt scheme failed to prove.
        # Do not publish a perfectly valid JSON document if it describes a
        # different account snapshot than this watcher cycle just read.
        record_stage(receipt, "appPayload", ok=False, sourceHash=source_hash,
                     contentHash=payload_hash,
                     error="payload source hash does not match current snapshot")
        log("× InventoryData 的 sourceHash 和本轮背包快照不一致，拒绝发布")
        return False
    record_stage(receipt, "appPayload", ok=True, sourceHash=source_hash,
                 contentHash=payload_hash, bytes=os.path.getsize(APP_PAYLOAD))

    if not publish:
        log("跳过发布（--no-publish）")
        record_stage(receipt, "published", ok=True, skipped=True,
                     sourceHash=source_hash, contentHash=payload_hash)
        return True
    # 排程和背包分两条线：抓不到 browse.wf 就沿用上一份，不阻断发布。
    # 6 小时以内不重复拉，排程一天只变一次。
    run("build_arb_schedule.py", ["--days", "30", "--max-age", "6"])
    if not (os.environ.get("WF_VPS_HOST") and os.environ.get("WF_VPS_PASS")):
        log("× 没有 WF_VPS_HOST / WF_VPS_PASS，无法发布")
        record_stage(receipt, "published", ok=False, sourceHash=source_hash,
                     contentHash=payload_hash, error="VPS credentials unavailable")
        return False
    args = []
    token = os.environ.get("WF_PUBLISH_TOKEN")
    base = os.environ.get("WF_PUBLISH_BASE")
    if token:
        args += ["--token", token]
    if base:
        args += ["--base-url", base]
    if not run("wf_publish.py", args):
        record_stage(receipt, "published", ok=False, sourceHash=source_hash,
                     contentHash=payload_hash, error="wf_publish.py failed")
        return False
    publish_receipt = read_json(PUBLISH_RECEIPT)
    if (publish_receipt.get("contentHash") != payload_hash
            or publish_receipt.get("sourceHash") != source_hash):
        record_stage(receipt, "published", ok=False, sourceHash=source_hash,
                     contentHash=payload_hash,
                     error="publish receipt does not match this payload")
        log("× VPS 回执的 source/content hash 与本轮不一致，视为发布失败")
        return False
    record_stage(receipt, "published", ok=True, sourceHash=source_hash,
                 contentHash=payload_hash,
                 status=publish_receipt.get("status"),
                 snapshotId=publish_receipt.get("snapshotId"),
                 publishedAt=publish_receipt.get("publishedAt"))
    return True


def market_due(state: dict) -> tuple[bool, bool] | None:
    """该不该刷价；返回 (该刷, 是否全量)，不该刷返回 None。

    只看时间，不动 state —— 真正刷完由调用方写回去。这样刷价可以放到
    独立线程里跑，主线程照样盯背包文件。
    """
    every = int(state.get("marketEvery") or 0)
    if every <= 0:
        return None
    now = time.time()
    if now - float(state.get("marketTs") or 0) < every * 3600:
        return None
    refresh = float(state.get("marketRefreshHours") or 24) * 3600
    return True, (now - float(state.get("marketFull") or 0) >= refresh)


def run_market(full: bool) -> bool:
    log("全量刷价（835 件，约 8 分钟）" if full else "补缺价")
    return run("wf_market.py", ["sync"] if full else ["sync", "--missing"])


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
        due = market_due(state)
        if due and run_market(due[1]):
            now = time.time()
            state["marketTs"] = now
            if due[1]:
                state["marketFull"] = now
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
    # 刷价动辄十几分钟，放在主循环里会把「背包一变就同步」拖成十几分钟后。
    # 所以扔进线程，主线程只负责盯文件；刷完再回来重建一次发布。
    state_lock = threading.Lock()
    market_running = threading.Event()
    market_ready = threading.Event()

    def save_state() -> None:
        with state_lock:
            write_state(state)

    def refresh_market() -> None:
        try:
            due = market_due(state)
            if not due or not run_market(due[1]):
                return
            now = time.time()
            with state_lock:
                state["marketTs"] = now
                if due[1]:
                    state["marketFull"] = now
            market_ready.set()
        finally:
            market_running.clear()

    def kick_market() -> None:
        if market_running.is_set():
            return
        market_running.set()
        threading.Thread(target=refresh_market, daemon=True).start()

    kick_market()
    save_state()

    pending: tuple[int, int] | None = None       # 上一次采样，用于判断是否稳定
    try:
        while True:
            time.sleep(args.interval)
            # 价格刷完了：趁现在重建一次，否则新价要等下次背包变化才上线。
            if market_ready.is_set() and not market_running.is_set():
                market_ready.clear()
                log("价格已更新，重建并发布")
                if sync(args.dat, not args.no_publish):
                    fp = fingerprint(args.dat)
                    last_seen = fp
                    with state_lock:
                        state.update(datTs=fp[0], datSize=fp[1])
                save_state()
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
                with state_lock:
                    state.update(datTs=fp[0], datSize=fp[1])
                kick_market()
                save_state()
            else:
                log("同步失败，等下次文件变化再试")
    except KeyboardInterrupt:
        log("停止监听")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
