import sqlite3
import urllib.request
import json
import time
import os
import sys
from datetime import datetime

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT_DIR, "data", "wf_history.db")
WORLDSTATE_URL = "https://api.warframe.com/cdn/worldState.php"

def init_tables(conn):
    c = conn.cursor()
    c.execute("DROP TABLE IF EXISTS active_events")
    c.execute("""
    CREATE TABLE active_events (
        event_id TEXT PRIMARY KEY,
        target_id TEXT,
        category TEXT,
        node TEXT,
        title TEXT,
        first_seen_at REAL,
        last_seen_at REAL,
        is_completed INTEGER DEFAULT 0
    )
    """)
    c.execute("""
    CREATE TABLE IF NOT EXISTS event_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT,
        target_id TEXT,
        category TEXT,
        node TEXT,
        title TEXT,
        first_seen_at REAL,
        last_seen_at REAL,
        duration_seconds REAL,
        recorded_at REAL
    )
    """)
    c.execute("""
    CREATE TABLE IF NOT EXISTS target_summary (
        target_id TEXT PRIMARY KEY,
        display_name TEXT,
        category TEXT,
        total_seen INTEGER DEFAULT 0,
        last_seen_at REAL,
        avg_interval_seconds REAL,
        intervals_json TEXT
    )
    """)
    conn.commit()

def load_catalog(conn):
    c = conn.cursor()
    c.execute("SELECT id, section, title, is_deterministic, base_interval_seconds, meta_json FROM catalog_targets")
    rows = c.fetchall()
    catalog = {}
    for r in rows:
        catalog[r[0]] = {
            "id": r[0],
            "section": r[1],
            "title": r[2],
            "is_deterministic": bool(r[3]),
            "base_interval": r[4],
            "meta": json.loads(r[5])
        }
    return catalog

def extract_reward_strings(rw):
    res = []
    if isinstance(rw, dict):
        for item in rw.get("countedItems", []):
            if isinstance(item, dict):
                res.append(item.get("ItemType", ""))
            elif isinstance(item, str):
                res.append(item)
        for it in rw.get("items", []):
            if isinstance(it, str):
                res.append(it)
            elif isinstance(it, dict):
                res.append(it.get("ItemType", ""))
    elif isinstance(rw, list):
        for it in rw:
            res.extend(extract_reward_strings(it))
    elif isinstance(rw, str):
        res.append(rw)
    return res

def poll_and_record(conn, catalog):
    req = urllib.request.Request(WORLDSTATE_URL, headers={"User-Agent": "WarframeWatch-Daemon/1.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        ws = json.loads(resp.read().decode("utf-8"))
    
    now = time.time()
    c = conn.cursor()
    current_active = set()
    
    # 1. Invasions
    for inv in ws.get("Invasions", []):
        if inv.get("Completed", False):
            continue
        inv_id = inv.get("_id", {}).get("$oid", str(inv.get("_id", "")))
        node = inv.get("Node", "")
        node_target_id = f"node_{node}"
        
        # Match node target
        if node_target_id in catalog:
            t = catalog[node_target_id]
            ekey = f"inv_{inv_id}_{node_target_id}"
            current_active.add(ekey)
            record_active(c, ekey, node_target_id, "invasion", node, t["title"], now)
            
def extract_reward_strings(rw):
    res = []
    if isinstance(rw, dict):
        for item in rw.get("countedItems", []):
            if isinstance(item, dict):
                res.append(item.get("ItemType", ""))
            elif isinstance(item, str):
                res.append(item)
        for it in rw.get("items", []):
            if isinstance(it, str):
                res.append(it)
            elif isinstance(it, dict):
                res.append(it.get("ItemType", ""))
    elif isinstance(rw, list):
        for it in rw:
            res.extend(extract_reward_strings(it))
    elif isinstance(rw, str):
        res.append(rw)
    return res
                
        for rw_str in rewards:
            rw_lower = rw_str.lower()
            for tid, t in catalog.items():
                if t["section"] == "items":
                    kws = t["meta"].get("keywords", [])
                    if any(k.lower() in rw_lower for k in kws):
                        ekey = f"inv_{inv_id}_{tid}"
                        current_active.add(ekey)
                        record_active(c, ekey, tid, "invasion", node, t["title"], now)
                        
    # 2. Alerts
    for alert in ws.get("Alerts", []):
        alert_id = alert.get("_id", {}).get("$oid", str(alert.get("_id", "")))
        mission = alert.get("MissionInfo", {})
        node = mission.get("location", "")
        node_target_id = f"node_{node}"
        
        if node_target_id in catalog:
            t = catalog[node_target_id]
            ekey = f"alert_{alert_id}_{node_target_id}"
            current_active.add(ekey)
            record_active(c, ekey, node_target_id, "alert", node, t["title"], now)
            
        rewards = []
        rw = mission.get("missionReward", {})
        for item in rw.get("countedItems", []):
            rewards.append(item.get("ItemType", ""))
        for it in rw.get("items", []):
            rewards.append(it)
            
        for rw_str in rewards:
            rw_lower = rw_str.lower()
            for tid, t in catalog.items():
                if t["section"] == "items":
                    kws = t["meta"].get("keywords", [])
                    if any(k.lower() in rw_lower for k in kws):
                        ekey = f"alert_{alert_id}_{tid}"
                        current_active.add(ekey)
                        record_active(c, ekey, tid, "alert", node, t["title"], now)

    # 3. Active Fissures (ActiveMissions)
    for f in ws.get("ActiveMissions", []):
        f_id = f.get("_id", {}).get("$oid", str(f.get("_id", "")))
        node = f.get("Node", "")
        tier = f.get("Modifier", "")
        mtype = f.get("MissionType", "")
        is_hard = bool(f.get("Hard", False))
        diff_str = "hard" if is_hard else "normal"
        
        # Match fissure combo
        fissure_target_id = f"fissure_{tier}_{mtype}_{diff_str}"
        if fissure_target_id in catalog:
            t = catalog[fissure_target_id]
            ekey = f"fissure_{f_id}_{fissure_target_id}"
            current_active.add(ekey)
            record_active(c, ekey, fissure_target_id, "fissure", node, t["title"], now)
            
        # Match node
        node_target_id = f"node_{node}"
        if node_target_id in catalog:
            t = catalog[node_target_id]
            ekey = f"fissure_{f_id}_{node_target_id}"
            current_active.add(ekey)
            record_active(c, ekey, node_target_id, "fissure", node, t["title"], now)

    # 4. Process ended events
    c.execute("SELECT event_id, target_id, category, node, title, first_seen_at, last_seen_at FROM active_events WHERE is_completed = 0")
    for row in c.fetchall():
        eid, tid, cat, node, title, fseen, lseen = row
        if eid not in current_active:
            duration = lseen - fseen
            c.execute("""
                INSERT INTO event_history (event_id, target_id, category, node, title, first_seen_at, last_seen_at, duration_seconds, recorded_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (eid, tid, cat, node, title, fseen, lseen, duration, now))
            c.execute("UPDATE active_events SET is_completed = 1 WHERE event_id = ?", (eid,))
            
            # Update target summary
            c.execute("SELECT total_seen, last_seen_at, intervals_json FROM target_summary WHERE target_id = ?", (tid,))
            s_row = c.fetchone()
            if s_row is None:
                c.execute("""
                    INSERT INTO target_summary (target_id, display_name, category, total_seen, last_seen_at, avg_interval_seconds, intervals_json)
                    VALUES (?, ?, ?, 1, ?, 0, '[]')
                """, (tid, title, cat, lseen))
            else:
                tot, old_lseen, intervals_str = s_row
                intervals = json.loads(intervals_str or "[]")
                if old_lseen:
                    diff = fseen - old_lseen
                    if diff > 600:
                        intervals.append(diff)
                avg_int = sum(intervals) / len(intervals) if intervals else 0
                c.execute("""
                    UPDATE target_summary
                    SET total_seen = total_seen + 1, last_seen_at = ?, avg_interval_seconds = ?, intervals_json = ?
                    WHERE target_id = ?
                """, (lseen, avg_int, json.dumps(intervals[-50:]), tid))

    conn.commit()
    c.execute("SELECT count(*) FROM active_events WHERE is_completed = 0")
    cnt = c.fetchone()[0]
    return cnt

def record_active(c, event_id, target_id, category, node, title, now):
    c.execute("SELECT first_seen_at FROM active_events WHERE event_id = ?", (event_id,))
    row = c.fetchone()
    if row is None:
        c.execute("""
            INSERT INTO active_events (event_id, target_id, category, node, title, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (event_id, target_id, category, node, title, now, now))
        print(f"[{datetime.now().strftime('%H:%M:%S')}] [+] 记录新上线: {title} (节点: {node})")
    else:
        c.execute("UPDATE active_events SET last_seen_at = ? WHERE event_id = ?", (now, event_id))

if __name__ == "__main__":
    conn = sqlite3.connect(DB_PATH)
    init_tables(conn)
    catalog = load_catalog(conn)
    print(f"已加载 {len(catalog)} 个全量监控目标定义，开始拉取世界状态比对...")
    active_cnt = poll_and_record(conn, catalog)
    print(f"[{datetime.now().strftime('%H:%M:%S')}] 数据库抓取完成！当前正在活跃匹配的监控事件数: {active_cnt}")
    conn.close()
