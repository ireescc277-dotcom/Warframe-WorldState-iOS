'use strict';
// 最小复现：同一个页面里先后建两个指向 site/index.html 的 iframe，第二个会不会拿到空文档。
const fs = require('fs'), path = require('path'), http = require('http');
const { webkit } = require('playwright');

const ROOT = path.resolve('ios/DamageCalc');
const PORT = 8817;
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css', '.json': 'application/json', '.webp': 'image/webp' };

const hits = [];
const server = http.createServer((req, res) => {
  const raw = req.url || '/';
  let rel = decodeURIComponent(raw.split('?')[0]);
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(ROOT, rel);
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    hits.push(raw + ' -> 404');
    res.writeHead(404); res.end('nf'); return;
  }
  const body = fs.readFileSync(file);
  hits.push(raw + ' -> ' + body.length);
  res.writeHead(200, {
    'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
    'Content-Length': body.length,
    'Connection': 'close',
  });
  res.end(body);
});

(async () => {
  await new Promise(r => server.listen(PORT, '127.0.0.1', r));
  const browser = await webkit.launch();
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${PORT}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(6000);

  const probe = await page.evaluate(async () => {
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const build = async (src, keep) => {
      const f = document.createElement('iframe');
      f.style.cssText = 'position:fixed;left:-9999px;width:1px;height:1px';
      const p = new Promise(r => { f.onload = r; });
      f.src = src;
      document.body.appendChild(f);
      await Promise.race([p, sleep(9000)]);
      await sleep(300);
      const w = f.contentWindow;
      let info;
      try {
        info = {
          src,
          href: w.location.href,
          ready: w.document.readyState,
          htmlLen: w.document.documentElement ? w.document.documentElement.outerHTML.length : -1,
          scripts: w.document.scripts.length,
          reCalc: typeof w.reCalc,
        };
      } catch (e) { info = { src, err: String(e.message || e) }; }
      if (!keep) f.remove();
      return info;
    };

    const out = [];
    out.push(await build('site/index.html?n=1', true));   // 第一个，留着
    out.push(await build('site/index.html?n=2', true));   // 第二个，同时存在
    out.push(await build('site/index.html?n=3', false));  // 第三个
    return JSON.stringify(out);
  });

  console.log(probe);
  console.log('SERVER HITS:\n' + hits.filter(h => h.includes('index.html')).slice(0, 8).join('\n'));
  await browser.close();
  server.close();
  process.exit(0);
})().catch(e => { console.log('FAIL ' + e.message); server.close(); process.exit(1); });
