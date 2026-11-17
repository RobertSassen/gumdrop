// Renders the window cakes (windows.js) into ../../art/windows/<id>/ and
// writes ../../windows/<id>.json, which tells the game which levels a window
// covers and which flavors of glass each panel holds.
//
//   cd tools/art && npm install && node render-windows.js
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ART = path.resolve(__dirname, '../../art/windows');
const DATA = path.resolve(__dirname, '../../windows');
const PANEL_PX = 320;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('pageerror', e => console.log('page error:', e.message));
  await page.setContent('<!doctype html><html><body></body></html>');
  await page.addScriptTag({ path: path.join(__dirname, 'windows.js') });
  const metas = await page.evaluate(() => window.windowCakes.WINDOWS.map(window.windowCakes.meta));
  fs.mkdirSync(DATA, { recursive: true });
  for (let i = 0; i < metas.length; i++) {
    const m = metas[i];
    const r = await page.evaluate(([i, px]) => window.windowCakes.render(window.windowCakes.WINDOWS[i], px), [i, PANEL_PX]);
    const dir = path.join(ART, m.id);
    fs.mkdirSync(dir, { recursive: true });
    const save = (name, url) => fs.writeFileSync(path.join(dir, name + '.png'), Buffer.from(url.split(',')[1], 'base64'));
    save('base', r.base); save('lead', r.lead);
    for (const f in r.glass) save(f, r.glass[f]);
    fs.writeFileSync(path.join(DATA, m.id + '.json'), JSON.stringify({ ...m, panel_px: PANEL_PX, panels: r.panels }, null, 1) + '\n');
    console.log(m.id, r.panels.map(p => p.length).join(' '), 'flavors per panel');
  }
  await browser.close();
})();
