'use strict';
// 默认参数下把每套配卡的 burst / dps / ttk 记下来，用来证明「新增选项不改默认结果」
const fs = require('fs'), path = require('path');
const {makeEngine} = require('../server/engine.js');
const DB = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'server', 'data', 'payload.json'), 'utf8'));
const ENG = makeEngine(DB);
const opt = {steel:false,status:true,extViral:0,armorStrip:0,window:10,headshot:false,
             crit:true,incarnon:false,dmgBuff:0,ccBuff:0};
const out = {};
for (const b of DB.b) {
  const e = DB.e.find(x => x.n === 'Heavy Gunner') || DB.e[0];
  const r = ENG.compute(DB.w[b.w], (b.slots[0]||[]).slice(), e, 100, opt, b.w);
  out[b.w] = [Math.round(r.d.burst*100)/100,
              r.s ? Math.round(r.s.dps*100)/100 : null,
              r.s && r.s.kill != null ? Math.round(r.s.kill*100)/100 : null];
}
const f = process.argv[2] || 'build/tmp/snap.json';
fs.writeFileSync(f, JSON.stringify(out, null, 0));
console.log('snapshot', Object.keys(out).length, '→', f);
