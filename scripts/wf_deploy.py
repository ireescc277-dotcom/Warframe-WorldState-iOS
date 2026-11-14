#!/usr/bin/env python3
"""Deploy the world-state recorder to the VPS and (re)start its systemd unit.

Idempotent: uploads the current scripts, rewrites the unit file, reloads, and
restarts. Re-running after an edit is the normal way to ship a change.

    WF_VPS_HOST=1.2.3.4 WF_VPS_PASS=... python scripts/wf_deploy.py [--smoke-only]

The password is read from the environment and never written to disk or argv.
"""

import argparse
import json
import os
import stat
import sys

import paramiko

HOST = os.environ.get("WF_VPS_HOST", "")
USER = os.environ.get("WF_VPS_USER", "root")
PASS = os.environ.get("WF_VPS_PASS", "")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMOTE_DIR = "/opt/wf-monitor"
UNIT_PATH = "/etc/systemd/system/wf-recorder.service"
UNIT_NAME = "wf-recorder"

FILES = [
    ("scripts/wf_store.py", "wf_store.py", 0o644),
    ("scripts/wf_record.py", "wf_record.py", 0o644),
    ("scripts/wf_prob.py", "wf_prob.py", 0o644),
    ("scripts/wf_arb_backfill.py", "wf_arb_backfill.py", 0o644),
]

UNIT = """[Unit]
Description=Warframe world state recorder
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory={remote}
Environment=PYTHONUNBUFFERED=1
Environment=WF_DB={remote}/wf_history.db
Environment=WF_DICT={remote}/node_meta.json
{worldstate_env}ExecStart=/usr/bin/python3 {remote}/wf_record.py --interval 120
Restart=always
RestartSec=15
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
"""


def run(client, command, check=True):
    stdin, stdout, stderr = client.exec_command(command, timeout=120)
    stdin.close()
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if check and code != 0:
        raise RuntimeError("%s\n-> %s\n%s" % (command, code, err.strip()))
    return out, err, code


def build_node_meta():
    """nodeID -> {mode, planet}. The recorder needs it to build target paths."""
    with open(os.path.join(ROOT, "WarframeWatch/Resources/DefaultDict.json"), encoding="utf-8") as fh:
        payload = json.load(fh)
    meta = {}
    for node_id, info in (payload.get("nodes") or {}).items():
        if info.get("mt") or info.get("planet"):
            meta[node_id] = {"mode": info.get("mt"), "planet": info.get("planet")}
    return meta


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke-only", action="store_true", help="upload + one poll, do not touch systemd")
    args = parser.parse_args()

    if not HOST or not PASS:
        print("WF_VPS_HOST / WF_VPS_PASS must be set", file=sys.stderr)
        return 2

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASS, timeout=30,
                   banner_timeout=30, auth_timeout=30, look_for_keys=False, allow_agent=False)

    try:
        run(client, "mkdir -p %s" % REMOTE_DIR)

        sftp = client.open_sftp()
        try:
            for local, remote, mode in FILES:
                sftp.put(os.path.join(ROOT, local), "%s/%s" % (REMOTE_DIR, remote))
                sftp.chmod("%s/%s" % (REMOTE_DIR, remote), mode)
                print("put %s" % remote)

            meta = build_node_meta()
            text = json.dumps(meta, ensure_ascii=False, separators=(",", ":"))
            with sftp.file("%s/node_meta.json" % REMOTE_DIR, "w") as fh:
                fh.write(text)
            print("put node_meta.json (%d nodes)" % len(meta))
        finally:
            sftp.close()

        out, _, _ = run(client, "cd %s && python3 wf_record.py --once" % REMOTE_DIR, check=False)
        print(out.strip() or "(no output)")

        if args.smoke_only:
            out, _, _ = run(client, "ls -la %s" % REMOTE_DIR)
            print(out)
            return 0

        token = os.environ.get("WF_PUBLISH_TOKEN", "").strip()
        worldstate_env = (
            "Environment=WF_WORLDSTATE_OUT=/var/www/wf/%s/worldstate.json\n" % token
            if token
            else ""
        )

        sftp = client.open_sftp()
        try:
            with sftp.file("/tmp/wf-recorder.service", "w") as fh:
                fh.write(UNIT.format(remote=REMOTE_DIR, worldstate_env=worldstate_env))
            sftp.chmod("/tmp/wf-recorder.service", 0o644)
        finally:
            sftp.close()

        run(client, "mv /tmp/wf-recorder.service %s" % UNIT_PATH)
        run(client, "chmod 644 %s" % UNIT_PATH)
        run(client, "systemctl daemon-reload")
        run(client, "systemctl enable %s" % UNIT_NAME)
        run(client, "systemctl restart %s" % UNIT_NAME)
        out, _, _ = run(client, "sleep 3; systemctl is-active %s; systemctl show %s -p NRestarts --value" % (UNIT_NAME, UNIT_NAME))
        print("unit: %s" % out.strip().replace("\n", " restarts="))

        out, _, _ = run(
            client,
            "sqlite3 %s/wf_history.db \"select 'polls', count(*) from poll union all "
            "select 'occurrences', count(*) from occurrence union all "
            "select 'targets', count(distinct target) from occurrence;\"" % REMOTE_DIR,
            check=False,
        )
        print(out.strip() or "(sqlite3 missing, skipping counts)")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
