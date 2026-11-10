import json
import sqlite3
import os
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DICT_PATH = os.path.join(ROOT_DIR, "WarframeWatch", "Resources", "DefaultDict.json")
OUTPUT_JSON = os.path.join(ROOT_DIR, "WarframeWatch", "Resources", "CompleteCatalog.json")
DB_PATH = os.path.join(ROOT_DIR, "data", "wf_history.db")
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

with open(DICT_PATH, 'r', encoding='utf-8') as f:
    d = json.load(f)

nodes = d.get('nodes', {})
mission_types = d.get('missionTypes', {})
tiers = d.get('tiers', {})

catalog = []

# =========================================================================
# 1. 确定性周期与定时重置 (Deterministic Cycles & Resets, 21 项)
# =========================================================================
cycles = [
    ("cycle_cetus_night", "夜灵平野 · 黑夜 (三傻猎杀)", "希图斯 150 分钟循环（50 分钟黑夜）", "moon.stars.fill", 150 * 60),
    ("cycle_cetus_day", "夜灵平野 · 白昼", "希图斯 150 分钟循环（100 分钟白天）", "sun.max.fill", 150 * 60),
    ("cycle_vallis_warm", "奥布山谷 · 暖温期", "福尔图娜 1600 秒循环（400 秒暖温）", "thermometer.sun.fill", 1600),
    ("cycle_vallis_cold", "奥布山谷 · 寒冷期", "福尔图娜 1600 秒循环（1200 秒寒冷）", "thermometer.snowflake", 1600),
    ("cycle_cambion_vome", "魔导原形 · 沃姆 (Vome)", "火卫二 150 分钟循环（50 分钟沃姆）", "eye.fill", 150 * 60),
    ("cycle_cambion_fass", "魔导原形 · 法斯 (Fass)", "火卫二 150 分钟循环（100 分钟法斯）", "flame.fill", 150 * 60),
    ("cycle_duviri_joy", "双衍王境 · 喜悦心境 (Joy)", "双衍 10 小时循环（每心境 2 小时）", "sparkles", 10 * 3600),
    ("cycle_duviri_anger", "双衍王境 · 愤怒心境 (Anger)", "双衍 10 小时循环（每心境 2 小时）", "flame", 10 * 3600),
    ("cycle_duviri_envy", "双衍王境 · 嫉妒心境 (Envy)", "双衍 10 小时循环（每心境 2 小时）", "leaf.fill", 10 * 3600),
    ("cycle_duviri_sorrow", "双衍王境 · 悲伤心境 (Sorrow)", "双衍 10 小时循环（每心境 2 小时）", "cloud.rain.fill", 10 * 3600),
    ("cycle_duviri_fear", "双衍王境 · 恐惧心境 (Fear)", "双衍 10 小时循环（每心境 2 小时）", "exclamationmark.shield", 10 * 3600),
    ("cycle_earth_day", "地球常规星图 · 白昼", "地球普通节点 8 小时循环（4 小时白昼，扫描日光植物）", "sun.haze.fill", 8 * 3600),
    ("cycle_earth_night", "地球常规星图 · 黑夜", "地球普通节点 8 小时循环（4 小时黑夜，扫描月光植物）", "moon.fill", 8 * 3600),
    ("cycle_baro_arrive", "虚空商人 Baro Ki'Teer 到港", "隔周周五 21:00 进港停留 48 小时", "person.crop.rectangle.stack", 14 * 86400),
    ("cycle_sortie_reset", "每日突击任务重置", "每日北京时间 00:00 准时重置", "shield.checkered", 86400),
    ("cycle_archon_reset", "执政官猎杀每周重置", "每周一北京时间 00:00 准时重置", "bolt.shield.fill", 7 * 86400),
    ("cycle_netracell_reset", "奈特拉密室周重置", "每周一北京时间 00:00 准时重置 (5次)", "cube.transparent", 7 * 86400),
    ("cycle_deep_archimedea_reset", "深层古灵档案重置", "每周一北京时间 00:00 准时重置", "books.vertical.fill", 7 * 86400),
    ("cycle_nightwave_reset", "午夜电波周常任务重置", "每周一北京时间 08:00 准时重置", "radio.fill", 7 * 86400),
    ("cycle_teshin_reset", "钢铁之路阁下 Teshin 轮换", "每周一北京时间 08:00 准时重置（8周商品循环）", "figure.fencing", 7 * 86400),
    ("cycle_zariman_reset", "扎里曼侵入派系轮换", "每 2.5 小时轮换一次 Corpus / Grineer", "arrow.triangle.2.circlepath", 5 * 3600)
]

for cid, title, sub, icon, interval in cycles:
    catalog.append({
        "id": cid,
        "section": "cycles",
        "title": title,
        "subtitle": sub,
        "icon": icon,
        "is_deterministic": True,
        "base_interval_seconds": interval,
        "meta": {"type": "cycle"}
    })

# =========================================================================
# 2. 星图全节点 (Star Chart Nodes, 全量 452 个节点，零删减)
# =========================================================================
for node_id, info in nodes.items():
    name = info.get("n", node_id)
    faction = info.get("e", "未知派系")
    mtype = info.get("t", "常规任务")
    
    catalog.append({
        "id": f"node_{node_id}",
        "section": "nodes",
        "title": name,
        "subtitle": f"{faction} · {mtype}",
        "icon": "globe.asia.australia.fill",
        "is_deterministic": False,
        "base_interval_seconds": 0,
        "meta": {
            "type": "node",
            "node_key": node_id,
            "faction": faction,
            "mission_type": mtype
        }
    })

# =========================================================================
# 3. 虚空裂隙全空间 (Fissures Matrix: 6 纪元 × 28 任务类型 × 2 难度 = 336 组合)
# =========================================================================
tier_names = {
    "VoidT1": "古纪 (Lith)",
    "VoidT2": "前纪 (Meso)",
    "VoidT3": "中纪 (Neo)",
    "VoidT4": "后纪 (Axi)",
    "VoidT5": "安魂 (Requiem)",
    "VoidT6": "全能 (Omnia)"
}

for t_key, t_name in tiers.items():
    t_display = tier_names.get(t_key, t_name)
    for m_key, m_name in mission_types.items():
        if m_key == "MT_DEFAULT" or m_key == "MT_PVP":
            continue
        # Normal
        catalog.append({
            "id": f"fissure_{t_key}_{m_key}_normal",
            "section": "fissures",
            "title": f"[{t_display}] {m_name} (普通)",
            "subtitle": f"常规虚空裂隙 · {m_name}",
            "icon": "bolt.badge.clock",
            "is_deterministic": False,
            "base_interval_seconds": 14400, # ~4小时
            "meta": {
                "type": "fissure",
                "tier": t_key,
                "mission_type": m_key,
                "is_hard": False
            }
        })
        # Steel Path
        catalog.append({
            "id": f"fissure_{t_key}_{m_key}_hard",
            "section": "fissures",
            "title": f"[{t_display}] {m_name} (钢铁之路)",
            "subtitle": f"钢铁之路裂隙 · +100级 · 钢铁精华",
            "icon": "shield.lefthalf.filled.badge.checkmark",
            "is_deterministic": False,
            "base_interval_seconds": 21600, # ~6小时
            "meta": {
                "type": "fissure",
                "tier": t_key,
                "mission_type": m_key,
                "is_hard": True
            }
        })

# =========================================================================
# 4. 核心物资、武器部件与掉落物品 (Items & Drops)
# =========================================================================
# Built-in exhaustive list of real invasion & alert items
items_pool = [
    # 战略强化
    ("catalyst", "Orokin 催化剂 (金土豆) 蓝图", "武器容量翻倍核心道具", "sparkles", ["Catalyst", "催化剂"], 58.5 * 3600),
    ("reactor", "Orokin 反应堆 (银土豆) 蓝图", "战甲/同伴/载具容量翻倍", "sparkles", ["Reactor", "反应堆"], 56.2 * 3600),
    ("forma", "塑形块 (Forma) 蓝图/成品", "装备极化槽位极性改变", "plus.circle.fill", ["Forma", "塑形块"], 31.4 * 3600),
    ("exilus_wf", "战甲特殊功能槽连接器", "解锁战甲特殊功能槽", "shield.fill", ["ExilusAdapter", "Exilus"], 94.0 * 3600),
    ("exilus_wp", "武器特殊功能槽连接器", "解锁武器特殊功能槽", "cross.circle.fill", ["WeaponExilus"], 98.2 * 3600),
    ("riven_sliver", "裂罅碎石 (Riven Sliver)", "兑换紫卡与精炼材料", "diamond.fill", ["RivenSliver", "碎石"], 42.0 * 3600),
    ("kavat_code", "库娃遗传密码 (5x)", "孵化猫甲与库娃基因", "pawprint.fill", ["KavatCode", "库娃"], 36.5 * 3600),
    ("nitain", "尼坦萃取物 (Nitain / 泥丸)", "特殊化学萃取物", "drop.fill", ["NitainExtract", "尼坦", "泥丸"], 120.0 * 3600),
    ("orokin_cell", "奥罗金电池 (3x)", "Prime 装备与战甲铸造消耗", "battery.100.bolt", ["OrokinCell", "奥罗金电池"], 22.5 * 3600),
    ("mutagen_mass", "突变原聚合物 (3x)", "道场生物实验室研发必备", "atom", ["Mutagen", "突变原"], 16.8 * 3600),
    ("fieldron", "电磁力导管 (3x)", "道场能源实验室研发必备", "bolt.fill", ["Fieldron", "电磁力导管", "电磁盒"], 14.2 * 3600),
    ("detonite", "爆燃喷射器 (3x)", "道场化学实验室研发必备", "flame.fill", ["Detonite", "爆燃喷射器", "爆燃安瓿"], 15.0 * 3600),
    
    # 亡魂与破坏者入侵武器部件 (全量展开)
    ("karak_wraith_bp", "卡拉卡·亡魂 蓝图", "Grineer 突击步枪亡魂版", "wrench.and.screwdriver", ["KarakWraithBlueprint"], 7 * 86400),
    ("karak_wraith_barrel", "卡拉卡·亡魂 枪管", "Grineer 突击步枪亡魂版部件", "wrench.and.screwdriver", ["KarakWraithBarrel"], 48 * 3600),
    ("karak_wraith_receiver", "卡拉卡·亡魂 机匣", "Grineer 突击步枪亡魂版部件", "wrench.and.screwdriver", ["KarakWraithReceiver"], 48 * 3600),
    ("karak_wraith_stock", "卡拉卡·亡魂 枪托", "Grineer 突击步枪亡魂版部件", "wrench.and.screwdriver", ["KarakWraithStock"], 48 * 3600),

    ("strun_wraith_bp", "斯特朗·亡魂 蓝图", "Grineer 散弹枪亡魂版", "wrench.and.screwdriver", ["StrunWraithBlueprint"], 7 * 86400),
    ("strun_wraith_barrel", "斯特朗·亡魂 枪管", "Grineer 散弹枪亡魂版部件", "wrench.and.screwdriver", ["StrunWraithBarrel"], 48 * 3600),
    ("strun_wraith_receiver", "斯特朗·亡魂 机匣", "Grineer 散弹枪亡魂版部件", "wrench.and.screwdriver", ["StrunWraithReceiver"], 48 * 3600),
    ("strun_wraith_stock", "斯特朗·亡魂 枪托", "Grineer 散弹枪亡魂版部件", "wrench.and.screwdriver", ["StrunWraithStock"], 48 * 3600),

    ("twin_vipers_wraith_bp", "双子蝰蛇·亡魂 蓝图", "Grineer 双持副手亡魂版", "wrench.and.screwdriver", ["TwinVipersWraithBlueprint"], 8 * 86400),
    ("twin_vipers_wraith_barrel", "双子蝰蛇·亡魂 枪管", "Grineer 双持副手部件", "wrench.and.screwdriver", ["TwinVipersWraithBarrel"], 52 * 3600),
    ("twin_vipers_wraith_receiver", "双子蝰蛇·亡魂 机匣", "Grineer 双持副手部件", "wrench.and.screwdriver", ["TwinVipersWraithReceiver"], 52 * 3600),
    ("twin_vipers_wraith_link", "双子蝰蛇·亡魂 联结器", "Grineer 双持副手部件", "wrench.and.screwdriver", ["TwinVipersWraithLink"], 52 * 3600),

    ("furax_wraith_bp", "弗拉克斯·亡魂 蓝图", "Grineer 拳套近战亡魂版", "wrench.and.screwdriver", ["FuraxWraithBlueprint"], 9 * 86400),
    ("furax_wraith_right", "弗拉克斯·亡魂 右手套", "Grineer 拳套近战部件", "wrench.and.screwdriver", ["FuraxWraithRightGauntlet"], 60 * 3600),
    ("furax_wraith_left", "弗拉克斯·亡魂 左手套", "Grineer 拳套近战部件", "wrench.and.screwdriver", ["FuraxWraithLeftGauntlet"], 60 * 3600),

    ("gorgon_wraith_bp", "蛇发女妖·亡魂 蓝图", "Grineer 重机枪亡魂版", "wrench.and.screwdriver", ["GorgonWraithBlueprint"], 10 * 86400),
    ("gorgon_wraith_barrel", "蛇发女妖·亡魂 枪管", "Grineer 重机枪部件", "wrench.and.screwdriver", ["GorgonWraithBarrel"], 64 * 3600),
    ("gorgon_wraith_receiver", "蛇发女妖·亡魂 机匣", "Grineer 重机枪部件", "wrench.and.screwdriver", ["GorgonWraithReceiver"], 64 * 3600),
    ("gorgon_wraith_stock", "蛇发女妖·亡魂 枪托", "Grineer 重机枪部件", "wrench.and.screwdriver", ["GorgonWraithStock"], 64 * 3600),

    ("sheev_bp", "希芙 (Sheev) 蓝图", "Grineer 特种短剑近战", "wrench.and.screwdriver", ["SheevBlueprint"], 12 * 86400),
    ("sheev_blade", "希芙 (Sheev) 刀刃", "Grineer 短剑部件", "wrench.and.screwdriver", ["SheevBlade"], 72 * 3600),
    ("sheev_hilt", "希芙 (Sheev) 刀柄", "Grineer 短剑部件", "wrench.and.screwdriver", ["SheevHilt"], 72 * 3600),
    ("sheev_heatsink", "希芙 (Sheev) 散热护座", "Grineer 短剑部件", "wrench.and.screwdriver", ["SheevHeatsink"], 72 * 3600),

    ("dera_vandal_bp", "德拉·破坏者 蓝图", "Corpus 能量步枪破坏者版", "wrench.and.screwdriver", ["DeraVandalBlueprint"], 7 * 86400),
    ("dera_vandal_barrel", "德拉·破坏者 枪管", "Corpus 能量步枪部件", "wrench.and.screwdriver", ["DeraVandalBarrel"], 48 * 3600),
    ("dera_vandal_receiver", "德拉·破坏者 机匣", "Corpus 能量步枪部件", "wrench.and.screwdriver", ["DeraVandalReceiver"], 48 * 3600),
    ("dera_vandal_stock", "德拉·破坏者 枪托", "Corpus 能量步枪部件", "wrench.and.screwdriver", ["DeraVandalStock"], 48 * 3600),

    ("snipetron_vandal_bp", "狙击特隆·破坏者 蓝图", "Corpus 狙击枪破坏者版", "wrench.and.screwdriver", ["SnipetronVandalBlueprint"], 7 * 86400),
    ("snipetron_vandal_barrel", "狙击特隆·破坏者 枪管", "Corpus 狙击枪部件", "wrench.and.screwdriver", ["SnipetronVandalBarrel"], 48 * 3600),
    ("snipetron_vandal_receiver", "狙击特隆·破坏者 机匣", "Corpus 狙击枪部件", "wrench.and.screwdriver", ["SnipetronVandalReceiver"], 48 * 3600),
    ("snipetron_vandal_stock", "狙击特隆·破坏者 枪托", "Corpus 狙击枪部件", "wrench.and.screwdriver", ["SnipetronVandalStock"], 48 * 3600),

    ("prova_vandal_bp", "普罗沃·破坏者 蓝图", "Corpus 电击棍破坏者版", "wrench.and.screwdriver", ["ProvaVandalBlueprint"], 9 * 86400),
    ("prova_vandal_blade", "普罗沃·破坏者 刀刃", "Corpus 电击棍部件", "wrench.and.screwdriver", ["ProvaVandalBlade"], 56 * 3600),
    ("prova_vandal_hilt", "普罗沃·破坏者 刀柄", "Corpus 电击棍部件", "wrench.and.screwdriver", ["ProvaVandalHilt"], 56 * 3600),

    ("quanta_vandal_bp", "量子切割器·破坏者 蓝图", "Corpus 重激光枪破坏者版", "wrench.and.screwdriver", ["QuantaVandalBlueprint"], 10 * 86400),
    ("quanta_vandal_barrel", "量子切割器·破坏者 枪管", "Corpus 重激光枪部件", "wrench.and.screwdriver", ["QuantaVandalBarrel"], 68 * 3600),
    ("quanta_vandal_receiver", "量子切割器·破坏者 机匣", "Corpus 重激光枪部件", "wrench.and.screwdriver", ["QuantaVandalReceiver"], 68 * 3600),

    # 警报专属光环与特种 MOD
    ("aura_steel_charge", "钢铁充能 (Steel Charge)", "战甲光环 · 近战伤害提升", "shield.lefthalf.filled", ["SteelCharge", "钢铁充能"], 72 * 3600),
    ("aura_energy_siphon", "能量虹吸 (Energy Siphon)", "战甲光环 · 全队持续能量回复", "bolt.shield", ["EnergySiphon", "能量虹吸"], 68 * 3600),
    ("aura_corrosive_projection", "腐蚀投射 (Corrosive Projection)", "战甲光环 · 削减全图敌方护甲", "shield.slash.fill", ["CorrosiveProjection", "腐蚀投射"], 65 * 3600),
    ("aura_dead_eye", "死亡之眼 (Dead Eye)", "战甲光环 · 增加狙击枪伤害", "scope", ["DeadEye", "死亡之眼"], 84 * 3600),
    ("aura_enemy_radar", "侦敌通报 (Enemy Radar)", "战甲光环 · 全队敌方雷达探测", "antenna.radiowaves.left.and.right", ["EnemyRadar", "侦敌通报"], 76 * 3600),
    ("aura_shield_disruption", "护盾瓦解 (Shield Disruption)", "战甲光环 · 削减敌方护盾上限", "shield.slash", ["ShieldDisruption", "护盾瓦解"], 80 * 3600),
    ("aura_speed_holster", "快速切换 (Speed Holster)", "战甲光环 · 武器切换速度提升", "arrow.triangle.swap", ["SpeedHolster", "快速切换"], 90 * 3600),
    ("aura_sprint_boost", "冲刺提升 (Sprint Boost)", "战甲光环 · 全队冲刺速度提升", "figure.run", ["SprintBoost", "冲刺提升"], 86 * 3600),
    ("aura_rifle_amp", "步枪增幅 (Rifle Amp)", "战甲光环 · 步枪主武器伤害提升", "cross.fill", ["RifleAmp", "步枪增幅"], 78 * 3600),
    ("aura_pistol_amp", "手枪增幅 (Pistol Amp)", "战甲光环 · 手枪副手伤害提升", "cross.fill", ["PistolAmp", "手枪增幅"], 82 * 3600),
    ("aura_shotgun_spree", "散弹枪增幅 (Shotgun Spree)", "战甲光环 · 散弹枪伤害提升", "cross.fill", ["ShotgunSpree", "散弹枪增幅"], 88 * 3600),
    ("aura_physique", "物理抗性 (Physique)", "战甲光环 · 全队生命上限提升", "heart.fill", ["Physique", "物理抗性"], 75 * 3600),
    ("aura_loot_detector", "战利品探测器 (Loot Detector)", "战甲光环 · 掉落物小地图标记", "magnifyingglass", ["LootDetector", "战利品探测器"], 74 * 3600),
    ("aura_rejuvenation", "返老还童 (Rejuvenation)", "战甲光环 · 全队持续生命回复", "heart.circle.fill", ["Rejuvenation", "返老还童"], 70 * 3600),
    ("aura_brief_respite", "强化护盾 (Brief Respite)", "战甲光环 · 消耗能量转化护盾", "shield.fill", ["BriefRespite", "强化护盾"], 105 * 3600),

    # 噩梦双属性 MOD
    ("mod_blaze", "烈焰 (Blaze)", "噩梦 MOD · 散弹枪基础伤害 + 火焰", "flame.circle.fill", ["Blaze", "烈焰"], 96 * 3600),
    ("mod_lethal_torrent", "致命洪流 (Lethal Torrent)", "噩梦 MOD · 手枪射速 + 多重射击", "burst.fill", ["LethalTorrent", "致命洪流"], 90 * 3600),
    ("mod_hammer_shot", "锤击 (Hammer Shot)", "噩梦 MOD · 步枪暴击伤害 + 触发几率", "hammer.fill", ["HammerShot", "锤击"], 100 * 3600),
    ("mod_animal_instinct", "动物本能 (Animal Instinct)", "噩梦 MOD · 同伴战利品与敌人双雷达", "pawprint", ["AnimalInstinct", "动物本能"], 80 * 3600)
]

for item_id, title, sub, icon, kws, interval in items_pool:
    catalog.append({
        "id": f"item_{item_id}",
        "section": "items",
        "title": title,
        "subtitle": sub,
        "icon": icon,
        "is_deterministic": False,
        "base_interval_seconds": interval,
        "meta": {
            "type": "item",
            "keywords": kws
        }
    })

# =========================================================================
# 5. 写入 CompleteCatalog.json 与 SQLite 数据库
# =========================================================================
with open(OUTPUT_JSON, 'w', encoding='utf-8') as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)

print(f"✅ 生成全量监控配置 CompleteCatalog.json 完成，共 {len(catalog)} 个独立监控项！")

# 写入 SQLite
conn = sqlite3.connect(DB_PATH)
c = conn.cursor()
c.execute("""
CREATE TABLE IF NOT EXISTS catalog_targets (
    id TEXT PRIMARY KEY,
    section TEXT,
    title TEXT,
    subtitle TEXT,
    icon TEXT,
    is_deterministic INTEGER,
    base_interval_seconds REAL,
    meta_json TEXT
)
""")
c.execute("DELETE FROM catalog_targets")
for item in catalog:
    c.execute("""
    INSERT INTO catalog_targets (id, section, title, subtitle, icon, is_deterministic, base_interval_seconds, meta_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        item["id"],
        item["section"],
        item["title"],
        item["subtitle"],
        item["icon"],
        1 if item["is_deterministic"] else 0,
        item["base_interval_seconds"],
        json.dumps(item["meta"], ensure_ascii=False)
    ))
conn.commit()
conn.close()
print(f"✅ 成功将 {len(catalog)} 个监控目标完整导入本地 SQLite 数据库！")
