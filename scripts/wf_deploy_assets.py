#!/usr/bin/env python3
"""Deploy static Warframe artwork, icons, frames, and manifest to VPS (/var/www/wf-assets).

Serves under https://data.ireescc.com/wf-assets/ so the iOS app can download and
cache ~55 MB of artwork/icons on demand instead of bloating the IPA bundle.

Usage:
    python scripts/wf_deploy_assets.py          # diff sync via manifest.json (tarball if first time)
    python scripts/wf_deploy_assets.py --full   # force full tarball upload & atomic swap
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
import pathlib
import posixpath
import sys
import tarfile
import tempfile

import paramiko

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS_DIR = ROOT / "assets"
REMOTE_ROOT = os.environ.get("WF_ASSETS_ROOT", "/var/www/wf-assets")
SITE = "/etc/nginx/sites-available/data.ireescc.com"
SNIPPET = "/etc/nginx/snippets/wf-assets.conf"
INCLUDE_AFTER = "include /etc/nginx/snippets/wf-dps.conf;"

ASSET_CATEGORIES: list[tuple[str, str, tuple[str, ...]]] = [
    ("icons", "weapon-icons", (".webp",)),
    ("mod-icons", "mod-icons", (".webp",)),
    ("mod-art", "mod-art", (".webp",)),
    ("arcane-icons", "arcane-icons", (".webp",)),
    ("extra-icons", "extra-icons", (".webp", ".json")),
    ("mod-frames", "mod-frames", (".png",)),
    ("polarities", "polarities", (".png",)),
]

NGINX_CONF = """# Static Warframe artwork/icons/frames downloaded by the iOS app on demand.
location = /wf-assets/manifest.json {
    alias {root}/manifest.json;
    default_type application/json;
    add_header Cache-Control "no-cache" always;
    add_header X-Content-Type-Options nosniff;
    limit_except GET HEAD { deny all; }
}

location /wf-assets/ {
    alias {root}/;
    autoindex off;
    add_header Cache-Control "public, max-age=86400";
    add_header X-Content-Type-Options nosniff;
    limit_except GET HEAD { deny all; }
}
"""


def load_env_local() -> None:
    env_path = ROOT / ".env.local"
    if not env_path.exists():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip("\"'"))


def sha256_short(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:16]


def collect_local_assets() -> tuple[dict[str, tuple[pathlib.Path, int, str]], dict]:
    files: dict[str, tuple[pathlib.Path, int, str]] = {}
    entries = []
    total_bytes = 0
    version_hasher = hashlib.sha256()

    for remote_dir, local_dir, exts in ASSET_CATEGORIES:
        src_dir = ASSETS_DIR / local_dir
        if not src_dir.exists():
            continue
        for path in sorted(src_dir.iterdir()):
            if not path.is_file():
                continue
            if path.suffix.lower() not in exts:
                continue
            rel = f"{remote_dir}/{path.name}"
            data = path.read_bytes()
            digest = sha256_short(data)
            size = len(data)
            files[rel] = (path, size, digest)
            entries.append({"p": rel, "s": size, "h": digest})
            total_bytes += size
            version_hasher.update(f"{rel}:{size}:{digest}\n".encode("utf-8"))

    manifest = {
        "version": version_hasher.hexdigest()[:16],
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "fileCount": len(entries),
        "totalBytes": total_bytes,
        "files": entries,
    }
    return files, manifest


def ssh_run(client: paramiko.SSHClient, cmd: str, check: bool = True) -> tuple[int, str, str]:
    stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
    stdin.close()
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if check and code != 0:
        raise RuntimeError(f"SSH failed ({code}): {cmd}\n{err.strip()}")
    return code, out, err


def configure_nginx(client: paramiko.SSHClient, sftp: paramiko.SFTPClient) -> None:
    conf_body = NGINX_CONF.replace("{root}", REMOTE_ROOT)
    with sftp.file(SNIPPET, "w") as fh:
        fh.write(conf_body)
    sftp.chmod(SNIPPET, 0o644)

    with sftp.file(SITE, "r") as fh:
        site_text = fh.read().decode("utf-8")

    include_line = f"include {SNIPPET};"
    if SNIPPET not in site_text:
        if INCLUDE_AFTER in site_text:
            site_text = site_text.replace(
                INCLUDE_AFTER,
                f"{INCLUDE_AFTER}\n    {include_line}",
                1,
            )
        else:
            site_text = site_text.replace(
                "location / { return 404; }",
                f"{include_line}\n\n    location / {{ return 404; }}",
                1,
            )
        with sftp.file(SITE, "w") as fh:
            fh.write(site_text)
        print(f"[nginx] added {include_line} to {SITE}")
    else:
        print(f"[nginx] {SNIPPET} already included")

    _, out, err = ssh_run(client, "nginx -t && systemctl reload nginx")
    if out.strip():
        print(out.strip())
    if err.strip():
        print(err.strip())


def upload_full_tarball(
    client: paramiko.SSHClient,
    sftp: paramiko.SFTPClient,
    files: dict[str, tuple[pathlib.Path, int, str]],
    manifest_bytes: bytes,
) -> None:
    print(f"[pack] creating tar.gz for {len(files)} files...")
    with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as tmp:
        tmp_path = pathlib.Path(tmp.name)

    try:
        with tarfile.open(tmp_path, "w:gz", compresslevel=6) as tf:
            for rel, (local_path, _, _) in files.items():
                tf.add(local_path, arcname=rel, recursive=False)
            info = tarfile.TarInfo("manifest.json")
            info.size = len(manifest_bytes)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(manifest_bytes))

        tar_size = tmp_path.stat().st_size
        remote_tar = "/tmp/wf-assets-upload.tar.gz"
        print(f"[upload] sending {tar_size / 1048576:.2f} MB to {remote_tar}...")
        sftp.put(str(tmp_path), remote_tar)

        staging = f"{REMOTE_ROOT}.staging"
        old = f"{REMOTE_ROOT}.old"
        cmd = (
            f"rm -rf {staging} {old} && "
            f"mkdir -p {staging} && "
            f"tar -xzf {remote_tar} -C {staging} && "
            f"chmod -R a+rX {staging} && "
            f"if [ -d {REMOTE_ROOT} ]; then mv {REMOTE_ROOT} {old}; fi && "
            f"mv {staging} {REMOTE_ROOT} && "
            f"rm -rf {old} {remote_tar}"
        )
        ssh_run(client, cmd)
        print(f"[deploy] atomically installed {len(files)} assets -> {REMOTE_ROOT}")
    finally:
        tmp_path.unlink(missing_ok=True)


def upload_incremental(
    client: paramiko.SSHClient,
    sftp: paramiko.SFTPClient,
    files: dict[str, tuple[pathlib.Path, int, str]],
    manifest_bytes: bytes,
    remote_manifest: dict,
) -> None:
    remote_map = {
        item["p"]: (item.get("s"), item.get("h"))
        for item in remote_manifest.get("files", [])
    }
    to_upload = [
        (rel, local_path)
        for rel, (local_path, size, digest) in files.items()
        if remote_map.get(rel) != (size, digest)
    ]
    to_delete = [rel for rel in remote_map if rel not in files]

    if not to_upload and not to_delete and remote_manifest.get("version") == json.loads(manifest_bytes)["version"]:
        print("[sync] remote assets already up to date!")
        return

    print(f"[sync] upload={len(to_upload)}, delete={len(to_delete)}")
    if len(to_upload) > 200:
        upload_full_tarball(client, sftp, files, manifest_bytes)
        return

    dirs = {posixpath.dirname(f"{REMOTE_ROOT}/{rel}") for rel, _ in to_upload}
    if dirs:
        ssh_run(client, "mkdir -p " + " ".join(sorted(dirs)))

    for rel, local_path in to_upload:
        dst = f"{REMOTE_ROOT}/{rel}"
        tmp_dst = f"{dst}.tmp"
        sftp.put(str(local_path), tmp_dst)
        sftp.chmod(tmp_dst, 0o644)
        ssh_run(client, f"mv -f {tmp_dst} {dst}")

    if to_delete:
        rels = " ".join(f"{REMOTE_ROOT}/{rel}" for rel in to_delete)
        ssh_run(client, f"rm -f {rels}")

    tmp_manifest = f"{REMOTE_ROOT}/manifest.json.tmp"
    with sftp.file(tmp_manifest, "w") as fh:
        fh.write(manifest_bytes.decode("utf-8"))
    sftp.chmod(tmp_manifest, 0o644)
    ssh_run(client, f"mv -f {tmp_manifest} {REMOTE_ROOT}/manifest.json")
    print("[sync] incremental update complete")


def main() -> int:
    load_env_local()
    ap = argparse.ArgumentParser()
    ap.add_argument("--full", action="store_true", help="Force full tarball upload")
    ap.add_argument("--skip-nginx", action="store_true", help="Skip nginx snippet/reload")
    args = ap.parse_args()

    host = os.environ.get("WF_VPS_HOST", "")
    user = os.environ.get("WF_VPS_USER", "root")
    password = os.environ.get("WF_VPS_PASS", "")
    if not host or not password:
        print("[x] WF_VPS_HOST / WF_VPS_PASS missing (set env or .env.local)", file=sys.stderr)
        return 2

    files, manifest = collect_local_assets()
    manifest_bytes = json.dumps(manifest, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    print(
        f"[local] {manifest['fileCount']} files "
        f"({manifest['totalBytes'] / 1048576:.2f} MB) version={manifest['version']}"
    )

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        host,
        username=user,
        password=password,
        timeout=30,
        look_for_keys=False,
        allow_agent=False,
    )
    try:
        sftp = client.open_sftp()
        try:
            remote_manifest = None
            if not args.full:
                try:
                    with sftp.file(f"{REMOTE_ROOT}/manifest.json", "r") as fh:
                        remote_manifest = json.loads(fh.read().decode("utf-8"))
                except Exception:
                    remote_manifest = None

            if remote_manifest is not None:
                upload_incremental(client, sftp, files, manifest_bytes, remote_manifest)
            else:
                upload_full_tarball(client, sftp, files, manifest_bytes)

            if not args.skip_nginx:
                configure_nginx(client, sftp)
        finally:
            sftp.close()

        _, check_out, _ = ssh_run(
            client,
            "curl -fsSI https://data.ireescc.com/wf-assets/manifest.json | head -n 6; "
            "curl -fsSI https://data.ireescc.com/wf-assets/mod-frames/SilverSelectedBacker.png | head -n 6; "
            "curl -fsSI https://data.ireescc.com/wf-assets/mod-art/OmegaMod.webp | head -n 6",
            check=False,
        )
        print("[verify]\n" + check_out.strip())
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
