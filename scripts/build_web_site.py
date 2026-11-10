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
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "server" / "site"
DST = ROOT / "web" / "app" / "site"
NODE = shutil.which("node") or "node"


CAT_ORDER = {"Primary": 0, "Secondary": 1, "Melee": 2, "Archgun": 3, "Exalted Weapon": 4}


def read_locale(path: Path) -> dict:
    """zh.js 是 `var localeLang = {...}`，值是单引号字符串且内含 HTML，不是 JSON。

    交给 node 执行一次最省事：这份表本来就只在 JS 里用，自己写解析器只会跑偏。
    node 不可用时退回空表，武器名显示英文，不影响计算。
    """
    if not path.exists():
        return {}
    src = path.read_text(encoding="utf-8") + "\nprocess.stdout.write(JSON.stringify(localeLang));"
    try:
        # 走 stdin：这份表 130KB，作为 -e 参数会超过 Windows 命令行上限
        r = subprocess.run([NODE, "-"], input=src.encode("utf-8"),
                           capture_output=True, timeout=60)
        if r.returncode != 0:
            print(f"[!] node 执行 {path.name} 失败: {r.stderr.decode('utf-8', 'replace')[:200]}",
                  file=sys.stderr)
            return {}
        return json.loads(r.stdout.decode("utf-8"))
    except Exception as e:  # noqa: BLE001
        print(f"[!] 解析 {path.name} 失败: {e}", file=sys.stderr)
        return {}


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

    # 武器清单（给 iOS 武器列表用）：名字、中文名、分类、缩略图、攻击段数。
    # 中文名来自站点自带的 localeLang，和计算器界面显示的是同一份。
    zh = read_locale(SRC / "zh.js")
    catalog = []
    for name, w in index.items():
        catalog.append({
            "n": name,
            "z": zh.get(name, name),
            "c": w["category"],
            "t": w["type"],
            "img": w["imageName"],
            "mr": w["masteryReq"],
            "atk": w["attacks"],
            "inc": w["incarnon"],
        })
    catalog.sort(key=lambda x: (CAT_ORDER.get(x["c"], 9), x["z"]))
    (DST / "weapons-list.json").write_text(
        json.dumps(catalog, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    # iOS App 用同一份资源：project.yml 把它当 folder reference 打进 bundle，
    # 所以这里同步一份过去（构建产物，不入库）。放在 WarframeWatch 之外，
    # 免得和那个 target 的普通 sources 重复收录。
    ios = ROOT / "ios" / "DamageCalc"
    if ios.exists():
        shutil.rmtree(ios)
    ios.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "web" / "app", ios)
    print(f"[ios] {ios}")

    size = sum(p.stat().st_size for p in DST.rglob("*") if p.is_file())
    print(f"[ok] {DST}  {size/1048576:.2f} MB  索引 {len(index)}  shim={n1} zh={n2}")
    if not n1 or not n2:
        print("[!] 替换未全部命中，检查 server/site/index.html 结构是否变化", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
