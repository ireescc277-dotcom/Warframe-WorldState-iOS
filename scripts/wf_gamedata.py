#!/usr/bin/env python3
"""直接从 DE 的公开导出拉游戏数据，不经过 Overwolf / AlecaFrame。

为什么可以这样：`content.warframe.com/PublicExport/index_{en,zh}.txt.lzma`
只有 496 字节，每行是 `ExportWeapons_en.json!00_<hash>`。hash 变了才说明
这个文件变了，所以每 10 分钟问一次索引几乎没有成本；没变就不下载。

公开导出由客户端补丁重新生成，改 mod 数值、加新武器都在里面。AlecaFrame
的 `cachedData/json/*.json` 本来也是这份东西的转存，只是要等 Overwolf
更新才有；直接连源头就不看它脸色。

    python scripts/wf_gamedata.py once                 # 拉一次、构建、写盘
    python scripts/wf_gamedata.py watch --interval 600 # 常驻轮询
    python scripts/wf_gamedata.py once --publish /var/www/wf/<token>

产物（默认 data/gamedata/）
    gamedata.json       武器基础数值 + mod 各等级数值 + 中英文名
    gamedata.meta.json  数据版本（索引 hash）、官方最后修改时间、条目数
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import lzma
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone

BASE = "https://content.warframe.com/PublicExport"
INDEX = BASE + "/index_{lang}.txt.lzma"
MANIFEST = BASE + "/Manifest/"
UA = "WarframeWatch/1.0 (+https://data.ireescc.com)"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# VPS 上脚本直接躺在 /opt/wf-monitor 下，没有 scripts/ 这一层，用环境变量指
DATA = os.environ.get("WF_GAMEDATA_DATA") or os.path.join(ROOT, "data", "gamedata")
RAW = os.path.join(DATA, "raw")
STATE = os.path.join(DATA, "state.json")

# 只下这两组：武器给 DPS 的底子，mod 给加成。其余（遗物、配方、外观）
# 体积大且跟当前功能无关，需要时再往这里加。
FILES = ("ExportWeapons", "ExportUpgrades")

# 武器保留的字段，键名压短；damagePerShot 的 20 个槽位是 IPS + 各元素。
WEAPON_KEYS = (
    ("totalDamage", "td"), ("criticalChance", "cc"), ("criticalMultiplier", "cm"),
    ("procChance", "sc"), ("fireRate", "fr"), ("magazineSize", "mag"),
    ("reloadTime", "rl"), ("multishot", "ms"), ("trigger", "tr"),
    ("productCategory", "cat"), ("omegaAttenuation", "om"), ("masteryReq", "mr"),
)
MOD_KEYS = (
    ("type", "t"), ("compatName", "cp"), ("polarity", "pol"),
    ("rarity", "r"), ("fusionLimit", "mx"), ("baseDrain", "d"),
)


def log(msg: str) -> None:
    stamp = datetime.now().strftime("%m-%d %H:%M:%S")
    print(f"[{stamp}] {msg}", flush=True)


def fetch(url: str, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def load_state() -> dict:
    try:
        with open(STATE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_json(path: str, doc: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def parse_index(text: str) -> dict[str, str]:
    """`ExportWeapons_en.json!00_abc` -> {'ExportWeapons_en.json': '00_abc'}"""
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or "!" not in line:
            continue
        name, _, digest = line.partition("!")
        out[name] = digest
    return out


def _xz_text(raw: bytes) -> str:
    """备用解压：调 xz CLI。

    liblzma 5.2（Ubuntu 22.04 的 python3.10 就链接它）遇到缺结束标记的流，
    会在最后一次 decode 里把已解出的尾巴一起丢掉；xz 命令行走的是同一份库，
    但它先写 stdout 再报错，所以能拿到完整内容。
    """
    import shutil
    import subprocess
    import tempfile

    exe = shutil.which("xz") or shutil.which("lzma")
    if not exe:
        return ""
    with tempfile.NamedTemporaryFile(suffix=".lzma", delete=False) as fh:
        fh.write(raw)
        path = fh.name
    try:
        proc = subprocess.run([exe, "-dc", path], capture_output=True, timeout=60)
        return proc.stdout.decode("utf-8", "replace")
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def lzma_text(raw: bytes) -> str:
    """解 index 用的 lzma。

    DE 的索引流末尾没有结束标记：新版 liblzma 容忍，旧版直接抛异常。
    头部 5..13 字节写着解压后长度，拿它当验收标准，不够就换 xz 再解一次。
    """
    expect = int.from_bytes(raw[5:13], "little") if len(raw) >= 13 else 0
    dec = lzma.LZMADecompressor(lzma.FORMAT_ALONE)
    out = bytearray()
    try:
        for i in range(0, len(raw), 64):
            out += dec.decompress(raw[i:i + 64])
            if dec.eof:
                break
    except lzma.LZMAError:
        pass
    if expect and len(out) < expect:
        alt = _xz_text(raw)
        if len(alt.encode("utf-8")) > len(out):
            return alt
    return out.decode("utf-8", "replace")


def sync_lang(lang: str, state: dict, force: bool = False) -> list[str]:
    """按索引 hash 增量下载。返回本次真正更新的文件名。"""
    raw = fetch(INDEX.format(lang=lang), timeout=30)
    text = lzma_text(raw)
    index = parse_index(text)
    known = {} if force else (state.get(lang) or {})
    changed = [n for n, h in index.items() if known.get(n) != h]
    os.makedirs(RAW, exist_ok=True)
    for name in changed:
        if not name.startswith(FILES):
            continue
        body = fetch(MANIFEST + name + "!" + index[name], timeout=180)
        path = os.path.join(RAW, name)
        with open(path + ".tmp", "wb") as fh:
            fh.write(body)
        os.replace(path + ".tmp", path)
        log(f"↓ {name} {len(body) / 1e6:.1f} MB")
    state[lang] = index
    state["indexSha"] = hashlib.sha1(raw).hexdigest()[:12]
    state["checkedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return [n for n in changed if n.startswith(FILES)]


def load_raw(name: str) -> dict:
    path = os.path.join(RAW, name)
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def zh_names(kind: str) -> dict[str, str]:
    """中文导出按 uniqueName 取名字；没有中文文件时返回空，调用方回退英文。"""
    doc = load_raw(f"Export{kind}_zh.json")
    rows = doc.get(f"Export{kind}") or []
    return {r["uniqueName"]: r.get("name") or "" for r in rows if r.get("uniqueName")}


def build_weapons() -> dict:
    rows = load_raw("ExportWeapons_en.json").get("ExportWeapons") or []
    zh = zh_names("Weapons")
    out = {}
    for r in rows:
        u = r.get("uniqueName")
        if not u:
            continue
        item = {"n": r.get("name") or "", "z": zh.get(u) or r.get("name") or ""}
        dmg = r.get("damagePerShot") or []
        # 20 个 float 原样保留：元素的相对比例决定配卡怎么算
        item["dmg"] = [round(float(x), 4) for x in dmg]
        for src, dst in WEAPON_KEYS:
            if r.get(src) is not None:
                item[dst] = r[src]
        out[u] = item
    return out


def build_mods() -> dict:
    rows = load_raw("ExportUpgrades_en.json").get("ExportUpgrades") or []
    zh = zh_names("Upgrades")
    out = {}
    for r in rows:
        u = r.get("uniqueName")
        if not u:
            continue
        item = {"n": r.get("name") or "", "z": zh.get(u) or r.get("name") or ""}
        for src, dst in MOD_KEYS:
            if r.get(src) is not None:
                item[dst] = r[src]
        # 每级一行字符串，和游戏里数值栏一致；解析留给计算器
        levels = []
        for step in r.get("levelStats") or []:
            levels.append([s for s in (step.get("stats") or [])])
        item["lv"] = levels
        out[u] = item
    return out


def build_riven_tags(rows: list[dict] | None = None) -> dict[str, list[dict]]:
    """Extract Riven tag coefficients from DE's public upgrade export.

    Riven stats are not ordinary rank tables.  Their ``upgradeEntries`` hold
    the base coefficient plus the generated name fragments that the account
    fingerprint later combines with disposition, rank and roll attenuation.
    Keeping them beside the normal game data means account import does not
    need AlecaFrame's cached copy or an independently maintained tag table.
    """
    if rows is None:
        rows = load_raw("ExportUpgrades_en.json").get("ExportUpgrades") or []
    result: dict[str, list[dict]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        unique_name = row.get("uniqueName")
        if not isinstance(unique_name, str) or "/Randomized/" not in unique_name:
            continue
        riven_type = unique_name.rsplit("/", 1)[-1]
        entries: list[dict] = []
        seen_tags: set[str] = set()
        for entry in row.get("upgradeEntries") or []:
            if not isinstance(entry, dict):
                continue
            tag = entry.get("tag")
            if not isinstance(tag, str) or not tag or tag in seen_tags:
                continue
            values = entry.get("upgradeValues")
            values = values if isinstance(values, list) else []
            first = values[0] if values and isinstance(values[0], dict) else {}
            try:
                value = float(first.get("value"))
            except (TypeError, ValueError):
                continue
            if value == 0:
                continue
            entries.append({
                "tag": tag,
                "value": value,
                "prefix": entry.get("prefixTag") if isinstance(entry.get("prefixTag"), str) else "",
                "suffix": entry.get("suffixTag") if isinstance(entry.get("suffixTag"), str) else "",
            })
            seen_tags.add(tag)
        if entries:
            result[riven_type] = entries
    return result


def build(out_dir: str = DATA, publish: str | None = None) -> dict:
    weapons = build_weapons()
    mods = build_mods()
    riven_tags = build_riven_tags()
    state = load_state()
    doc = {"weapons": weapons, "mods": mods, "rivenTags": riven_tags}
    path = os.path.join(out_dir, "gamedata.json")
    save_json(path, doc)
    payload = gzip.compress(json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8"), 6)
    gz_path = os.path.join(out_dir, "gamedata.json.gz")
    with open(gz_path, "wb") as fh:
        fh.write(payload)
    meta = {
        "build": state.get("indexSha"),
        "checkedAt": state.get("checkedAt"),
        "builtAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "weapons": len(weapons),
        "mods": len(mods),
        "rivenTags": sum(len(entries) for entries in riven_tags.values()),
        "bytes": len(payload),
    }
    save_json(os.path.join(out_dir, "gamedata.meta.json"), meta)
    if publish:
        os.makedirs(publish, exist_ok=True)
        with open(os.path.join(publish, "gamedata.json.gz"), "wb") as fh:
            fh.write(payload)
        save_json(os.path.join(publish, "gamedata.meta.json"), meta)
        log(f"发布 {publish}/gamedata.json.gz")
    log(f"√ 武器 {len(weapons)} · mod {len(mods)} · 紫卡词条 {meta['rivenTags']} · gz {len(payload) / 1e3:.0f} KB · build {meta['build']}")
    return meta


def once(out_dir: str, publish: str | None, force: bool) -> dict:
    state = load_state()
    changed: list[str] = []
    for lang in ("en", "zh"):
        changed += sync_lang(lang, state, force=force)
    save_json(STATE, state)
    if changed or force or not os.path.exists(os.path.join(out_dir, "gamedata.json")):
        log(f"索引有更新（{len(changed)} 个文件），重建")
        return build(out_dir, publish)
    log("索引未变，跳过构建")
    if publish:
        # 定时器重启后 publish 目录可能被清空，补一次
        build(out_dir, publish)
    return {}


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass
    ap = argparse.ArgumentParser(description="从 DE 公开导出构建游戏数据")
    ap.add_argument("cmd", nargs="?", default="once", choices=("once", "watch", "build"))
    ap.add_argument("--interval", type=int, default=600)
    ap.add_argument("--out", default=DATA)
    ap.add_argument("--publish", default=os.environ.get("WF_GAMEDATA_PUBLISH") or None)
    ap.add_argument("--force", action="store_true", help="忽略缓存重新全下")
    args = ap.parse_args()

    if args.cmd == "build":
        build(args.out, args.publish)
        return 0
    if args.cmd == "once":
        once(args.out, args.publish, args.force)
        return 0
    while True:
        try:
            once(args.out, args.publish, args.force)
        except Exception as exc:  # noqa: BLE001
            log(f"× {exc}")
        time.sleep(max(60, args.interval))


if __name__ == "__main__":
    raise SystemExit(main())
