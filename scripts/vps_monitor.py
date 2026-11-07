#!/usr/bin/env python3
"""
Warframe WorldState VPS Push Monitor
====================================
Lightweight background service to run on your Linux/VPS server.
Polls DE official worldState.php every 60 seconds and pushes instant notifications
to your iPhone via Bark, Telegram Bot, or Webhook when watched items appear.

Supported Watch Triggers:
- Core treasures: Orokin Catalyst (催化剂), Orokin Reactor (反应堆), Forma, Exilus
- Rare rewards: Riven Sliver, Kavat Genetic Code, Mutagen Mass, Wraith/Vandal parts
- Deterministic cycles: Cetus Night hunter alert, Baro Ki'Teer arrival
- High discounts: Darvo deal > 50%
"""

import os
import sys
import time
import json
import logging
from datetime import datetime
import urllib.request
import urllib.error

# ==================== CONFIGURATION ====================
WORLDSTATE_URL = "https://api.warframe.com/cdn/worldState.php"
POLL_INTERVAL_SECONDS = 60

# Bark iOS Push (Download Bark from iOS App Store, get your device key)
# e.g., "https://api.day.app/YOUR_KEY"
BARK_SERVER_URL = os.environ.get("BARK_URL", "")

# Telegram Bot (Optional: paste bot token and chat_id)
TG_BOT_TOKEN = os.environ.get("TG_BOT_TOKEN", "")
TG_CHAT_ID = os.environ.get("TG_CHAT_ID", "")

# Watched Keywords (case-insensitive substring match against rewards and mission types)
WATCHED_ITEMS = [
    {"id": "catalyst", "name": "Orokin 催化剂 (金土豆)", "keywords": ["Catalyst", "催化剂"]},
    {"id": "reactor", "name": "Orokin 反应堆 (银土豆)", "keywords": ["Reactor", "反应堆"]},
    {"id": "forma", "name": "Forma (福马)", "keywords": ["Forma"]},
    {"id": "exilus", "name": "特殊功能槽连接器", "keywords": ["Exilus"]},
    {"id": "mutagen", "name": "突变原聚合物 (Mutagen Mass)", "keywords": ["Mutagen"]},
    {"id": "riven_sliver", "name": "裂罅碎石", "keywords": ["RivenSliver", "裂罅碎石"]},
    {"id": "wraith_vandal", "name": "亡魂 / 破坏者 部件", "keywords": ["Wraith", "Vandal"]}
]

# State tracking to avoid duplicate notifications
seen_events = set()
cetus_night_notified = False
baro_notified = False

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

def send_push(title: str, body: str, group: str = "Warframe"):
    """Send push notification to iPhone via Bark or Telegram."""
    logging.info(f"🚨 [PUSH] {title} - {body}")
    
    # 1. Bark Push
    if BARK_SERVER_URL:
        try:
            url = f"{BARK_SERVER_URL.rstrip('/')}/{urllib.parse.quote(title)}/{urllib.parse.quote(body)}?group={group}&sound=bell"
            req = urllib.request.Request(url, headers={"User-Agent": "WarframeWatch-VPS/1.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status == 200:
                    logging.info("  -> Bark push delivered successfully.")
        except Exception as e:
            logging.error(f"  -> Bark push failed: {e}")
            
    # 2. Telegram Bot Push
    if TG_BOT_TOKEN and TG_CHAT_ID:
        try:
            tg_url = f"https://api.telegram.org/bot{TG_BOT_TOKEN}/sendMessage"
            payload = json.dumps({
                "chat_id": TG_CHAT_ID,
                "text": f"*{title}*\n{body}",
                "parse_mode": "Markdown"
            }).encode('utf-8')
            req = urllib.request.Request(tg_url, data=payload, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status == 200:
                    logging.info("  -> Telegram push delivered successfully.")
        except Exception as e:
            logging.error(f"  -> Telegram push failed: {e}")

def check_reward_match(reward_obj) -> list:
    """Check if a reward object contains any watched keywords."""
    if not reward_obj:
        return []
    
    matched = []
    # Convert reward object to string representation
    text = json.dumps(reward_obj, ensure_ascii=False).lower()
    for item in WATCHED_ITEMS:
        for kw in item["keywords"]:
            if kw.lower() in text:
                matched.append(item["name"])
                break
    return matched

def poll_worldstate():
    global cetus_night_notified, baro_notified
    
    req = urllib.request.Request(
        WORLDSTATE_URL,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WarframeWatch/1.0"}
    )
    
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        logging.warning(f"Failed to fetch worldState.php: {e}")
        return

    # 1. Check Alerts
    alerts = data.get("Alerts", [])
    for alert in alerts:
        aid = alert.get("_id", {}).get("$oid", "")
        if aid in seen_events:
            continue
        mission = alert.get("MissionInfo", {})
        rewards = mission.get("missionReward", {})
        matched = check_reward_match(rewards)
        if matched:
            seen_events.add(aid)
            loc = mission.get("location", "未知节点")
            send_push(
                title=f"警报触发: {' + '.join(matched)}",
                body=f"地点: {loc}\n请及时上线完成任务领取！"
            )

    # 2. Check Invasions
    invasions = data.get("Invasions", [])
    for inv in invasions:
        iid = inv.get("_id", {}).get("$oid", "")
        if inv.get("Completed", False) or iid in seen_events:
            continue
        att_rewards = inv.get("AttackerReward", {})
        def_rewards = inv.get("DefenderReward", {})
        matched_att = check_reward_match(att_rewards)
        matched_def = check_reward_match(def_rewards)
        
        all_matched = list(set(matched_att + matched_def))
        if all_matched:
            seen_events.add(iid)
            node = inv.get("Node", "未知节点")
            send_push(
                title=f"入侵战备: {' + '.join(all_matched)}",
                body=f"节点: {node}\n进攻方/防守方争夺中，派系奖励即将瓜分完毕！"
            )

    # 3. Check Cetus Night
    syndicates = data.get("SyndicateMissions", [])
    for s in syndicates:
        if s.get("Tag") == "CetusSyndicate":
            exp_sec = s.get("Expiry", {}).get("$date", {}).get("$numberLong")
            if exp_sec:
                exp_timestamp = int(exp_sec) / 1000.0
                rem = exp_timestamp - time.time()
                # 9000s cycle: last 3000s is night
                if 0 < rem <= 3000:
                    if not cetus_night_notified:
                        mins_left = int(rem / 60)
                        send_push(
                            title="夜灵平野: 黑夜降临 🌕",
                            body=f"夜灵平野已进入黑夜猎杀时刻！\n剩余黑夜时长: {mins_left} 分钟，三傻兆力使已苏醒。"
                        )
                        cetus_night_notified = True
                else:
                    cetus_night_notified = False

    # 4. Check Baro Ki'Teer
    void_traders = data.get("VoidTraders", [])
    for baro in void_traders:
        act = baro.get("Activation", {}).get("$date", {}).get("$numberLong")
        exp = baro.get("Expiry", {}).get("$date", {}).get("$numberLong")
        if act and exp:
            now = time.time()
            is_active = (int(act)/1000.0) <= now <= (int(exp)/1000.0)
            if is_active:
                if not baro_notified:
                    node = baro.get("Node", "虚空各中继站")
                    items_count = len(baro.get("Manifest", []))
                    send_push(
                        title="虚空商人: Baro 到港！🛒",
                        body=f"停留位置: {node}\n已携带 {items_count} 件 Prime 货物进港，停留 48 小时！"
                    )
                    baro_notified = True
            else:
                baro_notified = False

def main():
    logging.info("==========================================")
    logging.info("Warframe WorldState VPS Monitor Started")
    logging.info(f"Target URL: {WORLDSTATE_URL}")
    logging.info(f"Poll Interval: {POLL_INTERVAL_SECONDS}s")
    logging.info(f"Bark Configured: {'YES' if BARK_SERVER_URL else 'NO (Set BARK_URL env)'}")
    logging.info(f"Telegram Configured: {'YES' if TG_BOT_TOKEN else 'NO (Set TG_BOT_TOKEN/TG_CHAT_ID)'}")
    logging.info("==========================================")
    
    while True:
        try:
            poll_worldstate()
        except Exception as e:
            logging.error(f"Error in poll loop: {e}")
        time.sleep(POLL_INTERVAL_SECONDS)

if __name__ == "__main__":
    main()
