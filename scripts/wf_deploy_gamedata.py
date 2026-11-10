#!/usr/bin/env python3
"""把游戏数据爬虫装到 VPS 上，10 分钟看一次 DE 的导出索引。

只做三件事：传脚本、写 systemd service+timer、enable --now。
不动已有服务；重复执行就是覆盖同一个 unit 再 restart。

    python scripts/wf_deploy_gamedata.py
    python scripts/wf_deploy_gamedata.py --run-now
"""

from __future__ import annotations

import argparse
import os
import sys

import paramiko

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOST = os.environ.get("WF_VPS_HOST", "")
USER = os.environ.get("WF_VPS_USER", "root")
PASS = os.environ.get("WF_VPS_PASS", "")
TOKEN = os.environ.get("WF_PUBLISH_TOKEN", "")
PUBLISH_ROOT = os.environ.get("WF_PUBLISH_ROOT", "/var/www/wf")
REMOTE = "/opt/wf-monitor"

SERVICE = """[Unit]
Description=Warframe game data crawler (DE PublicExport)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory={remote}
Environment=PYTHONUNBUFFERED=1
Environment=WF_GAMEDATA_DATA={remote}/gamedata
Environment=WF_GAMEDATA_PUBLISH={publish}
ExecStart=/usr/bin/python3 {remote}/wf_gamedata.py once
Nice=15
TimeoutStartSec=600
"""

TIMER = """[Unit]
Description=Poll Warframe PublicExport index every 10 minutes

[Timer]
OnBootSec=90s
OnUnitActiveSec=10min
AccuracySec=30s
Persistent=true
Unit=wf-gamedata.service

[Install]
WantedBy=timers.target
"""


def run(client: paramiko.SSHClient, cmd: str, quiet: bool = False) -> tuple[int, str]:
    _stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
    out = stdout.read().decode("utf-8", "replace") + stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if not quiet and out.strip():
        print(out.rstrip())
    return code, out


def sftp_write(sftp: paramiko.SFTPClient, path: str, text: str) -> None:
    with sftp.file(path, "w") as fh:
        fh.write(text)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-now", action="store_true", help="装完立刻跑一次，不等定时器")
    args = ap.parse_args()
    if not HOST or not PASS or not TOKEN:
        print("需要 WF_VPS_HOST / WF_VPS_PASS / WF_PUBLISH_TOKEN", file=sys.stderr)
        return 2

    publish = f"{PUBLISH_ROOT}/{TOKEN}"
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, 22, USER, PASS, timeout=30)
    sftp = client.open_sftp()

    run(client, f"mkdir -p {REMOTE}/gamedata {publish}")
    local = os.path.join(ROOT, "scripts", "wf_gamedata.py")
    sftp.put(local, f"{REMOTE}/wf_gamedata.py")
    print(f"↑ wf_gamedata.py -> {REMOTE}")

    sftp_write(sftp, "/etc/systemd/system/wf-gamedata.service", SERVICE.format(remote=REMOTE, publish=publish))
    sftp_write(sftp, "/etc/systemd/system/wf-gamedata.timer", TIMER)
    sftp.close()

    run(client, "systemctl daemon-reload")
    run(client, "systemctl enable --now wf-gamedata.timer")
    if args.run_now:
        run(client, "systemctl start wf-gamedata.service")
    run(client, "systemctl list-timers wf-gamedata.timer --no-pager | head -3")
    run(client, f"ls -la {publish}")
    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
