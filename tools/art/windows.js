// The window cakes: stained-glass scenes that the player fills in over a run
// of levels. Each scene is cut into a grid of panels, one per level, and each
// panel shows exactly as many flavors of glass as its level has trays.
//
// Runs in a browser page (render-windows.js drives it). A scene is a list of
// shapes painted back to front in a space where every panel is 200 x 200.
// S(flavor, path, cut): cut > 0 breaks a big shape into small panes of glass.
(() => {
const FLAVORS = ['cherry', 'tangerine', 'lemon', 'lime', 'mint', 'soda', 'blueberry', 'grape', 'raspberry', 'cola', 'licorice', 'peach'];
const LEAD = '#40312d', FROST = [233, 225, 210];
const PANEL = 200;

const P = d => new Path2D(d);
const circ = (x, y, r) => { const p = new Path2D(); p.arc(x, y, r, 0, 7); return p; };
const ell = (x, y, rx, ry, rot = 0) => { const p = new Path2D(); p.ellipse(x, y, rx, ry, rot, 0, 7); return p; };
const poly = pts => { const p = new Path2D(); pts.forEach(([x, y], i) => i ? p.lineTo(x, y) : p.moveTo(x, y)); p.closePath(); return p; };
const join = (...ps) => { const p = new Path2D(); ps.forEach(q => p.addPath(q)); return p; };
const S = (f, p, cut = 0) => ({ f, p, cut });
function flower(out, x, y, petal, centre, r = 9) {
  const ps = [];
  for (let k = 0; k < 5; k++) { const a = -Math.PI / 2 + k * Math.PI * 2 / 5; ps.push(circ(x + Math.cos(a) * r, y + Math.sin(a) * r, r * 0.86)); }
  out.push(S(petal, join(...ps)), S(centre, circ(x, y, r * 0.5)));
}
function rays(x, y, r0, r1, n = 8) {
  const ps = [];
  for (let k = 0; k < n; k++) { const a = k * Math.PI * 2 / n, w = 0.2;
    ps.push(poly([[x + Math.cos(a - w) * r0, y + Math.sin(a - w) * r0], [x + Math.cos(a) * r1, y + Math.sin(a) * r1], [x + Math.cos(a + w) * r0, y + Math.sin(a + w) * r0]])); }
  return join(...ps);
}
const tulip = (x, y) => P(`M${x-14} ${y-6} L${x-14} ${y-24} L${x-7} ${y-15} L${x} ${y-26} L${x+7} ${y-15} L${x+14} ${y-24} L${x+14} ${y-6} Q${x+14} ${y+9} ${x} ${y+9} Q${x-14} ${y+9} ${x-14} ${y-6}Z`);
const stem = (x, y0, y1) => P(`M${x-2.5} ${y0} L${x+2.5} ${y0} L${x+2.5} ${y1} L${x-2.5} ${y1}Z`);
const bow = (x, y) => join(poly([[x, y], [x - 12, y - 6], [x - 12, y + 6]]), poly([[x, y], [x + 12, y - 6], [x + 12, y + 6]]));

// Levels 1 to 4 (3, 4, 5 and 6 trays): sun, kite, tulips, blossom tree.
function kiteDay() {
  const out = [ S('soda', P('M0 0H400V310H0Z'), 3),
    S('tangerine', rays(96, 96, 45, 74)), S('lemon', circ(96, 96, 40)),
    S('cherry', poly([[310, 28], [310, 140], [275, 80]])), S('grape', poly([[310, 28], [345, 80], [310, 140]])),
    S('lemon', join(bow(305, 153), bow(296, 168), bow(303, 184))),
    S('lime', P('M0 300 Q100 262 200 292 T400 286 L400 400 L0 400Z'), 5),
    S('lime', join(stem(62, 270, 300), stem(122, 258, 292), stem(172, 280, 302))),
    S('mint', join(ell(73, 290, 12, 4.5, -0.7), ell(51, 290, 12, 4.5, 0.7), ell(133, 282, 12, 4.5, -0.7), ell(161, 296, 12, 4.5, 0.7))),
    S('cherry', tulip(62, 264)), S('lemon', tulip(122, 252)), S('cherry', tulip(172, 274)),
    S('blueberry', ell(348, 366, 40, 15)),
    S('cola', P('M294 348 L299 286 L313 286 L318 348Z')),
    S('raspberry', join(circ(306, 258, 30), circ(280, 274, 21), circ(332, 274, 21))),
    S('peach', join(circ(306, 244, 6.5), circ(288, 266, 6), circ(324, 266, 6), circ(306, 278, 6), circ(272, 282, 5), circ(340, 282, 5))) ];
  return out;
}

// Levels 5 to 8 (5, 6, 6 and 7 trays): sun and kite, blossom branch, duck, tulip bank.
function duckPond() {
  const out = [ S('soda', P('M0 0H400V240H0Z'), 3),
    S('tangerine', rays(70, 70, 37, 60)), S('lemon', circ(70, 70, 33)),
    S('grape', poly([[155, 74], [155, 146], [132, 106]])), S('grape', poly([[155, 74], [178, 106], [155, 146]])),
    S('mint', P('M210 186 Q300 112 400 150 L400 240 L210 240Z'), 9),
    S('lime', P('M0 166 Q100 134 200 175 T400 180 L400 400 L0 400Z'), 5),
    S('cola', P('M400 18 Q330 40 290 80 T216 122 L220 133 Q262 120 300 92 Q342 58 400 38Z')) ];
  flower(out, 300, 78, 'raspberry', 'peach', 11); flower(out, 250, 110, 'raspberry', 'peach', 10); flower(out, 352, 44, 'raspberry', 'peach', 10);
  out.push(S('peach', join(circ(232, 60, 6), circ(276, 34, 5), circ(372, 96, 6), circ(326, 124, 5))));
  out.push(S('blueberry', ell(200, 332, 172, 54), 7),
    S('lime', join(stem(22, 252, 400), stem(36, 268, 400))), S('cola', join(ell(22, 242, 6, 15), ell(36, 258, 6, 15))),
    S('mint', ell(62, 364, 21, 8)), S('mint', ell(288, 356, 21, 8)),
    S('lemon', poly([[74, 312], [54, 292], [82, 300]])), S('lemon', ell(112, 318, 43, 24)), S('lemon', circ(152, 290, 17)),
    S('lemon', ell(106, 318, 23, 12, -0.15)), S('tangerine', poly([[166, 284], [189, 291], [166, 298]])), S('cola', circ(156, 286, 3.2)),
    S('lime', join(stem(250, 256, 282), stem(292, 244, 290), stem(332, 258, 302), stem(366, 246, 318))),
    S('mint', join(ell(261, 272, 12, 4.5, -0.7), ell(281, 268, 12, 4.5, 0.7), ell(343, 284, 12, 4.5, -0.7), ell(355, 290, 12, 4.5, 0.7))),
    S('cherry', tulip(250, 250)), S('lemon', tulip(292, 238)), S('raspberry', tulip(332, 252)), S('grape', tulip(366, 240)));
  return out;
}

// levels: the level numbers (1 = first file in levels/) for the panels, row by row.
const WINDOWS = [
  { id: '01_kite_day', title: 'Kite day', customer: 'Coach Lin', cols: 2, rows: 2, levels: [1, 2, 3, 4], shapes: kiteDay() },
  { id: '02_duck_pond', title: 'The duck pond', customer: 'The twins next door', cols: 2, rows: 2, levels: [5, 6, 7, 8], shapes: duckPond() },
];

const hash = (i, j, s) => { let h = (i * 374761393 + j * 668265263 + s * 2147483647) | 0; h = (h ^ (h >> 13)) * 1274126177 | 0; return ((h ^ (h >> 16)) >>> 0) / 4294967295; };
const G = 30;
const vert = (i, j, s) => [i * G + (hash(i, j, s) - 0.5) * G * 0.62, j * G + (hash(j, i, s + 11) - 0.5) * G * 0.62];
const grey = v => `rgb(${v.map(x => Math.round(x)).join(',')})`;

// Paints every shape back to front. paint(shape, n) returns the fill for a
// shape (or a function of the small pane for cut shapes), or null to erase.
function paintAll(ctx, win, fillOf, lead) {
  const W = win.cols * PANEL, H = win.rows * PANEL;
  ctx.lineJoin = 'round'; ctx.strokeStyle = LEAD;
  win.shapes.forEach((sh, n) => {
    const fill = fillOf(sh, n);
    ctx.save(); ctx.clip(sh.p);
    if (fill === null) { ctx.globalCompositeOperation = 'destination-out'; ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H); ctx.globalCompositeOperation = 'source-over'; }
    if (sh.cut) {
      ctx.lineWidth = 1.5;
      for (let a = -1; a < W / G + 1; a++) for (let b = -1; b < H / G + 1; b++) {
        const q = [vert(a, b, sh.cut), vert(a + 1, b, sh.cut), vert(a + 1, b + 1, sh.cut), vert(a, b + 1, sh.cut)];
        ctx.beginPath(); q.forEach(([x, y], m) => m ? ctx.lineTo(x, y) : ctx.moveTo(x, y)); ctx.closePath();
        if (fill) { ctx.fillStyle = fill((hash(a, b, sh.cut + 5) - 0.5) * 2); ctx.fill(); if (!lead) { ctx.strokeStyle = ctx.fillStyle; ctx.lineWidth = 0.8; ctx.stroke(); } }
        if (lead) ctx.stroke();
      }
    } else if (fill) { ctx.fillStyle = fill((hash(n, 7, 3) - 0.5) * 2); ctx.fillRect(0, 0, W, H); }
    ctx.restore();
    if (lead) { ctx.lineWidth = 2.6; ctx.stroke(sh.p); }
  });
}
function canvasFor(win, px) {
  const c = document.createElement('canvas'); c.width = win.cols * px; c.height = win.rows * px;
  const ctx = c.getContext('2d', { willReadFrequently: true }); ctx.scale(px / PANEL, px / PANEL);
  return [c, ctx];
}

// Which flavors show in each panel, by counting flat-painted pixels.
function panelFlavors(win) {
  const [c, ctx] = canvasFor(win, PANEL);
  const key = {};
  FLAVORS.forEach((f, i) => { key[(i + 1) * 20] = f; });
  paintAll(ctx, win, sh => () => grey(Array(3).fill((FLAVORS.indexOf(sh.f) + 1) * 20)), false);
  const out = [];
  for (let r = 0; r < win.rows; r++) for (let col = 0; col < win.cols; col++) {
    const d = ctx.getImageData(col * PANEL, r * PANEL, PANEL, PANEL).data, n = {};
    for (let p = 0; p < d.length; p += 4) if (d[p + 3] === 255 && d[p] === d[p + 1] && key[d[p]]) n[key[d[p]]] = (n[key[d[p]]] || 0) + 1;
    out.push(FLAVORS.filter(f => n[f] > 25));
  }
  return out;
}

// The pictures the game needs for one window, as PNG data URLs:
//   base: every pane as clear frosted glass
//   glass[flavor]: that flavor's panes in shades of white; the game tints them
//   lead: the lead lines and a soft shine, drawn on top
function render(win, px) {
  const out = { glass: {}, panels: panelFlavors(win) };
  let [c, ctx] = canvasFor(win, px);
  paintAll(ctx, win, () => k => grey(FROST.map(v => v * (1 + k * 0.05))), false);
  out.base = c.toDataURL();
  for (const f of new Set(win.shapes.map(s => s.f))) {
    [c, ctx] = canvasFor(win, px);
    paintAll(ctx, win, sh => sh.f === f ? k => grey(Array(3).fill(255 * (0.9 + k * 0.1))) : null, false);
    out.glass[f] = c.toDataURL();
  }
  [c, ctx] = canvasFor(win, px);
  paintAll(ctx, win, () => null, true);
  for (let r = 0; r < win.rows; r++) for (let col = 0; col < win.cols; col++) {
    const x = col * PANEL, y = r * PANEL, g = ctx.createLinearGradient(x, y, x + PANEL, y + PANEL);
    g.addColorStop(0, 'rgba(255,255,255,.22)'); g.addColorStop(0.5, 'rgba(255,255,255,0)'); g.addColorStop(1, 'rgba(40,20,10,.1)');
    ctx.globalCompositeOperation = 'destination-over'; ctx.fillStyle = g; ctx.fillRect(x, y, PANEL, PANEL);
  }
  out.lead = c.toDataURL();
  return out;
}

window.windowCakes = { WINDOWS, render, meta: w => ({ id: w.id, title: w.title, customer: w.customer, cols: w.cols, rows: w.rows, levels: w.levels }) };
})();
