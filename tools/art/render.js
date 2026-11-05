// Renders every art file the game loads into ../../art.
//
//   cd tools/art && npm install && node render.js
//
// Needs Chromium for Playwright (npx playwright install chromium).
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = __dirname;
const OUT = path.resolve(ROOT, '../../art');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.woff2': 'font/woff2', '.png': 'image/png' };

function serve() {
  const server = http.createServer((req, res) => {
    const file = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!file.startsWith(ROOT) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise(r => server.listen(0, () => r(server)));
}

const save = (name, dataUrl) => {
  fs.writeFileSync(path.join(OUT, name), Buffer.from(dataUrl.split(',')[1], 'base64'));
  console.log('wrote art/' + name);
};

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const server = await serve();
  const base = `http://localhost:${server.address().port}`;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

  // 3D sprites
  const sp = await browser.newPage();
  sp.on('pageerror', e => console.log('page error:', e.message));
  await sp.goto(base + '/sprites.html');
  await sp.waitForFunction(() => window.__ready === true);
  const call = (fn, ...a) => sp.evaluate(([fn, a]) => window.sprites[fn](...a), [fn, a]);
  for (const [name, layers] of [['cube', await call('cube')], ['slab_h', await call('slab', false)], ['slab_v', await call('slab', true)], ['cupfill', await call('cupFill')]])
    for (const k of ['shadow', 'body', 'gloss']) save(`${name}_${k}.png`, layers[k]);
  for (const f of ['right', 'left', 'up', 'down']) save(`tray_${f}.png`, await call('tray', f));
  save('cup.png', await call('cup'));
  const table = await call('table');

  // Flat UI pieces at 2x
  const ui = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 600, height: 1200 } });
  await ui.goto(base + '/ui.html');
  await ui.evaluate(src => new Promise(r => { const i = document.getElementById('tableimg'); i.onload = r; i.src = src; }), table);
  await ui.evaluate(() => document.fonts.ready);
  for (const id of ['background', 'decor', 'card', 'pill', 'pause', 'pane_empty', 'pane_body', 'pane_gloss', 'btn_spare', 'btn_undo', 'btn_restart', 'sparkle']) {
    const el = await ui.$('#' + id);
    await el.screenshot({ path: path.join(OUT, id + '.png'), omitBackground: id !== 'background' });
    console.log('wrote art/' + id + '.png');
  }
  await browser.close();
  server.close();
})();
