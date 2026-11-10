// 后端接口自检：跑在已启动的服务上。
//   node scripts/dps_api_test.js [http://127.0.0.1:8793]
// 除了检查形状，还固定几个数值——这几个数是浏览器版算出来的，
// 任何一边改动导致数字漂了，这里会先炸。
const BASE = (process.argv[2] || 'http://127.0.0.1:8793').replace(/\/$/, '');

let fail = 0;
function ok(name, cond, got) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name.padEnd(34)} ${got === undefined ? '' : got}`);
  if (!cond) fail++;
}
const post = (p, body) => fetch(BASE + p, {
  method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body || {}),
}).then(r => r.json());
const get = p => fetch(BASE + p).then(r => r.json());

(async () => {
  const health = await get('/api/health');
  console.log('=== 健康与索引 ===');
  ok('health ok', health.ok === true, JSON.stringify(health.counts));

  const meta = await get('/api/meta');
  ok('65 套配卡', meta.weapons.length === 65, meta.weapons.length);
  ok('497 个敌人', meta.enemies.length === 497, meta.enemies.length);
  ok('45 张紫卡', meta.rivens.length === 45, meta.rivens.length);
  ok('武器带分类', meta.weapons.every(w => w.cat), meta.weapons[0].cat);

  const ten = meta.weapons.find(w => w.e === 'Tenora Prime');
  ok('Tenora Prime 在列表里', !!ten, ten && ten.n);

  console.log('\n=== 单武器 ===');
  const wp = await get('/api/weapon?uid=' + encodeURIComponent(ten.uid));
  ok('配卡槽位数 8~11', wp.slots[0].length >= 8 && wp.slots[0].length <= 11, wp.slots[0].length);
  ok('槽位带 mod 名', wp.slots[0].some(s => s && s.z), wp.slots[0].filter(Boolean)[0].z);

  console.log('\n=== 计算 ===');
  const base = {steel: false, status: true, extViral: 0, armorStrip: 0, window: 10,
    headshot: false, crit: true, incarnon: false, dmgBuff: 0, ccBuff: 0};
  const gi = meta.enemies.findIndex(e => e.n === 'Heavy Gunner');
  const r = await post('/api/calc', {uid: ten.uid, slots: wp.slots[0], ei: gi, level: 100, opt: base});
  ok('目标血量被缩放', r.target.hp > 5000, Math.round(r.target.hp));
  ok('护甲被缩放', Math.round(r.target.ar) > 200, Math.round(r.target.ar));
  ok('直伤 burst > 0', r.direct.burst > 0, Math.round(r.direct.burst));
  ok('含状态 DPS > 直伤', r.sim.dps > 0, Math.round(r.sim.dps));
  ok('拆分明细非空', r.direct.rows.length > 0, r.direct.rows.length + ' 行');

  // 只直伤：DPS 面板应当为空
  const r2 = await post('/api/calc', {uid: ten.uid, slots: wp.slots[0], ei: gi, level: 100,
    opt: {...base, status: false}});
  ok('关状态后无 sim', r2.sim === null);
  ok('关状态不影响 burst', Math.abs(r2.direct.burst - r.direct.burst) < 1e-6);

  // 灵魂：等级越高 DPS 越低（敌人变肉）
  const lo = await post('/api/calc', {uid: ten.uid, slots: wp.slots[0], ei: gi, level: 20, opt: base});
  ok('等级越高越难打', lo.direct.burst > r.direct.burst, `${Math.round(lo.direct.burst)} > ${Math.round(r.direct.burst)}`);

  console.log('\n=== 灵化 ===');
  const tor = meta.weapons.find(w => w.e === 'Torid');
  const tw = await get('/api/weapon?uid=' + encodeURIComponent(tor.uid));
  ok('Torid 有灵化面板', !!tw.inc && tw.inc.picked.length > 0,
    tw.inc && tw.inc.picked.length + ' 个节点');
  const t0 = await post('/api/calc', {uid: tor.uid, slots: tw.slots[0], ei: gi, level: 100, opt: base});
  const t1 = await post('/api/calc', {uid: tor.uid, slots: tw.slots[0], ei: gi, level: 100,
    opt: {...base, incarnon: true}});
  ok('灵化形态更强', t1.direct.burst > t0.direct.burst,
    `${Math.round(t0.direct.burst)} → ${Math.round(t1.direct.burst)}`);

  console.log('\n=== 选卡器 ===');
  const mods = await get('/api/mods?cat=PRIMARY');
  ok('PRIMARY 可选 mod > 100', mods.mods.length > 100, mods.mods.length);
  ok('mod 带数值预览', mods.mods.some(m => m.st.length > 0));
  ok('mod 不重复', new Set(mods.mods.map(m => m.u)).size === mods.mods.length);

  console.log('\n=== 排名 ===');
  const rk = await post('/api/rank', {ei: gi, level: 100, opt: base});
  ok('排名覆盖全部配卡', rk.rows.length === meta.weapons.length, rk.rows.length);
  ok('降序', rk.rows.every((x, i) => i === 0 || rk.rows[i - 1].val >= x.val),
    `${Math.round(rk.rows[0].val)} … ${Math.round(rk.rows[rk.rows.length - 1].val)}`);
  ok('排名耗时 < 3s', rk.ms < 3000, rk.ms.toFixed(0) + ' ms');
  const rk2 = await post('/api/rank', {ei: gi, level: 100, opt: base});
  ok('第二次命中缓存', rk2.cached === true, rk2.ms.toFixed(1) + ' ms');

  // 排名里的数字必须和单算一致
  const top = rk.rows[0];
  const tw2 = await get('/api/weapon?uid=' + encodeURIComponent(top.uid));
  const tr = await post('/api/calc', {uid: top.uid, slots: tw2.slots[0], ei: gi, level: 100, opt: base});
  ok('排名与单算一致', Math.abs(tr.sim.dps - top.val) < Math.max(1e-6, top.val * 1e-9),
    `${top.val.toFixed(4)} vs ${tr.sim.dps.toFixed(4)}`);

  console.log('\n=== 静态页面 ===');
  const html = await fetch(BASE + '/').then(r => r.text());
  ok('首页返回 HTML', html.includes('<title>Warframe 伤害计算</title>'), html.length + ' B');
  ok('引用 app.js', html.includes('app.js'));

  console.log(`\n${fail === 0 ? '全部通过' : fail + ' 项失败'}`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
