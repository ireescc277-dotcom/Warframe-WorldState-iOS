#!/usr/bin/env python3
"""把背包快照推到 VPS，App 启动时从那里取。

账号数据不再跟着 IPA 走：仓库要公开，而这份 JSON 里有白金余额和每件
Prime 部件的持有数。真数据放在 VPS 的一个随机路径下，App 用 CI 写进
Info.plist 的地址去拉，拉不到就退回本机缓存。

    WF_VPS_HOST=... WF_VPS_PASS=... python scripts/wf_publish.py --token <32位random>

`--token` 就是路径本身，等于凭证；换掉它旧链接立刻失效。

发布不是把新 JSON 直接覆盖给客户端：先上传并由 VPS 校验一个内容寻址的
payload，再原子替换很小的 `inventory.json` manifest。App 只相信 manifest
里的 snapshotId / sha256；因此它不可能把“刚刷新”的时间配到上一份内容上。
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import secrets
import shlex
import sys

import paramiko

HOST = os.environ.get("WF_VPS_HOST", "")
USER = os.environ.get("WF_VPS_USER", "root")
PASS = os.environ.get("WF_VPS_PASS", "")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAPSHOT = os.path.join(ROOT, "WarframeWatch", "Resources", "InventoryData.json")
INVENTORY_META = os.path.join(ROOT, "data", "inventory", "latest.meta.json")
RECEIPT = os.path.join(ROOT, "data", "inventory", "publish_receipt.json")
# 仲裁排程和背包放同一目录：App 由背包地址推出它的位置，不用多一个 secret。
SCHEDULE = os.path.join(ROOT, "data", "world", "arb.json")
REMOTE_ROOT = os.environ.get("WF_PUBLISH_ROOT", "/var/www/wf")

NGINX = """location /wf/ {{
    alias {root}/;
    autoindex off;
    default_type application/json;
    add_header Cache-Control "no-store" always;
    add_header X-Content-Type-Options nosniff;
    limit_except GET HEAD {{ deny all; }}
}}

# 安装包必须是二进制流：默认类型是 application/json，浏览器会把 .ipa
# 当文本渲染，点了没反应也存不下来。
location /wf/app/ {{
    alias {root}/app/;
    autoindex off;
    default_type application/octet-stream;
    add_header Cache-Control "no-store" always;
    add_header X-Content-Type-Options nosniff;
    add_header Content-Disposition "attachment";
    limit_except GET HEAD {{ deny all; }}
}}

# App 上传蹲守选择。服务器端监控按这份路径推送，否则两边各说各话。
# token 在路径里等于凭证；服务只监听 127.0.0.1，外面只能走这里。
location = /wf/{token}/watch {{
    proxy_pass http://127.0.0.1:8787/watch;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    client_max_body_size 64k;
    limit_except POST {{ deny all; }}
}}"""


def run(client, command, check=True):
    _, stdout, stderr = client.exec_command(command, timeout=90)
    out = stdout.read().decode("utf-8", "replace").strip()
    err = stderr.read().decode("utf-8", "replace").strip()
    code = stdout.channel.recv_exit_status()
    if check and code != 0:
        raise RuntimeError(f"{command}\n-> {code}\n{err}")
    return out


def atomic_local_json(path: str, payload: dict) -> None:
    """A completed receipt is always a whole receipt, never a half-written one."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def local_payload_metadata(path: str) -> tuple[dict, bytes, str]:
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        doc = json.loads(raw)
    except ValueError as exc:
        raise RuntimeError(f"快照 JSON 无效：{exc}") from exc
    if not isinstance(doc, dict):
        raise RuntimeError("快照 JSON 根节点不是对象")
    return doc, raw, hashlib.sha256(raw).hexdigest()


def captured_at_iso() -> str | None:
    """Aleca cache observation time for diagnostics, not for version identity."""
    try:
        with open(INVENTORY_META, encoding="utf-8") as fh:
            raw = json.load(fh).get("captured_at")
        if not isinstance(raw, str):
            return None
        return datetime.strptime(raw, "%Y%m%dT%H%M%SZ").replace(
            tzinfo=timezone.utc
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (OSError, ValueError, TypeError):
        return None


def manifest_for(doc: dict, *, digest: str, byte_count: int, published_at: str) -> dict:
    source = doc.get("source") if isinstance(doc.get("source"), dict) else {}
    manifest = {
        "schemaVersion": 2,
        # The complete content hash is both a dedupe key and the immutable
        # snapshot identity.  No wall-clock timestamp participates here.
        "snapshotId": digest,
        "contentHash": digest,
        "payload": f"snapshots/{digest}.json",
        "bytes": byte_count,
        "publishedAt": published_at,
    }
    if isinstance(source.get("accountHash"), str):
        manifest["sourceHash"] = source["accountHash"]
    if isinstance(source.get("accountSync"), str):
        manifest["sourceSync"] = source["accountSync"]
    if observed := captured_at_iso():
        manifest["sourceObservedAt"] = observed
    return manifest


def remote_json(sftp, path: str) -> dict | None:
    try:
        with sftp.open(path, "rb") as fh:
            parsed = json.loads(fh.read().decode("utf-8"))
        return parsed if isinstance(parsed, dict) else None
    except (OSError, ValueError, UnicodeDecodeError):
        return None


def put_then_rename(sftp, client, *, source: str | None = None,
                    raw: bytes | None = None, destination: str) -> None:
    """Upload beside the live file and publish it with one same-directory rename."""
    if (source is None) == (raw is None):
        raise ValueError("put_then_rename requires exactly one of source/raw")
    temporary = f"{destination}.tmp-{secrets.token_hex(8)}"
    try:
        if source is not None:
            sftp.put(source, temporary)
        else:
            with sftp.open(temporary, "wb") as fh:
                fh.write(raw or b"")
        sftp.chmod(temporary, 0o644)
        run(client, f"mv -f {shlex.quote(temporary)} {shlex.quote(destination)}")
    except Exception:
        try:
            sftp.remove(temporary)
        except OSError:
            pass
        raise


def remote_sha256(client, path: str) -> str:
    line = run(client, f"sha256sum {shlex.quote(path)}")
    digest = line.split(maxsplit=1)[0].lower()
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise RuntimeError(f"VPS 返回了无效 sha256：{line!r}")
    return digest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", default=os.environ.get("WF_PUBLISH_TOKEN", ""))
    parser.add_argument("--base-url", default=os.environ.get("WF_PUBLISH_BASE", ""),
                        help="用来回显最终链接，例如 https://example.com")
    parser.add_argument("--nginx", action="store_true", help="顺带写入 nginx location 并 reload")
    parser.add_argument("--dry-run", action="store_true",
                        help="只校验本地 payload 并打印计划，不连接 VPS")
    args = parser.parse_args(argv)

    if not os.path.exists(SNAPSHOT):
        print("没有快照，先跑 build_app_inventory.py", file=sys.stderr)
        return 1

    token = args.token or secrets.token_hex(16)
    if not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", token):
        print("token 只能含字母、数字、_、-，长度 16 到 128", file=sys.stderr)
        return 2

    try:
        doc, raw, digest = local_payload_metadata(SNAPSHOT)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    size = len(raw)
    source = doc.get("source") if isinstance(doc.get("source"), dict) else {}

    if args.dry_run:
        planned = manifest_for(doc, digest=digest, byte_count=size,
                               published_at="<VPS 校验 payload 后写入>")
        print(json.dumps(planned, ensure_ascii=False, indent=2))
        return 0

    if not HOST or not PASS:
        print("WF_VPS_HOST / WF_VPS_PASS must be set", file=sys.stderr)
        return 2

    remote_dir = f"{REMOTE_ROOT}/{token}"
    remote_payload = f"{remote_dir}/snapshots/{digest}.json"
    remote_manifest = f"{remote_dir}/inventory.json"
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASS, timeout=30,
                   banner_timeout=30, auth_timeout=30,
                   look_for_keys=False, allow_agent=False)

    try:
        run(client, f"mkdir -p {shlex.quote(remote_dir + '/snapshots')}")
        run(client, f"chmod 755 {shlex.quote(REMOTE_ROOT)} {shlex.quote(remote_dir)} "
                    f"{shlex.quote(remote_dir + '/snapshots')}")

        sftp = client.open_sftp()
        try:
            # Public schedule data is independent.  A failure here is recorded
            # but never turns a valid account payload into a half-publication.
            if os.path.exists(SCHEDULE):
                try:
                    put_then_rename(sftp, client, source=SCHEDULE,
                                    destination=f"{remote_dir}/arb.json")
                except Exception as exc:                       # noqa: BLE001
                    print(f"仲裁排程未更新（不阻断背包发布）：{exc}", file=sys.stderr)

            current = remote_json(sftp, remote_manifest)
            if (isinstance(current, dict)
                    and current.get("schemaVersion") == 2
                    and current.get("contentHash") == digest):
                # A rewrite of AlecaFrame's file with identical decoded account
                # data must not move the App's displayed publication time.
                receipt = {
                    "schemaVersion": 1,
                    "status": "already-published",
                    "snapshotId": current.get("snapshotId"),
                    "contentHash": digest,
                    "sourceHash": source.get("accountHash"),
                    "publishedAt": current.get("publishedAt"),
                    "checkedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
                atomic_local_json(RECEIPT, receipt)
                print(f"内容未变，沿用快照 {digest[:12]} · 已发布 {current.get('publishedAt')}")
                return 0

            # Stage 1: upload an immutable payload.  Its name is the complete
            # hash, and the VPS calculates the same hash before any manifest is
            # allowed to point to it.
            put_then_rename(sftp, client, source=SNAPSHOT, destination=remote_payload)
            if sftp.stat(remote_payload).st_size != size:
                raise RuntimeError("VPS payload 字节数与本地不一致")
            remote_digest = remote_sha256(client, remote_payload)
            if remote_digest != digest:
                raise RuntimeError(
                    f"VPS payload sha256 不一致：本地 {digest[:12]}，远端 {remote_digest[:12]}"
                )

            # Stage 2: server time is sampled only after the bytes above passed
            # verification, then a same-directory rename switches the pointer.
            published_at = run(client, "date -u +%Y-%m-%dT%H:%M:%SZ")
            if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", published_at):
                raise RuntimeError(f"VPS 返回了无效发布时间：{published_at!r}")
            manifest = manifest_for(doc, digest=digest, byte_count=size,
                                    published_at=published_at)
            manifest_raw = json.dumps(manifest, ensure_ascii=False,
                                      separators=(",", ":"), sort_keys=True).encode("utf-8")
            put_then_rename(sftp, client, raw=manifest_raw, destination=remote_manifest)
            if remote_json(sftp, remote_manifest) != manifest:
                raise RuntimeError("VPS manifest 回读与刚验证的 payload 指针不一致")
        finally:
            sftp.close()

        receipt = {
            "schemaVersion": 1,
            "status": "published",
            "snapshotId": digest,
            "contentHash": digest,
            "sourceHash": source.get("accountHash"),
            "publishedAt": manifest["publishedAt"],
            "payloadBytes": size,
            "recordedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        atomic_local_json(RECEIPT, receipt)

        if args.nginx:
            conf = NGINX.format(root=REMOTE_ROOT, token=token)
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

        print(f"已发布 {size // 1024} KB · snapshot:{digest[:12]} · VPS {manifest['publishedAt']}")
        print(f"远端 manifest {remote_manifest}")
        print(f"远端 payload  {remote_payload}")
        if args.base_url:
            print(f"地址 {args.base_url.rstrip('/')}/wf/{token}/inventory.json")
            if os.path.exists(SCHEDULE):
                print(f"     {args.base_url.rstrip('/')}/wf/{token}/arb.json")
        else:
            print(f"地址 <base>/wf/{token}/inventory.json")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
