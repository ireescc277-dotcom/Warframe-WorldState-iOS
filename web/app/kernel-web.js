/* 内核（浏览器版）
 *
 * 与 server/kernel.js 是同一套逻辑，区别只在宿主：
 *   Node 版用 jsdom 造一个 window，浏览器版用同源 iframe 装站点自己。
 * 差别是浏览器版更接近站点真实运行环境，且不需要任何服务端。
 *
 * 站点脚本要求的输入分三块，这里原样照搬：
 *   1. modsPanel[slot] = {name, actions, tags, uncomp, uncomptag, shard, info}
 *   2. 一批选项全局变量（is_headShot / externalVirus / strengthMult ...）
 *   3. 敌人用 showEnemy(name, steel) + correctEnemyLvl(lv) 缩放
 * 结果落在 currWeapon.info[攻击].queue_hp|queue_armor|queue_shield|queue_overguard。
 */
(function (global) {
  'use strict';

  var BASE = 'site/';
  var Q = ['dpsQueue', 'TTK_Queue', 'MedianTotal_Queue', 'TotalDmg_Queue'];
  // 生命层的字段名是 queue_hp，不是 queue_health —— 后者不存在。
  var FIELD = { health: 'queue_hp', armor: 'queue_armor', shield: 'queue_shield', overguard: 'queue_overguard' };

  var W = null;            // iframe 的 window（常驻）
  var frame = null;
  var booting = null;
  var loadedWeapon = null;
  var MANIFEST = null;
  var ENEMIES = null;
  // 构建期预生成的武器索引（site/weapon-index.js，由主页面 script 标签载入）
  var WINDEX = global.__WF_WEAPON_INDEX || {};

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  // ---------------------------------------------------------------- 启动

  function boot() {
    if (booting) return booting;
    booting = (async function () {
      // iOS 包内加载时 fetch 不可用（WFK 走 wfapp:// 自定义 scheme，Fetch API
      // 只认 http/https），数据由 site/data-bundle.js 预注入到 window。
      var inline = global.__WF_INLINE;
      if (inline) {
        MANIFEST = inline.map;
        ENEMIES = inline.enemies;
      } else {
        var pair = await Promise.all([
          fetch(BASE + 'weapons.json').then(function (r) { return r.json(); }),
          fetch(BASE + 'data/json/enemies-min.json').then(function (r) { return r.json(); })
        ]);
        MANIFEST = pair[0];
        ENEMIES = pair[1];
      }

      var t0 = performance.now();
      frame = document.createElement('iframe');
      frame.id = 'wf-kernel';
      frame.setAttribute('aria-hidden', 'true');
      frame.setAttribute('tabindex', '-1');
      frame.style.cssText = 'position:fixed;left:-10000px;top:0;width:1px;height:1px;border:0;opacity:0;pointer-events:none';

      var loaded = new Promise(function (res, rej) {
        frame.onload = res;
        frame.onerror = function () { rej(new Error('内核页面加载失败')); };
      });
      frame.src = BASE + 'index.html';
      document.body.appendChild(frame);
      await loaded;

      var w = frame.contentWindow;
      // defer 脚本在 load 之前已执行完；这里再等一小会儿兜住慢设备
      for (var i = 0; i < 200 && typeof w.reCalc !== 'function'; i++) await sleep(25);
      if (typeof w.reCalc !== 'function' || !w.modsProps) {
        throw new Error('内核未就绪（站点脚本未执行完）');
      }

      // 站点把整份配置压进 URL；记下来可以对拍，也避免 iframe 跳走
      w.setLocation = function (a) { w.__lastUrl = String(a); };
      W = w;
      W.__bootMs = Math.round(performance.now() - t0);
      return W;
    })();
    booting.catch(function (e) {
      booting = null;
      // iOS 上出问题看不到控制台，把原因留给外层读
      global.__wfErr = String((e && e.message) || e);
    });
    return booting;
  }

  // ---------------------------------------------------------------- 武器 / 敌人

  async function setWeapon(name) {
    if (!MANIFEST[name]) throw new Error('未知武器: ' + name);
    if (loadedWeapon === name) return;
    var p = W.showWeapon(name);
    if (p && typeof p.then === 'function') await p;
    for (var i = 0; i < 150 && (!W.currWeapon || W.currWeapon.name !== name); i++) await sleep(20);
    if (!W.currWeapon || W.currWeapon.name !== name) throw new Error('载入武器失败: ' + name);
    loadedWeapon = name;
    clearMods();
  }

  function clearMods() {
    var mp = W.modsPanel;
    for (var k in mp) mp[k] = 0;
    W.invalidateModStatsCache();
  }

  function setEnemy(name, steel, level, eximus, party) {
    var hit = ENEMIES.find(function (e) { return e.name === name; });
    if (!hit) throw new Error('未知敌人: ' + name);
    W.currEnemyLvl = W.currEnemyLvl || 1;
    W.showEnemy(name, !!steel);
    var lv = Math.max(1, Math.min(9999, Number(level) || 1));
    W.currEnemyLvl = lv;
    try { W.currEnemySPStatus = !!steel; } catch (e) {}
    W.$('#setEnemyLvl').val(String(lv));
    // 有些敌人（爆破型等）没有卓越者形态，站点连勾选框都不渲染
    var ex = hit.eximusOff ? false : !!eximus;
    W.currEnemyEximusStatus = ex;
    W.$('#eEximus').prop('checked', ex);
    // 队伍人数只对 showPartyCount 的敌人有意义
    var pv = W.$('#eParty');
    if (pv.length) pv.val(String(Math.max(1, Math.min(4, Number(party) || 1))));
    if (typeof W.correctEnemyLvl === 'function') W.correctEnemyLvl(lv);
  }

  // ---------------------------------------------------------------- mod

  function modInfo(name) {
    return W.modsProps.find(function (m) { return m.name === name; }) || null;
  }

  // 站点装 mod 就是往 modsPanel 里塞这个形状，showMod() 里逐字抄的。
  function putMod(slot, name) {
    var f = modInfo(name);
    if (!f) return false;
    var cell = {
      name: f.name,
      actions: JSON.parse(JSON.stringify(f.action)),
      tags: f.tags,
      uncomp: f.uncomp,
      uncomptag: f.uncomptag,
      shard: f.shardType,
      info: f.info || ''
    };
    if (f.set) cell.set = f.set;
    W.modsPanel[slot] = cell;
    return true;
  }

  function applyMods(mods, riven) {
    clearMods();
    var lost = [];
    var keys = Object.keys(mods || {});
    for (var i = 0; i < keys.length; i++) {
      var slot = keys[i];
      var name = mods[slot];
      if (!name) continue;
      if (name === 'Riven') {
        if (!putRiven(Number(slot), riven)) lost.push({ slot: Number(slot), name: name });
        continue;
      }
      if (!putMod(Number(slot), name)) lost.push({ slot: Number(slot), name: name });
    }
    W.invalidateModStatsCache();
    return lost;
  }

  // ---------------------------------------------------------------- 自定义属性
  //
  // 站点的 26 项面板外加成，写进 customStats，由 getCustomStat() 在各处读取。
  // pct=1 的项界面按百分比填、内部存小数；pct=0 的项原值。

  var CUSTOM_ATTR = [
    { k: 'base', n: 'Base Damage', l: '基础伤害', pct: 1 },
    { k: 'base_per_status', n: 'Base Damage per Status Effect', l: '每层状态的基础伤害', pct: 1 },
    { k: 'flat_change_dmg', n: 'Increase Base Damage (flat)', l: '固定加算基础伤害', pct: 0 },
    { k: 'abilityCombo', n: 'Combo Ability Multiplier', l: '技能连击倍率', pct: 0 },
    { k: 'crit_chance', n: 'Critical Chance', l: '暴击率', pct: 1 },
    { k: 'mult_crit_chance', n: 'Critical Chance (multiplicative)', l: '暴击率（乘算）', pct: 1 },
    { k: 'flat_crit_chance', n: 'Critical Chance (absolute)', l: '暴击率（绝对加成）', pct: 1 },
    { k: 'crit_chance_weakp', n: 'Weak Point Critical Chance', l: '弱点暴击率', pct: 1 },
    { k: 'crit_mult', n: 'Critical Multiplier', l: '暴击倍率', pct: 1 },
    { k: 'crit_mult_add', n: 'Critical Multiplier (absolute)', l: '暴击倍率（绝对加成）', pct: 0 },
    { k: 'crit_mult_mult', n: 'Critical Multiplier (final ×)', l: '暴击倍率（最终乘算）', pct: 0 },
    { k: 'status_chance', n: 'Status Chance', l: '触发几率', pct: 1 },
    { k: 'status_chance_mult', n: 'Vulnerable to Status Chance', l: '触发几率易伤', pct: 1 },
    { k: 'absolute_status_chance', n: 'Status Chance (absolute)', l: '触发几率（绝对加成）', pct: 0 },
    { k: 'status_damage', n: 'Status Damage', l: '状态伤害', pct: 1 },
    { k: 'vuln_status_damage', n: 'Vulnerability Status Damage', l: '易伤状态伤害', pct: 1 },
    { k: 'speed', n: 'Fire Rate / Attack Speed', l: '射速 / 攻速', pct: 1 },
    { k: 'multishot', n: 'Multishot', l: '多重', pct: 0 },
    { k: 'magazineSize', n: 'Magazine Size', l: '弹匣容量', pct: 1 },
    { k: 'reloadTime', n: 'Reload Time', l: '装填速度', pct: 1 },
    { k: 'mult_for_head', n: 'Headshot Damage', l: '爆头伤害', pct: 1 },
    { k: 'headshot_mult', n: 'Weak Point Damage', l: '弱点伤害', pct: 1 },
    { k: 'initialCombo', n: 'Initial Combo', l: '初始连击', pct: 0 },
    { k: 'dmgVulnerability', n: 'Damage Vulnerability', l: '伤害易伤', pct: 1 },
    { k: 'heatInherit', n: 'Heat Inherit', l: '火焰继承', pct: 1 },
    { k: 'heatAdd', n: 'Add Heat Instance', l: '附加火焰实例', pct: 1 }
  ];

  function applyCustom(list) {
    var cs = W.customStats || (W.customStats = {});
    for (var k in cs) delete cs[k];
    var out = {};
    var arr = list || [];
    for (var i = 0; i < arr.length; i++) {
      var it = arr[i];
      var meta = CUSTOM_ATTR.find(function (a) { return a.k === it.k; });
      var v = Number(it.v);
      if (!meta || !isFinite(v) || v === 0) continue;
      W.setCustomStat(it.k, meta.pct ? v / 100 : v);
      out[it.k] = v;
    }
    return out;
  }

  // ---------------------------------------------------------------- 紫卡
  //
  // 站点不把紫卡放在 modsProps 里：它是弹窗临时构造的 modsProps[9999]，
  // 由 showRiven() 从 #rivenSettings 的四个输入块读出来。

  var RIVEN_ATTR = {
    crit_chance: { name: 'Critical Chance' },
    crit_mult: { name: 'Critical Multiplier' },
    multishot: { name: 'Multishot' },
    status_chance: { name: 'Status Chance' },
    base: { name: 'Damage' },
    speed: { name: 'Fire Rate / Attack Speed' },
    Cold: { name: 'Cold', addt: 'element' },
    Heat: { name: 'Heat', addt: 'element' },
    Electricity: { name: 'Electricity', addt: 'element' },
    Toxin: { name: 'Toxin', addt: 'element' },
    Impact: { name: 'Impact', addt: 'phys' },
    Puncture: { name: 'Puncture', addt: 'phys' },
    Slash: { name: 'Slash', addt: 'phys' },
    addViral: { name: 'Viral' },
    addBlast: { name: 'Blast' },
    addGas: { name: 'Gas' },
    addMagnetic: { name: 'Magnetic' },
    addRadiation: { name: 'Radiation' },
    addCorrosive: { name: 'Corrosive' },
    status_damage: { name: 'Status Damage' },
    Corpus: { name: 'Damage to Corpus', addt: 'SMITE' },
    Grineer: { name: 'Damage to Grineer', addt: 'SMITE' },
    Infested: { name: 'Damage to Infested', addt: 'SMITE' },
    Scaldra: { name: 'Damage to Scaldra', addt: 'SMITE' },
    Techrot: { name: 'Damage to Techrot', addt: 'SMITE' },
    crit_chance_weakp: { name: 'Weak Point Critical Chance', addt: 'SMITE' },
    ammoCapacity: { name: 'Ammo Maximum' },
    ammoEff: { name: 'Ammo Efficiency' },
    mult_for_head: { name: 'Weak Point Damage' },
    magazineSize: { name: 'Magazine Capacity' },
    reloadTime: { name: 'Reload Speed' },
    shot_speed: { name: 'Shot Speed' },
    comboDuration: { name: 'Combo Duration' },
    initialCombo: { name: 'Initial Combo' },
    melee_combo_eff: { name: 'Heavy Attack Efficiency' },
    range: { name: 'Range' },
    punch_through: { name: 'Punch Through' },
    zoom: { name: 'Zoom' },
    recoil: { name: 'Weapon Recoil' },
    status_duration: { name: 'Status Duration' }
  };

  // 近战与远程可选属性不同，站点是按 productCategory 删表实现的
  var RIVEN_DROP_MELEE = ['punch_through', 'shot_speed', 'reloadTime', 'magazineSize', 'ammoCapacity', 'multishot', 'ammoEff'];
  var RIVEN_DROP_RANGED = ['range', 'melee_combo_eff', 'initialCombo', 'comboDuration'];

  function rivenAttrs(melee) {
    if (melee == null) melee = (W.currWeaponInitial || W.currWeapon || {}).productCategory === 'Melee';
    var drop = melee ? RIVEN_DROP_MELEE : RIVEN_DROP_RANGED;
    return Object.keys(RIVEN_ATTR)
      .filter(function (k) { return drop.indexOf(k) === -1; })
      .map(function (k) {
        return {
          k: k, n: RIVEN_ATTR[k].name, l: loc(RIVEN_ATTR[k].name), g: RIVEN_ATTR[k].addt || 'misc',
          // 站点 showRiven 对这三类做不同换算：原值 / 减 1 / 除 100
          u: ['Corpus', 'Grineer', 'Infested', 'Scaldra', 'Techrot'].indexOf(k) > -1 ? 'x'
            : ['comboDuration', 'initialCombo', 'range', 'punch_through'].indexOf(k) > -1 ? 's' : '%'
        };
      });
  }

  // props: [{p:'crit_chance', v:60}, ...] 最多四条，v 是用户填的原始数字
  function setRiven(props) {
    var list = (props || []).filter(function (x) {
      return x && x.p && RIVEN_ATTR[x.p] && Number(x.v);
    }).slice(0, 4);
    var blocks = W.$('#rivenSettings').find('.rivenSettingsInputBlock');
    blocks.each(function (i, el) {
      var box = W.$(el);
      var inp = box.find('.customDropdownInput');
      var val = box.find('.rivenSettingsIAVal');
      var it = list[i];
      if (!it) {
        inp.attr('data-type', '').attr('data-addt', '').text('Select property').data('type', '').data('addt', '');
        val.val('');
        return;
      }
      var meta = RIVEN_ATTR[it.p];
      inp.attr('data-type', it.p).attr('data-addt', meta.addt || '')
        .data('type', it.p).data('addt', meta.addt || '').text(meta.name);
      val.val(String(Number(it.v)));
    });
    W.showRiven();
    var rv = W.modsProps[9999];
    if (!rv || !rv.action || !Object.keys(rv.action).length) return null;
    return rv;
  }

  function putRiven(slot, props) {
    var rv = setRiven(props);
    if (!rv) return false;
    W.modsPanel[slot] = {
      name: 'Riven',
      actions: JSON.parse(JSON.stringify(rv.action)),
      tags: rv.tags,
      info: ''
    };
    W.invalidateModStatsCache();
    return true;
  }

  // 架势槽是 9。装了架势后，站点的连段命中表存在 actions.stances 里，
  // 由 #stanceAttackList 当前选中项决定每次 10 秒窗口打几下。
  function stanceList() {
    var cell = W.modsPanel[9];
    if (!cell || !cell.actions || !cell.actions.stances) return [];
    return Object.keys(cell.actions.stances);
  }

  function setStance(name) {
    var names = stanceList();
    var box = W.$('#stanceAttackList');
    box.empty();
    if (!names.length) return null;
    for (var i = 0; i < names.length; i++) {
      box.append(W.$('<option>').attr('data-name', names[i]).text(names[i]));
    }
    var pick = names.indexOf(name) > -1 ? name : names[0];
    box[0].selectedIndex = names.indexOf(pick);
    W.__wfoptStanceCombo = pick;
    return pick;
  }

  // ---------------------------------------------------------------- 选项

  // {is_set, val} 形状的开关
  function flag(v, key) {
    if (v == null || v === false) return null;
    if (v === true) return { is_set: true };
    if (typeof v === 'object') return v;
    return { is_set: true, val: Number(v) };
  }

  function applyOpts(o) {
    o = o || {};
    var w = W;

    // 强度：站点存的是倍数，输入框是百分比（100 → 1）
    var st = Number(o.strength);
    w.strengthMult = isFinite(st) && st > 0 ? st / 100 : 1;

    w.is_headShot = !!o.headshot;
    w.stealthBonus = !!o.stealth;
    w.isMaxCond = o.allConds !== false;          // 站点默认勾上
    w.is_Heavy = !!o.heavy;
    w.is_MultiplicativeBasePerStatus = !!o.perStatusMul;
    w.is_MultiplicativeWeakCC = !!o.weakCC;

    w.externalVirus = o.virus
      ? { is_set: !!o.virus.on, stucks: Math.max(0, Math.min(10, Number(o.virus.stacks) || 0)) }
      : { is_set: false, stucks: 0 };

    w.rhinoBuff = flag(o.rhino) || { is_set: false, val: 0 };
    w.mirageBuff = flag(o.mirage) || { is_set: false, val: 0 };
    w.hakuXata = flag(o.xata) || { is_set: false, val: 0 };
    w.toxicLash = flag(o.tlash) || { is_set: false, val: 0 };
    w.nourishBuff = flag(o.nourish) || { is_set: false, val: 0 };
    w.optFlatCrit = flag(o.flatCrit) || { is_set: false, val: 0 };
    w.decreaseArmorOpt = flag(o.armor) || { is_set: false, val: 0 };
    w.manualCountOfStatuses = flag(o.statusCount) || { is_set: false, val: 0 };
    w.optMadurai = { is_set: !!o.madurai };

    // 近战连击 / 重击起始 / 能力连击 / 狙击连击
    // 注意 comboСounter 里的 С 是 U+0421（站点源码即如此），不能用英文 C
    if (o.meleeCombo != null) w['combo\u0421ounterVal'] = Number(o.meleeCombo);
    if (o.heavyStart != null) {
      w.combo_counterInitial = Number(o.heavyStart);
      try { w['combo\u0421ounterSettingsVal'] = Number(o.heavyStart); } catch (e) {}
    }
    w['abilityCombo\u0421ounterSettings'] = o.abilityCombo != null
      ? { is_set: true, val: Number(o.abilityCombo) }
      : { is_set: false, val: 12 };
    w['sniperCombo\u0421ounterSettings'] = o.sniperCombo != null
      ? { is_set: true, val: Number(o.sniperCombo) }
      : { is_set: false, val: 1.5 };

    if (o.queueLength != null) {
      w.queueLength = Math.max(1, Math.min(60, Number(o.queueLength) || 20));
      w.$('#queueLen').val(String(w.queueLength));
    }

    // DOM 上的勾选状态，reCalc 有几处直接读它
    w.$('#optDecreaseArmor').prop('checked', !!w.decreaseArmorOpt.is_set);
    w.$('#optDecreaseArmorVal').val(String(w.decreaseArmorOpt.val || 0));
    w.$('#optCountStatusOnEnemy').prop('checked', !!w.manualCountOfStatuses.is_set);
    w.$('#optCountStatusOnEnemyPc').val(String(w.manualCountOfStatuses.val || 0));
    w.$('#optVirus').prop('checked', !!w.externalVirus.is_set);
    w.$('#optVirusStacks').val(String(w.externalVirus.stucks || 0));
  }

  // ---------------------------------------------------------------- 计算

  function collect() {
    var w = W;
    var out = [];
    var info = (w.currWeapon && w.currWeapon.info) || {};
    var names = Object.keys(info);
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      var it = info[name] || {};
      var row = { name: name, l: loc(name), dps: {}, ttk: {}, total: {} };
      var ds = ['health', 'armor', 'shield', 'overguard'];
      for (var j = 0; j < ds.length; j++) {
        var d = ds[j];
        var v = it[FIELD[d]];
        if (v != null && isFinite(v) && v > 0) row.dps[d] = Math.round(v);
        var t = w.TTK_Queue[name] && w.TTK_Queue[name][d];
        if (t && t.length && t[t.length - 1] != null) row.ttk[d] = t[t.length - 1];
        var m = w.MedianTotal_Queue[name] && w.MedianTotal_Queue[name][d];
        if (m && m.length && m[m.length - 1] != null) row.total[d] = m[m.length - 1];
      }
      if (!Object.keys(row.dps).length) continue;
      out.push(row);
    }
    return out;
  }

  async function calc(req) {
    // 站点把连击计数、触发计时、逐发队列这些状态挂在闭包与 DOM 上，跨计算残留。
    // 在真浏览器里它们会让同一配置反复算出 ±80% 的跳变，jsdom 里因为不跑计时器看不出来。
    // 这些状态无法从外部精确重置，所以每次计算重建内核环境——等于每次都从干净页面算。
    if (frame) {
      frame.remove();
      frame = null;
    }
    W = null;
    booting = null;
    loadedWeapon = null;
    modCache = null;

    await boot();
    await setWeapon(req.weapon);
    setEnemy(req.enemy, req.steel, req.level, req.eximus, req.party);

    var lost = applyMods(req.mods, req.riven);
    applyOpts(req.opts);
    applyCustom(req.custom);
    W.invalidateModStatsCache();

    // 近战：架势决定连段命中数，必须在 reCalc 之前选好。
    var stances = stanceList();
    var stance = stances.length ? setStance(req.stance) : null;

    // 结果队列是累加的，算之前清空。
    for (var q = 0; q < Q.length; q++) W[Q[q]] = {};

    var t0 = performance.now();
    W.reCalc();
    var ms = Math.round(performance.now() - t0);

    return {
      weapon: W.currWeapon.name,
      enemy: W.currEnemy.name,
      level: W.currEnemyLvl,
      steel: !!W.currEnemySPStatus,
      eximus: !!W.currEnemyEximusStatus,
      party: (W.$('#eParty').length ? Number(W.$('#eParty').val()) : 1) || 1,
      queueLen: W.queueLength,
      stances: stances,
      stance: stance,
      ms: ms,
      target: {
        hp: W.currEnemy.currHealth, ar: W.currEnemy.currArmor,
        sh: W.currEnemy.currShield, og: W.currEnemy.currOverguard,
        base: {
          hp: W.currEnemy.health && W.currEnemy.health.val,
          ar: W.currEnemy.armor && W.currEnemy.armor.val,
          sh: W.currEnemy.shield && W.currEnemy.shield.val
        },
        fac: (W.typeOfFaction && W.typeOfFaction[W.currEnemy.faction]) || null
      },
      attacks: collect(),
      lostMods: lost
    };
  }

  // ---------------------------------------------------------------- mod 槽位
  //
  // 站点的槽位语义（data-id），与 server/api.js 一致：
  //   0-7   八个主槽    8 exilus   9 stance   10 武器赋能
  //   11-12 战甲赋能    13-16 战甲 mod   17 aura   23-27 执政官碎片
  var SLOT_KIND = {
    0: 'main', 1: 'main', 2: 'main', 3: 'main', 4: 'main', 5: 'main', 6: 'main', 7: 'main',
    8: 'exilus', 9: 'stance', 10: 'arcane',
    11: 'frameArcane', 12: 'frameArcane',
    13: 'frame', 14: 'frame', 15: 'frame', 16: 'frame',
    17: 'aura',
    23: 'shard', 24: 'shard', 25: 'shard', 26: 'shard', 27: 'shard'
  };

  function hasAny(arr, vs) {
    return Array.isArray(arr) && vs.some(function (v) { return arr.indexOf(v) > -1; });
  }

  // 战甲类 mod 的 tags 有两种含义：武器类别（primary/melee…）或战甲名（BARUUK）。
  // 前者按当前武器筛，后者不筛。
  function tagOk(m, w) {
    var t = m.tags || [];
    if (!t.length) return true;
    return hasAny(w.categories, t);
  }

  function modsFor(weaponName, slot) {
    var w = WINDEX[weaponName];
    if (!w) return [];
    var kind = SLOT_KIND[slot] || 'main';
    var all = W.modsProps;
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var m = all[i];
      if (m.name === 'Riven') continue;   // 紫卡不在列表里，由弹窗单独构造
      var t = m.type || '';
      var ok = false;
      if (kind === 'main') {
        ok = ['exilus', 'stance', 'weapon_mist', 'frame_mist', 'aura', 'shard'].indexOf(t) === -1 &&
             hasAny(w.categories, m.tags);
      } else if (kind === 'exilus') {
        ok = t === 'exilus' && hasAny(w.categories, m.tags);
      } else if (kind === 'stance') {
        ok = t === 'stance' && hasAny(w.compTags, m.tags);
      } else if (kind === 'arcane') {
        ok = t === 'weapon_mist' && hasAny(w.categories, m.tags);
      } else if (kind === 'frameArcane') {
        ok = t === 'frame_mist' && tagOk(m, w);
      } else if (kind === 'frame') {
        ok = t === 'frame_mod';
      } else if (kind === 'aura') {
        ok = t === 'aura_mod' && tagOk(m, w);
      } else if (kind === 'shard') {
        ok = t === 'shard' && tagOk(m, w);
      }
      if (!ok) continue;
      out.push({
        n: m.name,
        l: loc(m.name),
        t: t,
        tags: m.tags,
        info: m.info || '',
        img: m.img,
        set: m.set || null,
        shard: m.shardType || null,
        act: m.action
      });
    }
    return out;
  }

  // ---------------------------------------------------------------- 列表

  // 站点用 localeLang 做显示名，内部 name 始终是英文；计算只认 name。
  function loc(name) {
    var m = (W && W.localeLang) || {};
    return m[name] || name;
  }

  // 启动时一次拿全：武器索引 + 敌人 + 中文名
  async function meta() {
    await boot();
    return {
      weapons: Object.keys(WINDEX).map(function (n) {
        var w = WINDEX[n];
        return {
          n: n, l: loc(n), cat: w.category, atk: w.attacks, tags: w.tags,
          inc: w.incarnon, mr: w.masteryReq, img: w.imageName
        };
      }),
      enemies: await enemies(),
      modCount: W.modsProps.length
    };
  }

  async function weapons() {
    await boot();
    return Object.keys(MANIFEST).sort();
  }

  async function enemies() {
    await boot();
    return ENEMIES.map(function (e) {
      return {
        name: e.name, l: loc(e.name), faction: e.faction, faction_l: loc(e.faction),
        party: !!e.showPartyCount, eximusOff: !!e.eximusOff,
        hp: e.health ? Number(e.health.val) : 0,
        ar: e.armor ? Number(e.armor.val) : 0,
        sh: e.shield ? Number(e.shield.val) : 0
      };
    });
  }

  var modCache = null;
  async function mods() {
    await boot();
    if (modCache) return modCache;
    modCache = W.modsProps.map(function (m) {
      return {
        name: m.name,
        l: loc(m.name),
        img: m.img,
        tags: m.tags || [],
        type: m.type || '',
        info: m.info || '',
        set: m.set || null,
        shard: m.shardType || null
      };
    });
    return modCache;
  }

  // 武器基础信息（伤害/暴击/射速/攻击段数），展示用
  async function weaponInfo(name) {
    await boot();
    var f = MANIFEST && MANIFEST[name];
    if (!f) return null;
    var j;
    var inline = global.__WF_INLINE;
    if (inline && inline.weapons && inline.weapons[name]) {
      j = JSON.parse(JSON.stringify(inline.weapons[name]));
    } else {
      var r = await fetch(BASE + 'weapons/' + encodeURIComponent(f));
      j = await r.json();
    }
    j.name = name;
    j.index = WINDEX[name] || null;
    return j;
  }

  global.WFK = {
    boot: boot,
    calc: calc,
    meta: meta,
    weapons: weapons,
    enemies: enemies,
    mods: mods,
    modsFor: modsFor,
    weaponInfo: weaponInfo,
    rivenAttrs: rivenAttrs,
    customAttrs: function () {
      return CUSTOM_ATTR.map(function (a) { return { k: a.k, n: a.n, l: a.l, pct: a.pct }; });
    },
    loc: loc,
    get W() { return W; }
  };
})(window);
