#!/usr/bin/env python3
"""
把 server/site 的站点资源整理成前端可直接加载的离线包：web/app/site/

做的事只有三件：
  1. 复制 jquery/min.js/zh.js/weapons.json/data/weapons
  2. 改写 site/index.html：注入 shim，把 localeLang 空对象换成 zh.js
  3. 生成 weapon-map.js（武器名 → 文件名），供 shim 解析 getWeapon.php

不复制 style-min.css（站点未抓取，且计算不依赖样式）。
"""
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "server" / "site"
DST = ROOT / "web" / "app" / "site"


def build_weapon_index(manifest: dict) -> dict:
    """对应 server/api.js 的 buildIndex()：每个武器抽一份精简索引。"""
    out = {}
    for name, fname in manifest.items():
        try:
            j = json.loads((SRC / "weapons" / fname).read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001 - 单个坏文件不该中断整体构建
            print(f"[!] {name}: {e}", file=sys.stderr)
            continue
        if not j.get("attacks"):
            continue
        out[name] = {
            "name": name,
            "category": j.get("category") or "",
            "categories": j.get("categories") or [],
            "compTags": j.get("compTags") or [],
            "tags": j.get("tags") or [],
            "type": j.get("type") or "",
            "masteryReq": j.get("masteryReq") or 0,
            "imageName": j.get("imageName") or "",
            "attacks": [a.get("name") for a in j["attacks"] if a.get("name")],
            "incarnon": bool(j.get("incarnon")),
            "mag": j.get("magazineSize"),
            "reload": j.get("reloadTime"),
            "trigger": j.get("trigger") or "",
        }
    return out


def main() -> int:
    if not (SRC / "min.js").exists():
        print(f"[x] 缺少 {SRC/'min.js'}", file=sys.stderr)
        return 1

    if DST.exists():
        shutil.rmtree(DST)
    DST.mkdir(parents=True)

    for f in ("min.js", "jquery-min.js", "zh.js", "weapons.json"):
        shutil.copy2(SRC / f, DST / f)
    shutil.copy2(ROOT / "web" / "offline" / "boot-shim.js", DST / "boot-shim.js")
    shutil.copytree(SRC / "weapons", DST / "weapons")
    shutil.copytree(SRC / "data", DST / "data")

    html = (SRC / "index.html").read_text(encoding="utf-8")

    # 站点的 <script>var localeLang = {};</script> 会覆盖 zh.js，改成加载 zh.js。
    html, n2 = re.subn(
        r"<script>\s*var localeLang\s*=\s*\{\};\s*</script>",
        '<script src="zh.js"></script>',
        html,
    )
    # 外部字体：离线环境会挂起，直接去掉引用（保留 <link> 会拖慢 iframe load）。
    html = re.sub(r'<link[^>]+fonts\.(googleapis|gstatic)\.com[^>]*>', "", html)

    # 在 head 第一个 script 之前插入 shim 与武器名→文件名映射（shim 要用）。
    # 武器索引是给主页面的 kernel-web.js 用的，不进 iframe。
    html, n1 = re.subn(
        r"(<head[^>]*>)",
        r'\1\n<script src="boot-shim.js"></script>\n'
        r'<script src="weapon-map.js"></script>',
        html,
        count=1,
    )

    (DST / "index.html").write_text(html, encoding="utf-8")

    # 武器名 → 文件名。名字里有空格和 &，不能靠规则推导，必须查表。
    manifest = json.loads((SRC / "weapons.json").read_text(encoding="utf-8"))
    (DST / "weapon-map.js").write_text(
        "window.__WF_WEAPONS=" + json.dumps(manifest, ensure_ascii=False) + ";",
        encoding="utf-8",
    )

    # 武器索引：服务端 api.js 启动时扫 666 个 JSON 建的那张表，这里预生成成脚本。
    # 浏览器不必为索引发 666 个请求。
    index = build_weapon_index(manifest)
    (DST / "weapon-index.js").write_text(
        "window.__WF_WEAPON_INDEX="
        + json.dumps(index, ensure_ascii=False, separators=(",", ":"))
        + ";",
        encoding="utf-8",
    )

    size = sum(p.stat().st_size for p in DST.rglob("*") if p.is_file())
    print(f"[ok] {DST}  {size/1048576:.2f} MB  索引 {len(index)}  shim={n1} zh={n2}")
    if not n1 or not n2:
        print("[!] 替换未全部命中，检查 server/site/index.html 结构是否变化", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
