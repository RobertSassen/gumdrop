// Renders the game's 3D-looking sprites with three.js: glossy jelly cubes, set
// slabs, silicone trays, cups and the oak table. Loaded by sprites.html and
// driven by render.js, which saves each result as a PNG in ../../art.
//
// Sizes follow the game's board units (scripts/core/level.gd): a tray cell is
// 76 px and a cube is 70 px, so S = 84 px per 3D unit keeps the proportions of
// the approved mockup.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const S = 84;            // px per unit
const CELL = 76, PAD = 6, CUBE = 70;
const TRAY_LONG = 4 * CELL + 2 * PAD, TRAY_WIDE = CELL + 2 * PAD;
const TILT = 16 * Math.PI / 180; // the mockup camera looks down at about 16 degrees from vertical

const canvas = document.createElement('canvas');
document.body.appendChild(canvas);
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.VSMShadowMap;
renderer.toneMapping = THREE.NeutralToneMapping;
renderer.toneMappingExposure = 0.9;
renderer.setClearColor(0x000000, 0);
const envTex = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;

const u = px => px / S;
const gloss = (color, o = {}) => new THREE.MeshPhysicalMaterial({ color, roughness: 0.32, clearcoat: 0.8, clearcoatRoughness: 0.2, ...o });
const gummy = (hex, o = {}) => new THREE.MeshPhysicalMaterial({
  color: hex, roughness: 0.25, clearcoat: 0.7, clearcoatRoughness: 0.08, emissive: hex, emissiveIntensity: 0.1, ...o,
});

function baseScene(shadowExtent = 6, shadowOpacity = 0.15) {
  const scene = new THREE.Scene();
  scene.environment = envTex;
  scene.environmentIntensity = 0.4;
  scene.add(new THREE.HemisphereLight('#fff6e8', '#7a5233', 0.55));
  const key = new THREE.DirectionalLight('#fff1dc', 1.9);
  key.position.set(-6, 20, 9);
  key.castShadow = true;
  key.shadow.mapSize.set(1024, 1024);
  Object.assign(key.shadow.camera, { left: -shadowExtent, right: shadowExtent, top: shadowExtent, bottom: -shadowExtent, near: 1, far: 60 });
  key.shadow.radius = 9; key.shadow.blurSamples = 16; key.shadow.bias = -0.0005;
  scene.add(key);
  // invisible ground that only shows the soft, warm shadow (kept light: the
  // game stacks sprite shadows, which a single 3D scene would not)
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), new THREE.ShadowMaterial({ color: '#4a2508', opacity: shadowOpacity }));
  ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true;
  scene.add(ground);
  return scene;
}
function add(parent, geo, m, x = 0, y = 0, z = 0) {
  const mesh = new THREE.Mesh(geo, m);
  mesh.position.set(x, y, z); mesh.castShadow = true; mesh.receiveShadow = true;
  parent.add(mesh); return mesh;
}
// Orthographic, slightly tilted camera centered on the ground point (0,0,0),
// so a sprite's center is the object's footprint center in the game.
function shoot(scene, wpx, hpx) {
  renderer.setSize(wpx, hpx, false);
  canvas.width = wpx; canvas.height = hpx;
  const cam = new THREE.OrthographicCamera(-u(wpx) / 2, u(wpx) / 2, u(hpx) / 2, -u(hpx) / 2, 0.1, 100);
  cam.position.set(0, Math.cos(TILT) * 30, Math.sin(TILT) * 30);
  cam.lookAt(0, 0, 0);
  renderer.render(scene, cam);
  return defringe(wpx, hpx);
}
// Antialiased edge pixels come out of WebGL much darker than the surface they
// belong to, which reads as a thin black outline in the game. Give each
// partly transparent pixel the color of its opaque neighbors, keeping its alpha.
function defringe(w, h) {
  const c2 = document.createElement('canvas'); c2.width = w; c2.height = h;
  const g = c2.getContext('2d');
  g.drawImage(canvas, 0, 0);
  const img = g.getImageData(0, 0, w, h), d = img.data, src = d.slice();
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4;
    if (src[i + 3] === 0 || src[i + 3] === 255) continue;
    let r = 0, gg = 0, b = 0, n = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const xx = x + dx, yy = y + dy;
      if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
      const j = (yy * w + xx) * 4;
      if (src[j + 3] === 255) { r += src[j]; gg += src[j + 1]; b += src[j + 2]; n++; }
    }
    if (n) { d[i] = r / n; d[i + 1] = gg / n; d[i + 2] = b / n; }
  }
  g.putImageData(img, 0, 0);
  return c2.toDataURL('image/png');
}

// --- sprites ---------------------------------------------------------------

// Jelly is drawn in three layers so its flavor color stays editable in
// tuning.json: a soft shadow, a white body the game tints with the flavor
// color, and a gloss layer the game adds on top untinted.
function layers(build, wpx, hpx, extent, withShadow = true) {
  const out = {};
  for (const pass of ['shadow', 'body', 'gloss']) {
    const sc = baseScene(extent, 0.12);
    const ground = sc.children.find(o => o.material && o.material.isShadowMaterial);
    let m;
    if (pass === 'shadow') m = new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false });
    if (pass !== 'shadow' || !withShadow) ground.visible = false;
    if (pass === 'body') {
      // dimmer light so the top face sits just under white and the sides keep their shading
      sc.traverse(o => { if (o.isLight) o.intensity *= 0.42; });
      m = new THREE.MeshStandardMaterial({ color: '#ffffff', roughness: 0.9, toneMapped: false });
    }
    if (pass === 'gloss') m = new THREE.MeshPhysicalMaterial({ color: '#000000', roughness: 0.25, clearcoat: 0.7, clearcoatRoughness: 0.08, toneMapped: false });
    build(sc, m);
    out[pass] = shoot(sc, wpx, hpx);
  }
  return out;
}

export function cube() {
  return layers((sc, m) => add(sc, new RoundedBoxGeometry(u(CUBE), u(CUBE) * 0.87, u(CUBE), 5, u(CUBE) * 0.22), m, 0, u(CUBE) * 0.435, 0), 140, 140, 2);
}

// A set tray's single glossy slab. vertical = true for trays that face up/down.
export function slab(vertical) {
  const L = u(4 * CELL - 6), Wd = u(CUBE + 2);
  return layers((sc, m) => add(sc, new RoundedBoxGeometry(vertical ? Wd : L, u(CUBE) * 0.84, vertical ? L : Wd, 6, u(18)), m, 0, u(CUBE) * 0.42, 0),
    vertical ? 150 : 380, vertical ? 380 : 150, 4);
}

// Full-color jelly cube, only for comparing a tinted sprite with the mockup.
export function cubeColor(hex) {
  const sc = baseScene(2);
  add(sc, new RoundedBoxGeometry(u(CUBE), u(CUBE) * 0.87, u(CUBE), 5, u(CUBE) * 0.22), gummy(hex), 0, u(CUBE) * 0.435, 0);
  return shoot(sc, 140, 140);
}

// Mint silicone tray. facing is the side of the open end: right, left, up, down.
export function tray(facing) {
  const sc = baseScene(4);
  const g = new THREE.Group(); sc.add(g);
  const trayM = gloss('#bfeadb', { roughness: 0.4, clearcoat: 0.5 });
  const cavM = gloss('#a5dcc9', { roughness: 0.5, clearcoat: 0.2 });
  const L = u(TRAY_LONG), Wd = u(TRAY_WIDE), H = 0.36;
  // built facing right (+x is the open end), then turned
  add(g, new RoundedBoxGeometry(L, 0.22, Wd, 4, 0.1), trayM, 0, 0.11, 0);
  add(g, new RoundedBoxGeometry(L, H, 0.16, 4, 0.07), trayM, 0, H / 2 + 0.05, -Wd / 2 + 0.08);
  add(g, new RoundedBoxGeometry(L, H, 0.16, 4, 0.07), trayM, 0, H / 2 + 0.05, Wd / 2 - 0.08);
  add(g, new RoundedBoxGeometry(0.16, H + 0.04, Wd, 4, 0.07), trayM, -L / 2 + 0.08, (H + 0.04) / 2 + 0.05, 0);
  const back = -L / 2 + u(PAD);
  for (let i = 1; i < 4; i++) add(g, new RoundedBoxGeometry(0.08, H - 0.1, Wd - 0.25, 3, 0.035), trayM, back + u(i * CELL), (H - 0.1) / 2 + 0.1, 0);
  for (let i = 0; i < 4; i++) add(g, new RoundedBoxGeometry(u(CELL) - 0.14, 0.04, Wd - 0.36, 2, 0.02), cavM, back + u((i + 0.5) * CELL), 0.23, 0);
  g.rotation.y = { right: 0, left: Math.PI, up: Math.PI / 2, down: -Math.PI / 2 }[facing];
  const vertical = facing === 'up' || facing === 'down';
  return vertical ? shoot(sc, 160, 400) : shoot(sc, 400, 160);
}

// White ceramic cup seen from above.
const CUP_K = 1.65;
const cupGeo = () => new THREE.LatheGeometry([[0, 0], [0.27, 0], [0.31, 0.03], [0.37, 0.34], [0.4, 0.38], [0.38, 0.41], [0.33, 0.4], [0.29, 0.1], [0, 0.1]]
  .map(([x, y]) => new THREE.Vector2(x * CUP_K, y * CUP_K)), 48);
export function cup() {
  const sc = baseScene(2);
  add(sc, cupGeo(), gloss('#ffffff', { roughness: 0.18, clearcoat: 1 }), 0, 0, 0);
  return shoot(sc, 180, 180);
}

// Jelly filling a cup to the brim with a soft dome, in the same three layers
// as a cube. The cup is there only to hide and shade the jelly; the game draws
// this over cup.png, which already has the shadow, so the shadow layer is empty.
export function cupFill() {
  const pts = [[0, 0.105], [0.285, 0.105], [0.3, 0.2], [0.316, 0.3], [0.326, 0.36], [0.322, 0.39], [0.3, 0.41], [0.25, 0.425], [0.15, 0.434], [0, 0.437]]
    .map(([x, y]) => new THREE.Vector2(x * CUP_K, y * CUP_K));
  const out = layers((sc, m) => {
    add(sc, cupGeo(), new THREE.MeshBasicMaterial({ colorWrite: false }), 0, 0, 0);
    add(sc, new THREE.LatheGeometry(pts, 48), m, 0, 0, 0);
  }, 180, 180, 2, false);
  return out;
}

// --- the oak table ---------------------------------------------------------

function oakTexture() {
  const SZ = 2048, c = document.createElement('canvas'); c.width = c.height = SZ;
  const g = c.getContext('2d');
  let seed = 11; const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const plankH = SZ / 9;
  for (let p = 0; p < 9; p++) {
    const y0 = p * plankH;
    const tones = ['#c9975f', '#bf8c56', '#d0a069', '#ba864f', '#c5935b'];
    g.fillStyle = tones[p % tones.length]; g.fillRect(0, y0, SZ, plankH);
    for (let k = 0; k < 6; k++) {
      const gy = y0 + rnd() * plankH, gh = 10 + rnd() * 40;
      g.fillStyle = `rgba(${rnd() < .5 ? '255,235,200' : '140,90,45'},${0.05 + rnd() * 0.06})`;
      g.fillRect(0, gy, SZ, gh);
    }
    for (let k = 0; k < 46; k++) {
      const base = y0 + rnd() * plankH, amp = 2 + rnd() * 6, freq = 0.002 + rnd() * 0.004, ph = rnd() * 6;
      g.strokeStyle = `rgba(120,72,32,${0.08 + rnd() * 0.16})`; g.lineWidth = 0.8 + rnd() * 1.8;
      g.beginPath();
      for (let x = 0; x <= SZ; x += 16) { const y = base + Math.sin(x * freq + ph) * amp; x ? g.lineTo(x, y) : g.moveTo(x, y); }
      g.stroke();
    }
    for (let k = 0; k < 2; k++) {
      const cx = rnd() * SZ, cy = y0 + plankH * (0.3 + rnd() * 0.4);
      for (let r = 0; r < 7; r++) {
        g.strokeStyle = 'rgba(115,68,30,0.12)'; g.lineWidth = 1.4;
        g.beginPath(); g.ellipse(cx, cy, 120 + r * 26, 14 + r * 6, 0, Math.PI * 0.1, Math.PI * 0.9 + Math.PI); g.stroke();
      }
    }
    for (let k = 0; k < 70; k++) {
      g.fillStyle = `rgba(245,215,170,${0.12 + rnd() * 0.15})`;
      g.fillRect(rnd() * SZ, y0 + rnd() * plankH, 6 + rnd() * 18, 1.5);
    }
    g.fillStyle = 'rgba(70,40,18,0.55)'; g.fillRect(0, y0, SZ, 3);
    g.fillStyle = 'rgba(255,230,190,0.25)'; g.fillRect(0, y0 + 3, SZ, 2);
    const j = rnd() * SZ; g.fillStyle = 'rgba(70,40,18,0.45)'; g.fillRect(j, y0, 3, plankH);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
}

// The table seen through the mockup's camera, filling a 1080 x 2340 phone screen.
export function table() {
  const W = 1080, H = 2340;
  renderer.setSize(W, H, false); canvas.width = W; canvas.height = H;
  const scene = new THREE.Scene();
  scene.environment = envTex; scene.environmentIntensity = 0.4;
  scene.add(new THREE.HemisphereLight('#fff6e8', '#7a5233', 0.55));
  const key = new THREE.DirectionalLight('#fff1dc', 1.9); key.position.set(-6, 20, 9); scene.add(key);
  const plane = new THREE.Mesh(new THREE.PlaneGeometry(34, 34), new THREE.MeshPhysicalMaterial({ map: oakTexture(), roughness: 0.5, clearcoat: 0.35, clearcoatRoughness: 0.35 }));
  plane.rotation.x = -Math.PI / 2; plane.position.z = -1.5;
  scene.add(plane);
  const cam = new THREE.PerspectiveCamera(26, W / H, 0.1, 200);
  cam.position.set(0, 52, 15); cam.lookAt(0, 0, -1.75);
  renderer.setClearColor(0x8a5a33, 1);
  renderer.render(scene, cam);
  renderer.setClearColor(0x000000, 0);
  return canvas.toDataURL('image/png');
}

window.sprites = { cube, cubeColor, slab, tray, cup, cupFill, table };
window.__ready = true;
