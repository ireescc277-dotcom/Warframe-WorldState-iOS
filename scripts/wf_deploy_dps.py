#!/usr/bin/env python3
"""把伤害计算后端 + 前端推到 VPS，并挂到 nginx 的 /dps/ 下。

    WF_VPS_HOST=... WF_VPS_PASS=... python scripts/wf_deploy_dps.py
    ... --payload-only     # 只换数据，不动服务与 nginx

布局（与仓库一致，省得两边路径分叉）：

    /srv/wf-dps/server/engine.js        计算内核
    /srv/wf-dps/server/api.js           HTTP 服务（127.0.0.1:8793）
    /srv/wf-dps/server/data/payload.json 数据
    /srv/wf-dps/web/app/*               前端静态文件

nginx 只做一件事：location /dps/ 反代到 8793，静态文件也由 Node 发，
省掉 alias 与 proxy 的路径对齐问题。
"""

import argparse
import os
import sys

import paramiko

HOST = os.environ.get("WF_VPS_HOST", "")
USER = os.environ.get("WF_VPS_USER", "root")
PASS = os.environ.get("WF_VPS_PASS", "")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMOTE = "/srv/wf-dps"
NODE = "/usr/local/bin/node"
PORT = 8793
UNIT = "/etc/systemd/system/wf-dps.service"
SNIPPET = "/etc/nginx/snippets/wf-dps.conf"
SITE = "/etc/nginx/sites-available/data.ireescc.com"
INCLUDE_AFTER = "include /etc/nginx/snippets/wf-inventory.conf;"

FILES = [
    ("server/engine.js", "server/engine.js", 0o644),
    ("server/api.js", "server/api.js", 0o644),
    ("server/data/payload.json", "server/data/payload.json", 0o644),
    ("web/app/index.html", "web/app/index.html", 0o644),
    ("web/app/app.css", "web/app/app.css", 0o644),
    ("web/app/app.js", "web/app/app.js", 0o644),
]

UNIT_TMPL = """[Unit]
Description=Warframe damage calculator (node)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory={remote}
Environment=WF_DPS_PORT={port}
Environment=WF_DPS_DATA={remote}/server/data/payload.json
Environment=WF_DPS_WEB={remote}/web/app
ExecStart={node} {remote}/server/api.js
Restart=always
RestartSec=5
MemoryMax=384M
Nice=5

[Install]
WantedBy=multi-user.target
"""

NGINX = """# 伤害计算：静态页和 /api 都走同一个 Node 进程，nginx 只做反代。
location = /dps {{ return 301 /dps/; }}
location /dps/ {{
    proxy_pass http://127.0.0.1:{port}/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Connection "";
    proxy_read_timeout 30s;
    proxy_buffering off;
    client_max_body_size 256k;
}}
"""


def run(client, cmd, check=True):
    _, out, err = client.exec_command(cmd, timeout=90)
    o = out.read().decode("utf-8", "replace")
    e = err.read().decode("utf-8", "replace")
    code = out.channel.recv_exit_status()
    if check and code != 0:
        raise RuntimeError("%s\n-> %s\n%s" % (cmd, code, e.strip()))
    return o, e, code


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--payload-only", action="store_true",
                    help="只重建并上传 payload.json，不动服务和 nginx")
    ap.add_argument("--no-build", action="store_true", help="跳过本地重建")
    ap.add_argument("--skip-nginx", action="store_true")
    args = ap.parse_args()
    if not HOST or not PASS:
        print("WF_VPS_HOST / WF_VPS_PASS must be set", file=sys.stderr)
        return 2

    if args.payload_only and not args.no_build:
        import subprocess
        print("重建 payload…")
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "build_dpsapp.py")],
                       check=True)

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASS, timeout=30,
                   banner_timeout=30, auth_timeout=30,
                   look_for_keys=False, allow_agent=False)
    try:
        out, _, _ = run(client, "test -x %s && %s -v" % (NODE, NODE), check=False)
        print("node:", out.strip() or "缺失")
        run(client, "mkdir -p %s/server/data %s/web/app" % (REMOTE, REMOTE))

        todo = [f for f in FILES if not args.payload_only or f[0].endswith("payload.json")]
        sftp = client.open_sftp()
        try:
            for local, remote, mode in todo:
                lpath = os.path.join(ROOT, local)
                rpath = "%s/%s" % (REMOTE, remote)
                sftp.put(lpath, rpath)
                sftp.chmod(rpath, mode)
                print("put %-28s %6.0f KB" % (remote, os.path.getsize(lpath) / 1024))
        finally:
            sftp.close()

        if args.payload_only:
            # 服务端按 mtime 自动重载，等一拍再查健康
            run(client, "sleep 2")
            out, _, _ = run(client, "curl -s http://127.0.0.1:%d/api/health" % PORT, check=False)
            print("health:", out.strip() or "(空)")
            return 0

        sftp = client.open_sftp()
        try:
            with sftp.file("/tmp/wf-dps.service", "w") as fh:
                fh.write(UNIT_TMPL.format(remote=REMOTE, port=PORT, node=NODE))
            with sftp.file("/tmp/wf-dps.conf", "w") as fh:
                fh.write(NGINX.format(port=PORT))
        finally:
            sftp.close()

        run(client, "mv /tmp/wf-dps.service %s && chmod 644 %s" % (UNIT, UNIT))
        run(client, "systemctl daemon-reload")
        run(client, "systemctl enable wf-dps")
        run(client, "systemctl restart wf-dps")
        run(client, "sleep 2; systemctl is-active wf-dps")

        if not args.skip_nginx:
            run(client, "mv /tmp/wf-dps.conf %s && chmod 644 %s" % (SNIPPET, SNIPPET))
            # 幂等：已经 include 过就不重复插
            out, _, _ = run(client, "grep -c 'wf-dps.conf' %s || true" % SITE)
            if out.strip() in ("", "0"):
                patch = (
                    "import shutil\n"
                    "p = %r\n"
                    "anchor = %r\n"
                    "line = '    include /etc/nginx/snippets/wf-dps.conf;\\n'\n"
                    "s = open(p).read()\n"
                    "if 'wf-dps.conf' not in s:\n"
                    "    shutil.copy(p, p + '.bak-dps')\n"
                    "    i = s.index(anchor) + len(anchor)\n"
                    "    s = s[:i] + '\\n' + line + s[i:]\n"
                    "    open(p, 'w').write(s)\n"
                    "    print('include 已插入')\n"
                    "else:\n"
                    "    print('已存在')\n"
                ) % (SITE, INCLUDE_AFTER)
                sftp = client.open_sftp()
                try:
                    with sftp.file("/tmp/wf_dps_patch.py", "w") as fh:
                        fh.write(patch)
                finally:
                    sftp.close()
                print(run(client, "python3 /tmp/wf_dps_patch.py && rm -f /tmp/wf_dps_patch.py")[0].strip())
            run(client, "nginx -t")
            run(client, "systemctl reload nginx")

        out, _, _ = run(client, "sleep 1; curl -s http://127.0.0.1:%d/api/health" % PORT, check=False)
        print("health:", out.strip() or "(空)")
        out, _, _ = run(client, "curl -s -o /dev/null -w '%{http_code} %{size_download}' "
                                "https://data.ireescc.com/dps/api/health", check=False)
        print("https /dps/api/health:", out.strip())
        out, _, _ = run(client, "curl -s -o /dev/null -w '%{http_code} %{size_download}' "
                                "https://data.ireescc.com/dps/", check=False)
        print("https /dps/:", out.strip())
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
