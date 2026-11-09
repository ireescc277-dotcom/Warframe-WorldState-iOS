#!/usr/bin/env python3
"""接收 App 上传的蹲守选择。

服务器端监控要按 App 里勾的目标推，否则两边各说各话：你在 App 里加了「安魂
裂隙」，VPS 还按自己那份 watch.json 推别的东西。

App 把 paths POST 过来，这里只改 watch.json 的 paths，推送通道的配置原样
保留。只监听回环，外部经 nginx 的 /wf/<token>/watch 反代进来——token 就是
凭证，和背包同一个目录，不额外发明一套鉴权。

    python3 wf_watch_api.py            # 监听 127.0.0.1:8792
    curl -X POST localhost:8787/watch -d '{"paths":["fis|VoidT5"]}'
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG = os.environ.get("WF_NOTIFY_CONFIG", "/opt/wf-monitor/watch.json")
MAX_BODY = 64 * 1024
MAX_PATHS = 300
MAX_PATH_LEN = 120

# App 能选的根只有这几个，别的字符串说明是脏数据或者有人在试探。
ROOTS = ("fis|", "arb|", "inv|", "storm|", "cycle|")


def load_config() -> dict:
    try:
        with open(CONFIG, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_config(payload: dict) -> None:
    tmp = CONFIG + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, CONFIG)


def clean_paths(raw) -> list[str]:
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, str):
            continue
        path = item.strip()
        if not path or len(path) > MAX_PATH_LEN or path in seen:
            continue
        if not path.startswith(ROOTS):
            continue
        seen.add(path)
        out.append(path)
        if len(out) >= MAX_PATHS:
            break
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "WFWatchAPI/1.0"

    def _reply(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:                       # noqa: N802 - BaseHTTPRequestHandler 约定
        if self.path == "/health":
            self._reply(200, {"ok": True})
        else:
            self._reply(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:                      # noqa: N802
        if self.path.rstrip("/") != "/watch":
            self._reply(404, {"ok": False, "error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            self._reply(413, {"ok": False, "error": "body size"})
            return

        raw = self.rfile.read(length)
        try:
            doc = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            self._reply(400, {"ok": False, "error": "bad json"})
            return
        # 没有 paths 字段就是探测请求，别当成「清空所有选择」处理。
        if not isinstance(doc, dict) or "paths" not in doc:
            self._reply(400, {"ok": False, "error": "missing paths"})
            return

        paths = clean_paths(doc.get("paths") if isinstance(doc, dict) else None)
        config = load_config()
        config["paths"] = paths
        config["updatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        config["updatedFrom"] = "app"
        try:
            save_config(config)
        except OSError as exc:
            self._reply(500, {"ok": False, "error": str(exc)})
            return
        self._reply(200, {"ok": True, "paths": len(paths)})

    def log_message(self, fmt: str, *args) -> None:
        stamp = datetime.now().strftime("%m-%d %H:%M:%S")
        sys.stderr.write(f"[{stamp}] {self.address_string()} {fmt % args}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8792)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"listening on http://{args.host}:{args.port}  config={CONFIG}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
