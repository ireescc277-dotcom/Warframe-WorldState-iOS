#!/usr/bin/env python3
"""把 Bark 的四档中断级别和“像来电”推一遍，用来看实际效果。

用法：python scripts/bark_demo.py [设备密钥]
密钥也可放在环境变量 WF_BARK_KEY。

按强度从弱到强，每条间隔 8 秒，方便逐条分辨。
"""

import json
import os
import sys
import time
import urllib.request

SERVER = "https://api.day.app"
GROUP = "warframe-demo"

# (标题, 正文, 额外参数)
CASES = [
    ("1/6 passive", "只进通知中心：不亮屏、不响、没有横幅。下拉通知中心才看得到。",
     {"level": "passive"}),
    ("2/6 active", "默认级别：亮屏 + 横幅 + 一声。专注模式开着的话会被拦下。",
     {"level": "active"}),
    ("3/6 timeSensitive", "时效性：专注模式也照常弹出来。静音开关在静音位时仍然不响。",
     {"level": "timeSensitive"}),
    ("4/6 critical", "关键警报：绕过静音开关和专注模式，强制响铃。音量 5。",
     {"level": "critical", "volume": 5}),
    ("5/6 critical 满音量", "同上，音量 10。这是 Bark 允许的最大值。",
     {"level": "critical", "volume": 10}),
    ("6/6 像来电", "critical + call=1：铃声循环 30 秒，接近来电的持续响。",
     {"level": "critical", "volume": 10, "call": "1"}),
]


def send(key: str, title: str, body: str, extra: dict) -> bool:
    payload = {
        "device_key": key,
        "title": title,
        "body": body,
        "group": GROUP,
        "ttl": 600,
        "isArchive": 1,
    }
    payload.update(extra)
    req = urllib.request.Request(
        SERVER + "/push",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            ok = data.get("code") == 200
            print(f"  {'√' if ok else '×'} {title}  {data.get('message', '')}")
            return ok
    except Exception as e:
        print(f"  × {title}  {e}")
        return False


def main() -> int:
    key = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("WF_BARK_KEY", "")).strip()
    if not key:
        print("没有设备密钥：传参或设置 WF_BARK_KEY", file=sys.stderr)
        return 2
    for i, (title, body, extra) in enumerate(CASES):
        if i:
            time.sleep(8)
        send(key, title, body, extra)
    return 0


if __name__ == "__main__":
    sys.exit(main())
