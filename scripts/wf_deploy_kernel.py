#!/usr/bin/env python3
"""把基于站点内核的伤害计算服务推到 VPS。

    set -a && . ./.env.local && set +a
    python scripts/wf_deploy_kernel.py

与旧版（engine.js + payload.json）的区别：计算不再是本项目写的公式，而是
warframe-damage.com 的 min.js 在 jsdom 里跑，所以要一并传 server/site/（站点
脚本 + 666 份武器数据 + 敌人数据），并在服务器上装 jsdom。

    上传    build/dps_bundle.tar.gz  → /tmp/，解到 /srv/wf-dps
    依赖    /srv/wf-dps/server 里 npm install --omit=dev
    服务    systemd wf-dps.service（127.0.0.1:8793）
    入口    nginx /dps/ 反代
"""

import os
import subprocess
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
BUNDLE = os.path.join(ROOT, "build", "dps_bundle.tar.gz")

PATHS = [
    "server/kernel.js",
    "server/api.js",
    "server/package.json",
    "server/package-lock.json",
    "server/site",
    "web/app",
]

UNIT_TMPL = """[Unit]
Description=Warframe damage calculator (site kernel in jsdom)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory={remote}
Environment=WF_DPS_PORT={port}
Environment=WF_DPS_WEB={remote}/web/app
Environment=NODE_OPTIONS=--max-old-space-size=320
ExecStart={node} {remote}/server/api.js
Restart=always
RestartSec=5
MemoryMax=560M
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
    proxy_read_timeout 60s;
    proxy_buffering off;
    client_max_body_size 256k;
}}
"""


def run(client, cmd, timeout=300, check=True):
    _, out, err = client.exec_command(cmd, timeout=timeout)
    o = out.read().decode("utf-8", "replace")
    e = err.read().decode("utf-8", "replace")
    code = out.channel.recv_exit_status()
    if check and code != 0:
        raise RuntimeError("%s\n-> %s\n%s" % (cmd, code, e.strip()))
    return o, e, code


def make_bundle():
    os.makedirs(os.path.dirname(BUNDLE), exist_ok=True)
    if os.path.exists(BUNDLE):
        os.remove(BUNDLE)
    cmd = ["tar", "-czf", BUNDLE] + PATHS
    subprocess.run(cmd, cwd=ROOT, check=True)
    return os.path.getsize(BUNDLE)


def main() -> int:
    if not HOST or not PASS:
        print("WF_VPS_HOST / WF_VPS_PASS must be set", file=sys.stderr)
        return 2

    web_only = "--web-only" in sys.argv
    size = make_bundle()
    print("bundle %.1f MB" % (size / 1048576))

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASS, timeout=30,
                   banner_timeout=30, auth_timeout=30,
                   look_for_keys=False, allow_agent=False)
    try:
        if web_only:
            sftp = client.open_sftp()
            try:
                for f in ("index.html", "app.css", "app.js"):
                    sftp.put(os.path.join(ROOT, "web/app", f), "%s/web/app/%s" % (REMOTE, f))
                    print("put web/app/" + f)
            finally:
                sftp.close()
            print("https /dps/:", run(client, "curl -s -o /dev/null -w '%{http_code} %{size_download}' "
                                              "https://data.ireescc.com/dps/app.js", check=False)[0].strip())
            return 0

        print("node:", run(client, "test -x %s && %s -v" % (NODE, NODE))[0].strip())
        run(client, "mkdir -p %s" % REMOTE)

        sftp = client.open_sftp()
        try:
            sftp.put(BUNDLE, "/tmp/dps_bundle.tar.gz")
        finally:
            sftp.close()
        print("uploaded")

        run(client, "rm -rf %s/server /tmp/wf-app && mkdir -p %s" % (REMOTE, REMOTE))
        run(client, "tar xzf /tmp/dps_bundle.tar.gz -C %s && ls %s/server" % (REMOTE, REMOTE))

        print("npm install …（首次较慢）")
        out, err, code = run(
            client,
            "cd %s/server && npm install --omit=dev --no-audit --no-fund 2>&1 | tail -5" % REMOTE,
            timeout=600,
        )
        print(out.strip())
        if code != 0:
            raise RuntimeError("npm install 失败:\n" + err.strip())

        sftp = client.open_sftp()
        try:
            with sftp.file("/tmp/wf-dps.service", "w") as fh:
                fh.write(UNIT_TMPL.format(remote=REMOTE, port=PORT, node=NODE))
            with sftp.file("/tmp/wf-dps.conf", "w") as fh:
                fh.write(NGINX.format(port=PORT))
        finally:
            sftp.close()

        run(client, "mv /tmp/wf-dps.service %s && chmod 644 %s" % (UNIT, UNIT))
        run(client, "mv /tmp/wf-dps.conf %s && chmod 644 %s" % (SNIPPET, SNIPPET))
        run(client, "systemctl daemon-reload && systemctl enable wf-dps")
        run(client, "systemctl restart wf-dps")
        run(client, "sleep 3; systemctl is-active wf-dps")

        out = run(client, "grep -c 'wf-dps.conf' %s || true" % SITE)[0]
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
        else:
            print("nginx include 已存在")
        run(client, "nginx -t")
        run(client, "systemctl reload nginx")

        # 自检：本地与公网各打一次
        run(client, "sleep 2")
        print("health:", run(client, "curl -s http://127.0.0.1:%d/api/health" % PORT, check=False)[0].strip())
        body = ('{"weapon":"Torid","enemy":"Heavy Gunner","level":100,'
                '"mods":{"0":"Serration","1":"Galvanized Chamber"},'
                '"custom":[{"k":"base","v":50}]}')
        out = run(client,
                  "curl -s -X POST http://127.0.0.1:%d/api/calc -H 'Content-Type: application/json' "
                  "-d '%s'" % (PORT, body), check=False)[0]
        print("calc:", out[:220])
        out = run(client, "curl -s -o /dev/null -w '%{http_code} %{size_download}' "
                          "https://data.ireescc.com/dps/", check=False)[0]
        print("https /dps/:", out.strip())
        out = run(client, "curl -s https://data.ireescc.com/dps/api/health", check=False)[0]
        print("https health:", out.strip())
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
