// Generates reference results from the first version of the tool (../shadow, JavaScript) so the Zig calculation can
// be compared with it. Run from this directory with Node:  node gen_reference.js /home/erdem/project/shadow
'use strict';
const path = require('path');
const fs = require('fs');
const root = process.argv[2] || '/home/erdem/project/shadow';
const B = require(path.join(root, 'bottle.js'));
const C = require(path.join(root, 'candle.js'));

// Same deterministic pseudo-random sequence as the Zig tests (LCG), so sample positions match.
function rng(seed) { let s = seed >>> 0; return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; }; }

// Analytic test images (no image decoding needed): smooth tones and hard edges.
const samplers = {
  smooth: (u, v) => 0.5 + 0.5 * Math.sin(9 * u) * Math.cos(7 * v),
  edges: (u, v) => ((Math.floor(u * 7) + Math.floor(v * 5)) % 2) ? 0.9 : 0.1,
  rings: (u, v) => { const d = Math.hypot(u - 0.5, v - 0.5); return (d > 0.18 && d < 0.3) || (d > 0.38 && d < 0.46) ? 1 : 0; }
};

const lampBase = {
  dia: 70, len: 120, glass: 3, n: 1.52, s: 20, gd: 6, rimW: 4, frontT: 12, plugDepth: 16, cableD: 3, cableAngle: 270,
  lx: 0, ly: 0, iw: 400, ix: 0, iy: 0, aspect: 1, dpi: 100, seam: 270, mode: 'binary', threshold: 0.5, gamma: 1,
  invert: false, htPattern: 'dot', grid: 'film', pitch: 2, fill: 1, htAngle: 0, waveAmp: 1, waveLen: 8, front: 'black', surface: 'film'
};
const lampCases = [
  { name: 'binary_edges', sampler: 'edges', p: {} },
  { name: 'binary_rings_invert', sampler: 'rings', p: { invert: true, threshold: 0.4 } },
  { name: 'dots_film', sampler: 'smooth', p: { mode: 'halftone', pitch: 3 } },
  { name: 'lines_wall_angle', sampler: 'smooth', p: { mode: 'halftone', htPattern: 'lines', grid: 'wall', pitch: 8, htAngle: 30 } },
  { name: 'wavy_gamma', sampler: 'smooth', p: { mode: 'halftone', htPattern: 'wavy', pitch: 4, gamma: 1.6, waveAmp: 2, waveLen: 10 } },
  { name: 'spiral_wall_front_clear', sampler: 'smooth', p: { mode: 'halftone', htPattern: 'spiral', grid: 'wall', pitch: 12, front: 'clear' } },
  { name: 'offcenter_noglass', sampler: 'edges', p: { lx: 4, ly: -3, glass: 0, dia: 80, len: 140, iw: 500, ix: 30, iy: -20, aspect: 0.75, seam: 0 } },
  { name: 'warnings_small', sampler: 'edges', p: { dia: 40, len: 40, s: 10, gd: 6, frontT: 5, plugDepth: 6 } }
];

const candleBase = {
  dia: 70, glass: 3, n: 1.52, gb: 0, gh: 150, cd: 34, hd: 60, fwid: 10, fhei: 30, seam: 0, source: 'real', unused: 'black',
  iw: 500, ix: 0, iy: 0, aspect: 1, dpi: 100, mode: 'binary', threshold: 0.5, gamma: 1, invert: false,
  htPattern: 'dot', grid: 'film', pitch: 3.5, fill: 1, htAngle: 0, waveAmp: 1, waveLen: 8
};
const candleCases = [
  { name: 'binary_rings', sampler: 'rings', p: {} },
  { name: 'dots_film', sampler: 'smooth', p: { mode: 'halftone' } },
  { name: 'rings_surface_unused_clear', sampler: 'smooth', p: { mode: 'halftone', htPattern: 'rings', grid: 'wall', pitch: 10, unused: 'clear' } },
  { name: 'led_low', sampler: 'edges', p: { source: 'led', cd: 38, hd: 30, fhei: 15, gb: 5 } },
  { name: 'warnings_real', sampler: 'smooth', p: { dia: 50, cd: 30, hd: 20, fhei: 40, gh: 50 } },
  { name: 'warnings_led', sampler: 'smooth', p: { source: 'led', dia: 40, cd: 34 } }
];

function samplePixels(film, seed, n) {
  const r = rng(seed), out = [];
  for (let k = 0; k < n; k++) { const i = Math.floor(r() * film.data.length); out.push([i, film.data[i]]); }
  return out;
}
const sum = a => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i]; return s; };

const out = { lamp: [], candle: [], screens: [], png: null };

for (const c of lampCases) {
  const p = Object.assign({}, lampBase, c.p);
  p.lz = B.ledZ(p);
  const res = B.compute(p, samplers[c.sampler]);
  const f = res.film, Bt = res.B, rnd = rng(7);
  const filmToWall = [], lit = [];
  for (let k = 0; k < 300; k++) {
    const u = rnd() * Bt.circ, v = rnd() * (Bt.z1 - Bt.z0);
    const P = B.filmPoint(Bt, u, v), Q = B.filmToWall(Bt, P);
    filmToWall.push([u, v, Q ? Q[0] : null, Q ? Q[1] : null]);
  }
  for (let k = 0; k < 400; k++) {
    const qx = (rnd() - 0.5) * 700, qy = (rnd() - 0.5) * 700;
    const h = B.wallToFilm(Bt, qx, qy);
    lit.push([qx, qy, B.litAt(res, qx, qy), B.penumbraAt(res, qx, qy, 2), h ? h.P : null]);
  }
  out.lamp.push({
    name: c.name, sampler: c.sampler, p, w: f.w, h: f.h, px: f.px, open: sum(f.data), shadow: sum(f.shadow),
    pixels: samplePixels(f, 11, 3000), filmToWall, lit, innerRadius: B.innerRadius(Bt),
    dims: B.baseDims(p), warnings: B.baseWarnings(p, B.baseDims(p)), svg: B.buildBaseSVG(p)
  });
}

for (const c of candleCases) {
  const p = Object.assign({}, candleBase, c.p);
  const res = C.compute(p, samplers[c.sampler]);
  const f = res.film, rnd = rng(13), lit = [];
  for (let k = 0; k < 400; k++) {
    const tx = (rnd() - 0.5) * 600, ty = (rnd() - 0.5) * 600;
    const L = [(rnd() - 0.5) * 6, (rnd() - 0.5) * 6, p.hd + (rnd() - 0.5) * 20];
    lit.push([tx, ty, L, C.litAt(res, tx, ty, L), C.blurAt(res, tx, ty, p.fwid)]);
  }
  out.candle.push({
    name: c.name, sampler: c.sampler, p, w: f.w, h: f.h, px: f.px, open: sum(f.data),
    pixels: samplePixels(f, 17, 3000), lit, innerRadius: C.innerRadius(p, p.hd), warnings: C.warnings(p)
  });
}

// Halftone screens on their own: exact boolean results on random points.
for (const pat of ['dot', 'square', 'lines', 'wavy', 'cross', 'rings', 'spiral']) {
  const p = { htPattern: pat, pitch: 5, fill: 0.9, htAngle: 20, waveAmp: 1.5, waveLen: 9 };
  const s = B.makeScreen(p), rnd = rng(23), pts = [];
  for (let k = 0; k < 2000; k++) { const a = (rnd() - 0.5) * 200, b = (rnd() - 0.5) * 200, t = rnd(); pts.push([a, b, t, s(a, b, t) ? 1 : 0]); }
  out.screens.push({ p, pts });
}

// PNG with dpi: a tiny 1x1 PNG.
const png1 = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000' + '1f15c4890000000d49444154789c6360f8cfc0f01f0005000201' + '5e1b3a8a0000000049454e44ae426082', 'hex');
out.png = { input: png1.toString('hex'), dpi: 300, output: Buffer.from(B.pngWithDpi(png1.buffer.slice(png1.byteOffset, png1.byteOffset + png1.length), 300)).toString('hex') };

fs.writeFileSync(path.join(__dirname, 'reference.json'), JSON.stringify(out));
console.log('lamp', out.lamp.map(c => c.name + ' ' + c.w + 'x' + c.h + ' open ' + c.open).join(', '));
console.log('candle', out.candle.map(c => c.name + ' ' + c.w + 'x' + c.h + ' open ' + c.open).join(', '));
console.log('size', fs.statSync(path.join(__dirname, 'reference.json')).size);
