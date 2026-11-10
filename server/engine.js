'use strict';
// DPS 计算内核（服务端运行，无 DOM 依赖）。
// 从 web/dps/index.html 原样搬出，只把全局 WF 换成构造参数 DB，
// 保证浏览器版与服务器版跑的是同一套公式。
function makeEngine(DB) {
const W = DB.w, M = DB.m, E = DB.e;

const DT = ["impact","puncture","slash","heat","cold","electricity","toxin",
            "blast","radiation","magnetic","viral","corrosive","gas"];
const ZH = {impact:"冲击",puncture:"穿刺",slash:"切割",heat:"火焰",cold:"冰冻",
  electricity:"电击",toxin:"毒素",blast:"爆炸",radiation:"辐射",magnetic:"磁力",
  viral:"病毒",corrosive:"腐蚀",gas:"毒气"};
const COL = {impact:"#9aa3ad",puncture:"#b98c5a",slash:"#c0504d",heat:"#e07a3f",
  cold:"#5fa8d3",electricity:"#8a6fd0",toxin:"#5aa06a",blast:"#c96f4a",
  radiation:"#c9c04a",magnetic:"#7f8fd0",viral:"#8fbf6a",corrosive:"#8fae4a",gas:"#7fae7f"};
const PHYS = new Set(["impact","puncture","slash"]);
const ELEM_ORDER = ["heat","cold","electricity","toxin"];
const ALLELEM = ["heat","cold","electricity","toxin","blast","radiation","magnetic","viral","corrosive","gas"];
const COMBO_OF = {"heat|cold":"blast","heat|electricity":"radiation","heat|toxin":"gas",
  "cold|electricity":"magnetic","cold|toxin":"viral","electricity|toxin":"corrosive"};

// ---------------------------------------------------------------- 阵营克制
// Update 36（2024-06-18）起血量/护甲/护盾类型合并，克制只按阵营查：
// 弱点 ×1.5、抗性 ×0.5。来源：Warframe Wiki 伤害总览表 + warframe.today（2026-09 复核）。
const FACMOD = {
  "Grineer":        {impact:1.5, corrosive:1.5},
  "Kuva Grineer":   {impact:1.5, corrosive:1.5, heat:0.5},
  "Corpus":         {puncture:1.5, magnetic:1.5},
  "Corpus Amalgam": {electricity:1.5, magnetic:1.5, blast:0.5},
  "Infested":       {slash:1.5, heat:1.5},
  "Infested Deimos":{blast:1.5, gas:1.5, viral:0.5},
  "Orokin":         {puncture:1.5, viral:1.5, radiation:0.5},
  "Sentient":       {cold:1.5, radiation:1.5, corrosive:0.5},
  "Narmer":         {slash:1.5, toxin:1.5, magnetic:0.5},
  "Murmur":         {electricity:1.5, radiation:1.5, viral:0.5},
  "Scaldra":        {impact:1.5, corrosive:1.5},
  "Techrot":        {magnetic:1.5, gas:1.5, cold:0.5},
  "Zariman":        {void:1.5}
};
function facMult(fk, t){ const m = FACMOD[fk]; return (m && m[t]) || 1; }

// ---------------------------------------------------------------- 状态效果
// 数值来源：Warframe Wiki / warframe.today / sanctumaeterna，2026-09 口径。
const ST = {
  viral:    {max:10, dur:6,  hp:[1.00, 0.25]},   // 首层 +100%，每层 +25%，10 层 +325%
  corrosive:{max:10, dur:8,  strip:0.26, cap:0.80},
  heat:     {dur:6, dot:0.50, strip:0.50},       // 燃烧：护甲上限 −50%
  slash:    {dur:6, dot:0.35},                   // 流血：35% 总伤/秒，无视护甲
  toxin:    {dur:6, dot:0.50}                    // 中毒：50% 毒素伤/秒，无视护盾
};

const CATT = {LongGuns:"PRIMARY",Pistols:"SECONDARY",Melee:"MELEE",
  SentinelWeapons:"SENTINEL",SpaceGuns:"ARCH-GUN",SpaceMelee:"ARCH-MELEE"};

// ---------------------------------------------------------------- 统计
function statVal(m, lv, k){
  const L = m.lv; if(!L || !L.length) return 0;
  const i = Math.max(0, Math.min(lv, L.length-1));
  const row = L[i]; if(!row) return 0;
  return row[k] || 0;
}
function aggregate(slots){
  const a = {dmg:0,cc:0,cd:0,ms:0,fr:0,sc:0,mag:0,rl:0,
             phys:{},elem:{},fac:{},bad:[]};
  for(const s of slots){
    if(!s) continue;
    const m = M[s.m];
    if(!m){ a.bad.push((s.m.split("/").pop()||"")); continue; }
    a.dmg += statVal(m,s.lv,"dmg");
    a.cc  += statVal(m,s.lv,"cc");
    a.cd  += statVal(m,s.lv,"cd");
    a.ms  += statVal(m,s.lv,"ms");
    a.fr  += statVal(m,s.lv,"fr");
    a.sc  += statVal(m,s.lv,"sc");
    a.mag += statVal(m,s.lv,"mag");
    a.rl  += statVal(m,s.lv,"rl");
    for(const t of ["impact","puncture","slash"]){
      const v = statVal(m,s.lv,t); if(v) a.phys[t]=(a.phys[t]||0)+v;
    }
    for(const t of ALLELEM){
      const v = statVal(m,s.lv,t); if(v) a.elem[t]=(a.elem[t]||0)+v;
    }
    for(const f of ["d_grineer","d_corpus","d_infested","d_corrupted","d_narmer","d_murmur","d_sentient"]){
      const v = statVal(m,s.lv,f); if(v) a.fac[f.slice(2)]=(a.fac[f.slice(2)]||0)+v;
    }
  }
  return a;
}

// 元素合流：先天元素排最前，之后按槽位顺序
function buildComponents(wp, a, slotOrder){
  const baseTotal0 = DT.reduce((s,t)=>s+(wp.dmg[DT.indexOf(t)]||0),0) || wp.td || 1;
  const dMul = 1 + a.dmg/100;
  const phys = [];
  for(const t of PHYS){
    let v = (wp.dmg[DT.indexOf(t)]||0) * dMul;
    if(a.phys[t]) v *= (1 + a.phys[t]/100);
    if(v > 0) phys.push({t,v,innate:true});
  }
  const q = [];
  for(const t of ELEM_ORDER){
    const v = (wp.dmg[DT.indexOf(t)]||0) * dMul;
    if(v > 0) q.push({t,v,innate:true});
  }
  for(const t of ["blast","radiation","magnetic","viral","corrosive","gas"]){
    const v = (wp.dmg[DT.indexOf(t)]||0) * dMul;
    if(v > 0) q.push({t,v,innate:true,combo:true});
  }
  for(const t of slotOrder){
    if(a.elem[t]) q.push({t, v: baseTotal0 * dMul * a.elem[t]/100, innate:false});
  }
  const out = [];
  let pend = null;
  for(const e of q){
    if(e.combo){ if(pend){ out.push(pend); pend=null; } out.push(e); continue; }
    if(!pend){ pend = {...e}; continue; }
    if(pend.t === e.t){ pend.v += e.v; continue; }
    const c = COMBO_OF[pend.t+"|"+e.t] || COMBO_OF[e.t+"|"+pend.t];
    if(c){ out.push({t:c, v: pend.v + e.v, innate: pend.innate&&e.innate}); pend=null; }
    else { out.push(pend); pend = {...e}; }
  }
  if(pend) out.push(pend);
  return phys.concat(out);
}

// ---------------------------------------------------------------- 等级缩放
// 每条曲线两端点 + smoothstep（L=70,U=80）。系数按阵营分叉，
// 取自 Wiki「Enemy Level Scaling」并与 warframe-damage.com 的实现逐项对齐。
// 每条曲线记作 [c1,e1,c2,e2]：f1=1+c1·q^e1，f2=1+c2·q^e2。
const SCALES = {
  _h: [0.015, 2.12, 10.7332, 0.72],
  _s: [0.02, 1.76, 2, 0.76],
  _a: [0.005, 1.75, 0.4, 0.75],
  "Infested":        {h:[0.0225,2.12,16.1,0.72]},
  "Infested Deimos": {h:[0.0225,2.12,16.1,0.72]},
  "Corpus":          {h:[0.015,2.12,13.416,0.55]},
  "Corpus Amalgam":  {h:[0.015,2.12,13.416,0.55]},
  "Orokin":          {h:[0.015,2.1,10.7332,0.685], s:[0.02,1.75,2,0.75]},
  "Techrot":         {h:[0.015,2.1,13.64,0.72],    s:[0.02,1.76,3.4106,0.76]},
  "Sentient":        {h:[0.015,2.0,10.7332,0.5],   s:[0.02,1.75,2,0.75]},
  "Murmur":          {h:[0.015,2.0,10.7332,0.5],   s:[0.02,1.75,2,0.75]}
};
function curve(fk, kind){
  const o = SCALES[fk] || {};
  return o[kind] || SCALES["_"+kind];
}
function multAt(c, q){
  if(q <= 0) return 1;
  const f1 = 1 + c[0]*Math.pow(q, c[1]);
  const f2 = 1 + c[2]*Math.pow(q, c[3]);
  const t = Math.min(1, Math.max(0, (q-70)/10));
  const s = t*t*(3-2*t);
  return f1 + (f2-f1)*s;
}
function scaleHealth(base, level, bl, fk){
  return base * multAt(curve(fk,"h"), level-(bl||1));
}
function scaleArmor(base, level, bl, fk){
  if(base <= 0) return 0;
  const v = base * multAt(curve(fk,"a"), level-(bl||1));
  return Math.max(200, Math.min(v, 2700));
}
function scaleShield(base, level, bl, fk){
  if(base <= 0) return 0;
  return base * multAt(curve(fk,"s"), level-(bl||1));
}
// 敌方护甲减伤：≤2700 用 0.9·√(A/2700)，超过则 A/(A+300)
function drOf(A){
  if(A <= 0) return 0;
  if(A <= 2700) return 0.9*Math.sqrt(A/2700);
  return A/(A+300);
}

// ---------------------------------------------------------------- 灵化
// 节点数值加在「基础值」上（Wiki 描述均为 Increase Base X by N），
// 所以先叠加到武器基础属性，再走 mod 的乘算。
// flatBaseDamage / additiveBaseDamage 只在灵化形态生效——它们描述的就是
// 灵化形态的基础伤害（Torid 的 +51 正好等于其灵化形态的 51 点基础伤害）。
function effWeapon(wp, inc, on){
  if(!inc) return wp;
  const b = Object.assign({}, wp);
  b.dmg = (wp.dmg || []).slice();
  if(on && inc.forms[1]){
    const f = inc.forms[1];
    b.td = f.td; b.cc = f.cc; b.cm = f.cm; b.sc = f.sc; b.fr = f.fr;
    if(f.mag != null && f.mag > 0) b.mag = f.mag;
    if(f.rl != null && f.rl > 0) b.rl = f.rl;
    if(f.ms != null && f.ms > 0) b.ms = f.ms;
    let sum = 0;
    const d = new Array(DT.length).fill(0);
    for(let i=0;i<DT.length;i++){ const v = f.dmg[DT[i]] || 0; d[i] = v; sum += v; }
    if(sum > 0) b.dmg = d;
  }
  let flat = 0, add = 0, ccA = 0, cmA = 0, scA = 0, frM = 0, rlM = 0, magM = 0,
      flatMag = 0, msA = 0;
  for(const p of inc.picked || []){
    const s = p.sc || {};
    if(on && s.flatBaseDamage) flat += s.flatBaseDamage;
    if(on && s.additiveBaseDamage) add += s.additiveBaseDamage;
    if(s.criticalChance) ccA += s.criticalChance;
    if(s.criticalMultiplier) cmA += s.criticalMultiplier;
    if(s.criticalMultiplierSet) b.cm = s.criticalMultiplierSet;
    if(s.critMultFlat) cmA += s.critMultFlat;
    if(s.statusChance) scA += s.statusChance;
    if(s.fireRate) frM += s.fireRate;
    if(s.reloadSpeed) rlM += s.reloadSpeed;
    if(s.magazine) magM += s.magazine;
    if(s.flatMagazine) flatMag += s.flatMagazine;
    if(s.multishot) msA += s.multishot;
  }
  if(flat || add){
    const old = b.td || 1;
    b.td = (old + flat) * (1 + add);
    const k = b.td / old;
    b.dmg = b.dmg.map(v => v * k);
  }
  b.cc = (b.cc || 0) + ccA;
  b.cm = (b.cm || 1) + cmA;
  b.sc = (b.sc || 0) + scA;
  b.fr = (b.fr || 1) * (1 + frM);
  b.rl = (b.rl || 0) / (1 + rlM);
  b.mag = Math.round(((b.mag || 1) + flatMag) * (1 + magM));
  b.ms = (b.ms || 1) + msA;
  return b;
}

// ---------------------------------------------------------------- 组装
const BANE_KEY = {Grineer:"grineer","Kuva Grineer":"grineer",Corpus:"corpus",
  "Corpus Amalgam":"corpus",Infested:"infested","Infested Deimos":"infested",
  Orokin:"corrupted",Sentient:"sentient",Narmer:"narmer",Murmur:"murmur"};

function assemble(wp, slots, enemy, level, opt){
  const a = aggregate(slots);
  const order = slots.filter(Boolean).map(s=>{
    const m=M[s.m]; if(!m) return null;
    return ALLELEM.filter(t=>statVal(m,s.lv,t)>0);
  }).filter(Boolean).flat();
  const comps = buildComponents(wp, a, order);

  const cc = (wp.cc||0)*100 * (1 + a.cc/100) + (opt.ccBuff || 0);
  const cm = (wp.cm||1) * (1 + a.cd/100);
  const critMul = (opt.crit === false) ? 1 : 1 + (cc/100)*(cm-1);
  const ms = (wp.ms||1) * (1 + a.ms/100);
  const fr = Math.max(0.05,(wp.fr||1) * (1 + a.fr/100));
  const mag = Math.max(1, Math.round((wp.mag||1) * (1 + a.mag/100)));
  const rl  = Math.max(0,(wp.rl||0) / (1 + a.rl/100));
  const sc  = Math.max(0,(wp.sc||0) * (1 + a.sc/100));

  const lv = level + (opt.steel ? 100 : 0);
  const fk = enemy.fk || "";
  const hp = scaleHealth(enemy.hp, lv, enemy.bl, fk);
  const arRaw = scaleArmor(enemy.ar, lv, enemy.bl, fk);
  const ar0 = Math.max(0, arRaw * (1 - (opt.armorStrip||0)/100));
  const sh = scaleShield(enemy.sh, lv, enemy.bl, fk);
  const banePct = (a.fac[BANE_KEY[fk]] || 0)/100;
  const headMul = opt.headshot ? 2 : 1;
  const buffMul = 1 + (opt.dmgBuff || 0)/100;

  const compsF = comps.map(c=>{
    const f = facMult(fk, c.t);
    return {t:c.t, v:c.v, f, vCrit:c.v*f*critMul*ms*(1+banePct)*headMul*buffMul};
  });
  const perShotShield = compsF.reduce((s,c)=>s+c.vCrit,0);
  const shotBase = comps.reduce((s,c)=>s+c.v,0) * ms;   // 不含暴击、不含加成

  return {a, comps:compsF, shotBase, perShotShield, cc, cm, critMul, ms, fr, mag, rl, sc,
          hp, ar0, sh, og:enemy.og||0, fk, banePct, lv,
          dr0: drOf(ar0)};
}

function healthPerShot(A, armor, viralMul){
  let toHealth = 0;
  for(const c of A.comps) toHealth += c.vCrit * (1 - drOf(armor)) * viralMul;
  return toHealth;
}

// 直伤口径：不叠状态、不剥甲
function direct(A){
  const rows = [];
  let toHealth = 0, toShield = 0;
  for(const c of A.comps){
    const dr = drOf(A.ar0);
    const vH = c.vCrit * (1 - dr);
    toHealth += vH; toShield += c.vCrit;
    rows.push({t:c.t, base:c.vCrit, f:c.f, dr, vH, share:0});
  }
  const tot = rows.reduce((s,r)=>s+r.vH,0) || 1;
  rows.forEach(r=>r.share = r.vH/tot);
  const burst = toHealth * A.fr;
  const sust = A.mag > 0 ? (toHealth * A.mag) / (A.mag/A.fr + A.rl) : burst;
  return {rows, toHealth, toShield, burst, sust};
}

// ---------------------------------------------------------------- 状态时间轴
// 确定性模拟：按期望值推进，不做随机抽样。
function simulate(A, opt){
  const T = Math.max(3, opt.window || 10), dt = 0.05;
  const baseViral = Math.min(10, opt.extViral || 0);
  let hp = A.hp, sh = A.sh, og = A.og, armor = A.ar0;
  let mag = A.mag || 1, reload = 0, t = 0;
  let viral = [], corr = [], heatUntil = -1, dots = [];
  let viralAcc = 0, corrAcc = 0;
  let dealt = 0, kill = null, dotTotal = 0, directTotal = 0;
  const N = Math.round(T/dt);
  const sumV = A.comps.reduce((s,x)=>s+x.v,0) || 1;
  const weights = A.comps.map(c=>({t:c.t, w:c.v/sumV}));
  const typeShot = {};
  for(const c of A.comps) typeShot[c.t] = (typeShot[c.t]||0) + c.v * A.ms;

  for(let i=0;i<N;i++){
    // 开火（含装填）
    let fired = 0;
    if(reload > 0){
      reload -= dt;
      if(reload <= 1e-6){ mag = A.mag || 1; reload = 0; }
    } else {
      fired = A.fr * dt;
      if(fired >= mag){
        fired = mag; mag = 0;
        if(A.rl > 0) reload = A.rl; else mag = A.mag || 1;
      } else mag -= fired;
    }

    // 挂状态：按期望值累积，小数部分留到下一步
    if(fired > 0){
      const procs = A.sc * A.ms * fired;
      for(const w of weights){
        const p = procs * w.w;
        if(p <= 1e-9) continue;
        if(w.t === "viral"){
          viralAcc += p;
          while(viralAcc >= 1){ viral.push(t + ST.viral.dur); viralAcc -= 1; }
        } else if(w.t === "corrosive"){
          corrAcc += p;
          while(corrAcc >= 1){ corr.push(t + ST.corrosive.dur); corrAcc -= 1; }
        } else if(w.t === "heat"){
          heatUntil = t + ST.heat.dur;
          dots.push({until:t+ST.heat.dur, n:"燃烧",
            dps: p * ST.heat.dot * typeShot.heat * (1+A.banePct)**2 * facMult(A.fk,"heat"),
            armor:true});
        } else if(w.t === "slash"){
          dots.push({until:t+ST.slash.dur, n:"流血",
            dps: p * ST.slash.dot * A.shotBase * (1+A.banePct)**2 * facMult(A.fk,"slash"),
            armor:false});
        } else if(w.t === "toxin"){
          dots.push({until:t+ST.toxin.dur, n:"中毒",
            dps: p * ST.toxin.dot * typeShot.toxin * (1+A.banePct)**2 * facMult(A.fk,"toxin"),
            armor:false, shieldPierce:true});
        }
      }
      viral = viral.filter(x=>x>t);
      const vcap = Math.max(0, 10 - baseViral);
      if(viral.length>vcap) viral = viral.slice(-vcap);
      corr  = corr.filter(x=>x>t);  if(corr.length>10)  corr  = corr.slice(-10);
    }
    dots = dots.filter(d=>d.until > t);

    // 病毒加伤 / 剥甲
    const vn = Math.min(10, baseViral + viral.length);
    const viralMul = vn > 0 ? 1 + (ST.viral.hp[0] + ST.viral.hp[1]*(vn-1)) : 1;
    const cStrip = Math.min(ST.corrosive.cap, ST.corrosive.strip * corr.length);
    const hStrip = (t < heatUntil) ? ST.heat.strip : 0;
    const strip = 1 - (1-cStrip)*(1-hStrip);
    const armorNow = Math.max(0, armor * (1-strip));

    let dmg = fired * healthPerShot(A, armorNow, viralMul);
    directTotal += dmg;

    let dotDmg = 0;
    for(const d of dots){
      let v = d.dps * dt * viralMul;
      if(d.armor) v *= (1 - drOf(armorNow));
      dotDmg += v;
    }
    dotTotal += dotDmg;
    dmg += dotDmg;

    if(sh > 0){
      const toS = Math.min(sh, dmg);
      sh -= toS; dmg -= toS;
    }
    if(og > 0){
      const toO = Math.min(og, dmg);
      og -= toO; dmg -= toO;
    }
    if(dmg > 0){
      hp -= dmg; dealt += Math.max(0, dmg);
      if(hp <= 0 && kill === null){
        kill = Math.max(0, t + dt*(1 + hp/dmg));
        hp = 0; break;
      }
    }
    t += dt;
  }

  const dur = kill !== null ? kill : Math.min(T, t) || T;
  const total = directTotal + dotTotal;
  const cStripEnd = Math.min(ST.corrosive.cap, ST.corrosive.strip * corr.length);
  return {
    dps: dur > 0 ? total/dur : 0,
    dps10: total/T,
    directDps: dur>0 ? directTotal/dur : 0,
    dotDps: dur>0 ? dotTotal/dur : 0,
    kill, viralAtEnd: viral.length, corrAtEnd: corr.length,
    stripAtEnd: cStripEnd, dur
  };
}

function compute(wp, slots, enemy, level, opt, uid){
  const inc = (DB.i && uid) ? DB.i[uid] : null;
  const wp2 = inc ? effWeapon(wp, inc, opt.incarnon) : wp;
  const A = assemble(wp2, slots, enemy, level, opt);
  const d = direct(A);
  const s = opt.status ? simulate(A, opt) : null;
  return {A, d, s, inc, wp2};
}

// ---------------------------------------------------------------- 状态
  return {DT, ZH, COL, PHYS, ELEM_ORDER, ALLELEM, COMBO_OF, FACMOD, ST, CATT,
          statVal, aggregate, buildComponents, effWeapon, assemble, drOf,
          multAt, curve, scaleHealth, scaleArmor, scaleShield,
          direct, simulate, compute, healthPerShot, BANE_KEY};
}

module.exports = {makeEngine};
