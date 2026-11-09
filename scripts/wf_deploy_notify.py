#!/usr/bin/env python3
"""把服务端蹲守进程部署到 VPS。

做四件事，都不碰已有服务：

1. 上传 wf_notify.py 和 nodes_zh.json（节点中文名，推送文案用）
2. 首次部署时写一份 watch.json 模板，**已存在就不覆盖**，免得冲掉手改的路径
3. 装 systemd unit 并 enable --now
4. 打印状态和最近日志

    python scripts/wf_deploy_notify.py
    python scripts/wf_deploy_notify.py --restart-only
"""

from __future__ import annotations

import argparse
import os
import sys

import paramiko

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

UNIT = """[Unit]
Description=Warframe watch notifier (server-side push)
After=network-online.target wf-recorder.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/wf-monitor
Environment=PYTHONUNBUFFERED=1
Environment=WF_DB=/opt/wf-monitor/wf_history.db
Environment=WF_NOTIFY_CONFIG=/opt/wf-monitor/watch.json
Environment=WF_NOTIFY_STATE=/opt/wf-monitor/notify_state.json
Environment=WF_NODES=/opt/wf-monitor/nodes_zh.json
ExecStart=/usr/bin/python3 /opt/wf-monitor/wf_notify.py --interval 30
Restart=always
RestartSec=10
Nice=15

[Install]
WantedBy=multi-user.target
"""

WATCH_TEMPLATE = """{
  "paths": [
    "fis|VoidT5",
    "fis|VoidT4|sp",
    "inv|potato",
    "inv|weapon"
  ],
  "catchUpSeconds": 3600,
  "channels": {
    "bark": {
      "key": "",
      "server": "https://api.day.app",
      "level": "timeSensitive",
      "group": "warframe"
    },
    "ntfy": {
      "server": "https://ntfy.sh",
      "topic": "wf-315122kdoziq",
      "priority": 4
    }
  }
}
"""

API_UNIT = """[Unit]
Description=Warframe watch-selection receiver (App -> VPS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/wf-monitor
Environment=PYTHONUNBUFFERED=1
Environment=WF_NOTIFY_CONFIG=/opt/wf-monitor/watch.json
ExecStart=/usr/bin/python3 /opt/wf-monitor/wf_watch_api.py --port 8792
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"""


def load_env() -> None:
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--restart-only", action="store_true")
    args = parser.parse_args()

    load_env()
    host = os.environ.get("WF_VPS_HOST")
    password = os.environ.get("WF_VPS_PASS")
    if not host or not password:
        print("WF_VPS_HOST / WF_VPS_PASS 未设置", file=sys.stderr)
        return 2

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, 22, os.environ.get("WF_VPS_USER", "root"), password,
                   timeout=30, look_for_keys=False, allow_agent=False)
    sftp = client.open_sftp()

    def put(local: str, remote: str) -> None:
        sftp.put(local, remote)
        print(f"· {local} -> {remote}")

    try:
        if not args.restart_only:
            put(os.path.join(ROOT, "scripts", "wf_notify.py"), "/opt/wf-monitor/wf_notify.py")
            put(os.path.join(ROOT, "scripts", "wf_watch_api.py"), "/opt/wf-monitor/wf_watch_api.py")
            put(os.path.join(ROOT, "data", "nodes_zh.json"), "/opt/wf-monitor/nodes_zh.json")

            try:
                sftp.stat("/opt/wf-monitor/watch.json")
                print("· watch.json 已存在，保留")
            except OSError:
                with sftp.file("/opt/wf-monitor/watch.json", "w") as fh:
                    fh.write(WATCH_TEMPLATE)
                print("· 写入 watch.json 模板（需要填推送 key）")

        # unit 先落到 /tmp 再 mv，避免 sftp 写到一半留下半个文件
        with sftp.file("/tmp/wf-notify.service", "w") as fh:
            fh.write(UNIT)
        with sftp.file("/tmp/wf-watch-api.service", "w") as fh:
            fh.write(API_UNIT)
        sftp.close()
        print("· unit 已上传")
    finally:
        client.close()

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, 22, os.environ.get("WF_VPS_USER", "root"), password,
                   timeout=30, look_for_keys=False, allow_agent=False)
    script = (
        "mv /tmp/wf-notify.service /etc/systemd/system/wf-notify.service && "
        "mv /tmp/wf-watch-api.service /etc/systemd/system/wf-watch-api.service && "
        "systemctl daemon-reload && "
        "systemctl enable --now wf-notify.service wf-watch-api.service >/dev/null 2>&1; "
        "systemctl restart wf-notify.service wf-watch-api.service; sleep 2; "
        "systemctl is-active wf-notify.service wf-watch-api.service; "
        "echo '--- notify ---'; journalctl -u wf-notify -n 6 --no-pager; "
        "echo '--- api ---'; journalctl -u wf-watch-api -n 6 --no-pager; "
        "echo '--- health ---'; curl -s -m 5 http://127.0.0.1:8792/health"
    )
    _, stdout, stderr = client.exec_command(script, timeout=90)
    print(stdout.read().decode("utf-8", "replace"))
    err = stderr.read().decode("utf-8", "replace").strip()
    if err:
        print(err, file=sys.stderr)
    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
