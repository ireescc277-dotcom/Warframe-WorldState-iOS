'use strict';
// 用 WebKit（Playwright 的 webkit build）把 iOS 那条链路在本地复现一遍。
// Chrome 跑得通、模拟器跑不通时，只能靠这个把页内报错捞出来。
//
// 用法：node scripts/dps_webkit_check.js [站点目录] [query]

const fs = require('fs'), path = require('path'), http = require('http');
const { webkit } = require('playwright');

const ROOT = path.resolve(process.argv[2] || 'ios/DamageCalc');
const QUERY = process.argv[3] || '?weapon=Torid';
const PORT = 8815;

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.webp': 'image/webp', '.png': 'image/png', '.svg': 'image/svg+xml',
};

const server = http.createServer((req, res) => {
  let rel = decodeURIComponent((req.url || '/').split('?')[0]);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(ROOT, rel);
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); res.end('nf'); return;
  }
  // 和 iOS 上的 LocalStaticServer 一样：一次性发完就关，不留 keep-alive
  res.writeHead(200, {
    'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
    'Cache-Control': 'no-cache', 'Connection': 'close',
  });
  res.end(fs.readFileSync(file));
});

(async () => {
  await new Promise(r => server.listen(PORT, '127.0.0.1', r));
  const browser = await webkit.launch();
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

  const logs = [];
  page.on('console', m => logs.push(m.type() + ': ' + m.text().slice(0, 240)));
  page.on('pageerror', e => logs.push('pageerror: ' + String(e && e.message || e).slice(0, 300)));
  page.on('requestfailed', r => logs.push('reqfail: ' + r.url().split('/').pop() + ' ' +
    (r.failure() && r.failure().errorText)));

  const t0 = Date.now();
  await page.goto(`http://127.0.0.1:${PORT}/index.html${QUERY}`, { waitUntil: 'load', timeout: 30000 })
    .catch(e => logs.push('goto: ' + e.message));

  const snap = async label => {
    const s = await page.evaluate(`(function(){
      var f = document.getElementById('wf-kernel');
      var fr = {present: !!f};
      if (f) {
        try {
          var w = f.contentWindow;
          fr.href = w.location.href;
          fr.ready = w.document.readyState;
          fr.scripts = w.document.scripts.length;
          fr.reCalc = typeof w.reCalc;
          fr.modsProps = !!w.modsProps;
          fr.htmlLen = w.document.documentElement ? w.document.documentElement.outerHTML.length : -1;
          fr.title = w.document.title;
        } catch (e) { fr.err = String(e.message || e); }
      }
      return JSON.stringify({
        step: window.__wfStep || '', buildinfo: (document.getElementById('buildinfo')||{}).textContent,
        wcount: (document.getElementById('wcount')||{}).textContent,
        tname: (document.getElementById('tname')||{}).textContent,
        cards: document.querySelectorAll('.acard').length,
        wfk: !!window.WFK, w: !!(window.WFK && window.WFK.W),
        inline: !!window.__WF_INLINE, jsErr: window.__jsErr || '', wfErr: window.__wfErr || '',
        banner: (document.getElementById('banner')||{}).textContent || '',
        frame: fr
      });
    })()`).catch(e => 'eval fail: ' + e.message);
    logs.push(`[${label} ${((Date.now() - t0) / 1000).toFixed(1)}s] ` + s);
  };

  await snap('load');
  for (const s of [2, 5, 10]) { await page.waitForTimeout(s * 1000); await snap('+' + s + 's'); }

  console.log(logs.join('\n'));
  await browser.close();
  server.close();
  process.exit(0);
})().catch(e => { console.log('FAIL ' + String(e && e.stack || e)); server.close(); process.exit(1); });
