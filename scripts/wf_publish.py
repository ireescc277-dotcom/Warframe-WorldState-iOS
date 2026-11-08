#!/usr/bin/env python3
"""把背包快照推到 VPS，App 启动时从那里取。

账号数据不再跟着 IPA 走：仓库要公开，而这份 JSON 里有白金余额和每件
Prime 部件的持有数。真数据放在 VPS 的一个随机路径下，App 用 CI 写进
Info.plist 的地址去拉，拉不到就退回本机缓存。

    WF_VPS_HOST=... WF_VPS_PASS=... python scripts/wf_publish.py --token <32位random>

`--token` 就是路径本身，等于凭证；换掉它旧链接立刻失效。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import sys
import time
import urllib.request

import paramiko

HOST = os.environ.get("WF_VPS_HOST", "")
USER = os.environ.get("WF_VPS_USER", "root")
PASS = os.environ.get("WF_VPS_PASS", "")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAPSHOT = os.path.join(ROOT, "WarframeWatch", "Resources", "InventoryData.json")
REMOTE_ROOT = os.environ.get("WF_PUBLISH_ROOT", "/var/www/wf")

NGINX = """location /wf/ {{
    alias {root}/;
    autoindex off;
    add_header Cache-Control "no-store" always;
    default_type application/json;
}}"""


def run(client, command, check=True):
    _, stdout, stderr = client.exec_command(command, timeout=90)
    out = stdout.read().decode("utf-8", "replace").strip()
    err = stderr.read().decode("utf-8", "replace").strip()
    code = stdout.channel.recv_exit_status()
    if check and code != 0:
        raise RuntimeError(f"{command}\n-> {code}\n{err}")
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", default=os.environ.get("WF_PUBLISH_TOKEN", ""))
    parser.add_argument("--base-url", default=os.environ.get("WF_PUBLISH_BASE", ""),
                        help="用来回显最终链接，例如 http://113.20.2.21")
    parser.add_argument("--nginx", action="store_true", help="顺带写入 nginx location 并 reload")
    args = parser.parse_args()

    if not HOST or not PASS:
        print("WF_VPS_HOST / WF_VPS_PASS must be set", file=sys.stderr)
        return 2
    if not os.path.exists(SNAPSHOT):
        print("没有快照，先跑 build_app_inventory.py", file=sys.stderr)
        return 1

    token = args.token or secrets.token_hex(16)
    if len(token) < 16:
        print("token 太短，至少 16 位", file=sys.stderr)
        return 2

    remote_dir = f"{REMOTE_ROOT}/{token}"
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASS, timeout=30,
                   banner_timeout=30, auth_timeout=30,
                   look_for_keys=False, allow_agent=False)

    try:
        run(client, f"mkdir -p {remote_dir}")
        run(client, f"chmod 755 {REMOTE_ROOT} {remote_dir}")

        sftp = client.open_sftp()
        try:
            sftp.put(SNAPSHOT, f"{remote_dir}/inventory.json")
            # 同一个路径下也留一份按时间命名的，方便回溯是哪天推的
            stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
            sftp.put(SNAPSHOT, f"{remote_dir}/{stamp}.json")
            sftp.chmod(f"{remote_dir}/inventory.json", 0o644)
        finally:
            sftp.close()

        size = os.path.getsize(SNAPSHOT)
        digest = hashlib.sha256(open(SNAPSHOT, "rb").read()).hexdigest()[:12]
        run(client, f"chmod 644 {remote_dir}/*.json")

        if args.nginx:
            conf = NGINX.format(root=REMOTE_ROOT)
            script = (
                "python3 - <<'PY'\n"
                "import re\n"
                "path='/etc/nginx/sites-enabled/default'\n"
                "text=open(path).read()\n"
                f"block='''{conf}'''\n"
                "if '/wf/' not in text:\n"
                "    text=text.replace('server {', 'server {\\n' + block, 1)\n"
                "    open(path,'w').write(text)\n"
                "PY\n"
                "nginx -t && systemctl reload nginx"
            )
            out = run(client, script, check=False)
            print(out.strip() or "nginx reloaded")

        with open(SNAPSHOT, encoding="utf-8") as fh:
            doc = json.load(fh)
        print(f"推送 {size // 1024} KB · sha256:{digest} · 构建于 {doc.get('builtAt')}")
        print(f"远端 {remote_dir}/inventory.json")
        if args.base_url:
            print(f"地址 {args.base_url.rstrip('/')}/wf/{token}/inventory.json")
        else:
            print(f"地址 <base>/wf/{token}/inventory.json")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
