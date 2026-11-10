#!/usr/bin/env python3
"""下载武器缩略图，供 App 离线显示。

站点把武器图放在自己的 /data/img/ 下，文件名就是武器数据里的 imageName。
一次下全，之后由 build_web_site.py 复制进 ios/DamageCalc/icons。

    python scripts/fetch_weapon_icons.py            # 增量：已有的跳过
    python scripts/fetch_weapon_icons.py --force    # 全部重下
"""
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
LIST = ROOT / "web" / "app" / "site" / "weapons-list.json"
OUT = ROOT / "assets" / "weapon-icons"
CDN = "https://warframe-damage.com/data/img/"


def fetch(name: str, force: bool) -> tuple[str, str]:
    dst = OUT / name
    if dst.exists() and dst.stat().st_size > 0 and not force:
        return name, "skip"
    try:
        req = Request(CDN + name, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=20) as r:
            data = r.read()
        if not data:
            return name, "empty"
        dst.write_bytes(data)
        return name, "ok"
    except Exception as e:  # noqa: BLE001
        return name, f"fail:{type(e).__name__}"


def main() -> int:
    force = "--force" in sys.argv
    if not LIST.exists():
        print(f"[x] 缺少 {LIST}，先跑 scripts/build_web_site.py", file=sys.stderr)
        return 1

    catalog = json.loads(LIST.read_text(encoding="utf-8"))
    names = sorted({w["img"] for w in catalog if w.get("img")})
    OUT.mkdir(parents=True, exist_ok=True)

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda n: fetch(n, force), names))

    ok = sum(1 for _, s in results if s == "ok")
    skip = sum(1 for _, s in results if s == "skip")
    bad = [(n, s) for n, s in results if s.startswith("fail") or s == "empty"]
    size = sum(p.stat().st_size for p in OUT.glob("*.webp"))
    print(f"[ok] 下载 {ok} · 已有 {skip} · 失败 {len(bad)} · {size/1048576:.2f} MB → {OUT}")
    for n, s in bad[:10]:
        print(f"  {n}: {s}")
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())
