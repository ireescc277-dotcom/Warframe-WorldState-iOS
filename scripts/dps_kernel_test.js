'use strict';
// 内核自检：走 server/kernel.js，打印各攻击的四套 DPS / TTK。
const K = require('../server/kernel.js');

(async () => {
  let t = Date.now();
  const r1 = await K.calc({ weapon: 'Torid', enemy: 'Heavy Gunner', level: 100 });
  console.log('boot+calc', Date.now() - t, 'ms  boot', K.W.__bootMs, 'ms');
  for (const a of r1.attacks) console.log(' ', a.name.padEnd(18), 'hp', a.dps.health, 'armor', a.dps.armor, 'ttk', a.ttk.health);

  t = Date.now();
  const r2 = await K.calc({ weapon: 'Torid', enemy: 'Heavy Gunner', level: 1 });
  console.log('lv1', Date.now() - t, 'ms', r2.attacks.map(a => a.name + ':' + a.dps.health).join(' '));

  const r3 = await K.calc({ weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, steel: true });
  console.log('steel', r3.attacks.map(a => a.name + ':' + a.dps.health).join(' '));

  const mods = { 0: 'Serration', 1: 'Split Chamber', 2: 'Vital Sense', 3: 'Primed Cryo Rounds', 4: 'Infected Clip', 5: 'Malignant Force', 6: 'Point Strike', 7: 'Hunter Munitions' };
  const r4 = await K.calc({ weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, mods });
  console.log('mods', r4.attacks.map(a => a.name + ':' + a.dps.health + ' ttk' + a.ttk.health).join(' '), 'lost', JSON.stringify(r4.lostMods));

  const r5 = await K.calc({ weapon: 'Torid', enemy: 'Heavy Gunner', level: 100, mods, opts: { headshot: true } });
  console.log('headshot', r5.attacks.map(a => a.name + ':' + a.dps.health).join(' '));

  console.log('mem', Math.round(process.memoryUsage().rss / 1048576), 'MB');
  process.exit(0);
})().catch(e => { console.log('ERR', e.message); console.log(e.stack.split('\n').slice(0, 8).join('\n')); process.exit(1); });
