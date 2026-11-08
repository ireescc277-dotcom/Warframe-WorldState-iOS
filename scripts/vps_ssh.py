#!/usr/bin/env python3
"""Run a shell command on the VPS over SSH (password auth, no sshpass needed).

Credentials come from the environment, never from this file:

    WF_VPS_HOST=1.2.3.4 WF_VPS_USER=root WF_VPS_PASS=... \\
        python scripts/vps_ssh.py "uname -a"

Keeping the password out of argv/files means it cannot leak through shell
history, `ps`, or a committed config.
"""

import os
import sys

import paramiko

HOST = os.environ.get("WF_VPS_HOST", "")
USER = os.environ.get("WF_VPS_USER", "root")
PASS = os.environ.get("WF_VPS_PASS", "")
TIMEOUT = int(os.environ.get("WF_VPS_TIMEOUT", "30"))


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: vps_ssh.py <command>", file=sys.stderr)
        return 2
    if not HOST or not PASS:
        print("WF_VPS_HOST / WF_VPS_PASS must be set", file=sys.stderr)
        return 2

    command = " ".join(sys.argv[1:])
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        HOST,
        port=int(os.environ.get("WF_VPS_PORT", "22")),
        username=USER,
        password=PASS,
        timeout=TIMEOUT,
        banner_timeout=TIMEOUT,
        auth_timeout=TIMEOUT,
        look_for_keys=False,
        allow_agent=False,
    )
    try:
        stdin, stdout, stderr = client.exec_command(command, timeout=TIMEOUT * 4)
        stdin.close()
        out = stdout.read().decode("utf-8", "replace")
        err = stderr.read().decode("utf-8", "replace")
        code = stdout.channel.recv_exit_status()
    finally:
        client.close()

    if out:
        sys.stdout.write(out)
    if err.strip():
        sys.stderr.write("\n[stderr]\n" + err)
    return code


if __name__ == "__main__":
    sys.exit(main())
