// P601 round 2: the Facet command building drawn in Figma with vector shapes only (Plugin API).
// Same projection and light as artgen (ADR 0023): 2:1 dimetric at 2x art px, light from the
// north-west with top 100 %, left 82 %, right 62 %. Nothing here is traced or sampled from any
// reference picture. Run through use_figma against the scratch file "Treadline art - P601".
const OX = 220, OY = 250, Z = 78.38367;
const P = (x, y, z) => [(x - y) * 64 + OX, (x + y) * 32 - z * Z + OY];
const LG = [-0.10, 0.10, 0.28];
const VIEW = [0.6123724, 0.6123724, 0.5];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
const shadeOf = (n) => Math.max(0.42, Math.min(1.04, 0.72 + dot(n, LG)));
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.substr(i, 2), 16) / 255);
const MAT = {
  panel: hex('#2F6FD0'), trim: hex('#1F3358'), gun: hex('#4B5256'), dark: hex('#30363A'),
  worn: hex('#8D9396'), rubber: hex('#25282B'), hazard: hex('#D9B222'), glow: hex('#9FE9FF'),
};
const clamp = (v) => Math.max(0, Math.min(1, v));
const col = (m, s, tint) => {
  const b = MAT[m]; const k = s / 0.82;
  return { r: clamp(b[0] * k * (tint || 1)), g: clamp(b[1] * k * (tint || 1)), b: clamp(b[2] * k * (tint || 1)) };
};
const hash = (a, b, c) => { let v = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791); return (Math.abs(v) % 10007) / 10007; };

const frame = figma.createFrame();
frame.name = 'Facet HQ (vector)';
frame.resize(440, 360);
frame.fills = [];
frame.clipsContent = false;
const page = figma.currentPage;
let count = 0;
const grad = (c1, c2) => ({
  type: 'GRADIENT_LINEAR', gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [{ position: 0, color: { ...c1, a: 1 } }, { position: 1, color: { ...c2, a: 1 } }],
});
function shape(pts2, fills, stroke, sw, opts) {
  const mx = Math.min(...pts2.map((p) => p[0])), my = Math.min(...pts2.map((p) => p[1]));
  const v = figma.createVector();
  frame.appendChild(v);
  const n = pts2.length;
  v.vectorNetwork = {
    vertices: pts2.map((p) => ({ x: p[0] - mx, y: p[1] - my })),
    segments: pts2.map((_, i) => ({ start: i, end: (i + 1) % n })),
    regions: [{ windingRule: 'NONZERO', loops: [pts2.map((_, i) => i)] }],
  };
  v.x = mx; v.y = my;
  v.fills = fills;
  if (stroke) { v.strokes = [{ type: 'SOLID', color: stroke, opacity: (opts && opts.so) || 1 }]; v.strokeWeight = sw || 1; v.strokeJoin = 'ROUND'; } else { v.strokes = []; }
  if (opts && opts.opacity !== undefined) v.opacity = opts.opacity;
  if (opts && opts.effects) v.effects = opts.effects;
  count++;
  return v;
}
function line2(a, b, color, w, op) {
  const v = figma.createVector();
  frame.appendChild(v);
  const mx = Math.min(a[0], b[0]), my = Math.min(a[1], b[1]);
  v.vectorNetwork = { vertices: [{ x: a[0] - mx, y: a[1] - my }, { x: b[0] - mx, y: b[1] - my }], segments: [{ start: 0, end: 1 }], regions: [] };
  v.x = mx; v.y = my; v.fills = [];
  v.strokes = [{ type: 'SOLID', color, opacity: op }]; v.strokeWeight = w; v.strokeCap = 'ROUND';
  count++;
}
const bil = (q, u, v) => [0, 1, 2].map((i) => q[0][i] * (1 - u) * (1 - v) + q[1][i] * u * (1 - v) + q[2][i] * u * v + q[3][i] * (1 - u) * v);
const proj = (p) => P(p[0], p[1], p[2]);

// A side face quad [bottomA, bottomB, topB, topA] with outward normal n, cut into panels.
function panelFace(q, n, m, nu, nv, id, glowy) {
  const s = shadeOf(n);
  const lu = Math.hypot(...sub(q[1], q[0])), lv = Math.hypot(...sub(q[3], q[0]));
  const seam = col(m, s * 0.5);
  shape(q.map(proj), [{ type: 'SOLID', color: seam }], col(m, s * 0.4), 1);
  const gu = 0.013 / lu, gv = 0.013 / lv;
  for (let i = 0; i < nu; i++) {
    for (let j = 0; j < nv; j++) {
      const u0 = i / nu + gu, u1 = (i + 1) / nu - gu, v0 = j / nv + gv, v1 = (j + 1) / nv - gv;
      const pq = [bil(q, u0, v0), bil(q, u1, v0), bil(q, u1, v1), bil(q, u0, v1)];
      const jit = 0.94 + 0.12 * hash(id, i, j);
      const ao = 1 - 0.30 * Math.pow(1 - (j + 0.5) / nv, 2.2);
      const c1 = col(m, s * 1.12 * ao, jit), c2 = col(m, s * 0.90 * ao, jit);
      shape(pq.map(proj), [grad(c1, c2)], null, 0);
      const t0 = proj(pq[3]), t1 = proj(pq[2]);
      line2(t0, t1, col(m, Math.min(1.1, s * 1.5)), 1, 0.55);
      if (nu * nv >= 4) {
        const bolt = proj(bil(pq, 0.1, 0.14));
        shape([[bolt[0] - 0.9, bolt[1]], [bolt[0], bolt[1] - 0.9], [bolt[0] + 0.9, bolt[1]], [bolt[0], bolt[1] + 0.9]], [{ type: 'SOLID', color: col(m, s * 0.4) }], null, 0, { opacity: 0.85 });
      }
    }
  }
}
// A flat plate stood off a face quad by `off` along its normal (a door, a hatch, a vent).
function decal(q, n, u0, u1, v0, v1, off, m, glow) {
  const o = [n[0] * off, n[1] * off, n[2] * off];
  const pq = [bil(q, u0, v0), bil(q, u1, v0), bil(q, u1, v1), bil(q, u0, v1)].map((p) => [p[0] + o[0], p[1] + o[1], p[2] + o[2]]);
  const s = shadeOf(n);
  if (glow) {
    shape(pq.map(proj), [{ type: 'SOLID', color: { r: MAT.glow[0], g: MAT.glow[1], b: MAT.glow[2] } }], null, 0,
      { effects: [{ type: 'DROP_SHADOW', color: { r: 0.4, g: 0.9, b: 1, a: 0.85 }, offset: { x: 0, y: 0 }, radius: 4, spread: 0, visible: true, blendMode: 'NORMAL' }] });
    return;
  }
  shape(pq.map(proj), [grad(col(m, s * 1.1), col(m, s * 0.8))], col(m, s * 0.45), 1);
  line2(proj(pq[3]), proj(pq[2]), col(m, Math.min(1.1, s * 1.5)), 1, 0.5);
}
function hazardStrip(q, n, u0, u1, v0, v1, off, stripes) {
  const o = [n[0] * off, n[1] * off, n[2] * off];
  const base = [bil(q, u0, v0), bil(q, u1, v0), bil(q, u1, v1), bil(q, u0, v1)].map((p) => [p[0] + o[0], p[1] + o[1], p[2] + o[2]]);
  const s = shadeOf(n);
  shape(base.map(proj), [{ type: 'SOLID', color: col('rubber', s) }], col('rubber', s * 0.5), 1);
  for (let k = 0; k < stripes; k++) {
    const a = k / stripes, b = a + 0.5 / stripes;
    const sk = 0.5 / stripes;
    const p = [bil(base, a, 0), bil(base, Math.min(1, b), 0), bil(base, Math.min(1, b + sk), 1), bil(base, Math.min(1, a + sk), 1)];
    shape(p.map(proj), [{ type: 'SOLID', color: col('hazard', s) }], null, 0);
  }
}
function ring(cx, cy, z, R, n, rot) {
  const out = [];
  for (let i = 0; i < n; i++) { const a = ((rot + (360 / n) * i) * Math.PI) / 180; out.push([cx + R * Math.cos(a), cy + R * Math.sin(a), z]); }
  return out;
}
// A frustum: visible side faces as panels, then the top (ring of panels round a cap).
function frustum(cx, cy, n, rot, R0, R1, z0, z1, m, nu, nv, id, topM) {
  const r0 = ring(cx, cy, z0, R0, n, rot), r1 = ring(cx, cy, z1, R1, n, rot);
  const centre = [cx, cy, (z0 + z1) / 2];
  const sides = [];
  for (let k = 0; k < n; k++) {
    const q = [r0[k], r0[(k + 1) % n], r1[(k + 1) % n], r1[k]];
    let nn = norm(cross(sub(q[1], q[0]), sub(q[3], q[0])));
    const mid = bil(q, 0.5, 0.5);
    if (dot(nn, sub(mid, centre)) < 0) nn = nn.map((v) => -v);
    if (dot(nn, VIEW) < 0.03) continue;
    sides.push({ q, n: nn });
  }
  sides.sort((a, b) => dot(a.n, VIEW) - dot(b.n, VIEW));
  const info = [];
  sides.forEach((f, i) => { panelFace(f.q, f.n, m, nu, nv, id * 10 + i, false); info.push(f); });
  // top
  const tm = topM || m, s = shadeOf([0, 0, 1]);
  shape(r1.map(proj), [{ type: 'SOLID', color: col(tm, s * 0.5) }], col(tm, s * 1.4), 1);
  const inner = 0.55;
  for (let k = 0; k < n; k++) {
    const a = r1[k], b = r1[(k + 1) % n];
    const ia = [cx + (a[0] - cx) * inner, cy + (a[1] - cy) * inner, z1], ib = [cx + (b[0] - cx) * inner, cy + (b[1] - cy) * inner, z1];
    const g = 0.015;
    const lerp3 = (p, q2, t) => [p[0] + (q2[0] - p[0]) * t, p[1] + (q2[1] - p[1]) * t, z1];
    const quad = [lerp3(ia, ib, 0.03), lerp3(ia, ib, 0.97), lerp3(a, b, 0.97), lerp3(a, b, 0.03)].map((p) => [cx + (p[0] - cx) * (1 - g * 0), cy + (p[1] - cy) * 1, z1]);
    const jit = 0.95 + 0.1 * hash(id, k, 9);
    shape(quad.map(proj), [grad(col(tm, s * 1.06 * jit), col(tm, s * 0.92 * jit))], null, 0);
  }
  const cap = r1.map((p) => [cx + (p[0] - cx) * (inner - 0.04), cy + (p[1] - cy) * (inner - 0.04), z1]);
  shape(cap.map(proj), [grad(col(tm, s * 1.1), col(tm, s * 0.95))], col(tm, s * 1.4), 1);
  return info;
}
function box(cx, cy, z0, sx, sy, sz, m, id, nu, nv) {
  const x0 = cx - sx / 2, x1 = cx + sx / 2, y0 = cy - sy / 2, y1 = cy + sy / 2, z1 = z0 + sz;
  const faces = [];
  // +y face (left on screen), +x face (right), top
  const left = [[x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1]];
  const right = [[x1, y1, z0], [x1, y0, z0], [x1, y0, z1], [x1, y1, z1]];
  const nl = [0, 1, 0], nr = [1, 0, 0];
  const big = (a, b) => Math.max(1, Math.round(Math.hypot(...sub(a, b)) / 0.22));
  panelFace(left, nl, m, nu || big(left[0], left[1]), nv || 1, id, false);
  panelFace(right, nr, m, nu || big(right[0], right[1]), nv || 1, id + 1, false);
  const s = shadeOf([0, 0, 1]);
  const top = [[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]];
  shape(top.map(proj), [grad(col(m, s * 1.08), col(m, s * 0.94))], col(m, s * 1.45), 1);
  return { left, right, nl, nr };
}

// ---- scene ----
const R = 1.45;
// soft contact shadow (one vector, blurred)
const sh = [];
for (let i = 0; i < 6; i++) { const a = ((15 + 60 * i) * Math.PI) / 180; sh.push(P(R * 1.05 * Math.cos(a) + 0.35, R * 1.05 * Math.sin(a) + 0.35, 0)); }
shape(sh, [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }], null, 0, { opacity: 0.38, effects: [{ type: 'LAYER_BLUR', blurType: 'NORMAL', radius: 9, visible: true }] });
// apron
box(0, 0, 0, 2.92, 2.92, 0.05, 'dark', 100, 6, 1);
// hazard edging on the apron front (+x and +y edges, flat on top)
for (let i = 0; i < 12; i++) {
  if (i % 2) continue;
  const a = -1.32 + i * 0.22;
  shape([P(1.30, a, 0.05), P(1.42, a, 0.05), P(1.42, a + 0.2, 0.05), P(1.30, a + 0.2, 0.05)], [{ type: 'SOLID', color: col('hazard', 1.0) }], null, 0);
  shape([P(a, 1.30, 0.05), P(a + 0.2, 1.30, 0.05), P(a + 0.2, 1.42, 0.05), P(a, 1.42, 0.05)], [{ type: 'SOLID', color: col('hazard', 1.0) }], null, 0);
}
// back and side pylons first
const pylons = [[-1.1, -1.1], [1.1, -1.1], [-1.1, 1.1], [1.1, 1.1]];
const pylon = (cx, cy, id) => {
  box(cx, cy, 0.05, 0.44, 0.44, 0.22, 'gun', id, 2, 1);
  frustum(cx, cy, 4, 45, 0.30, 0.20, 0.27, 0.40, 'panel', 1, 1, id + 5, 'panel');
  const o = proj([cx, cy, 0.41]);
  shape([[o[0] - 4, o[1]], [o[0], o[1] - 2], [o[0] + 4, o[1]], [o[0], o[1] + 2]], [{ type: 'SOLID', color: { r: MAT.glow[0], g: MAT.glow[1], b: MAT.glow[2] } }], null, 0,
    { effects: [{ type: 'DROP_SHADOW', color: { r: 0.4, g: 0.9, b: 1, a: 0.85 }, offset: { x: 0, y: 0 }, radius: 4, spread: 0, visible: true, blendMode: 'NORMAL' }] });
};
pylon(...pylons[0], 120);
pylon(...pylons[1], 130);
pylon(...pylons[2], 140);
// hall: three hexagonal tiers, trim bands between
frustum(0, 0, 6, 15, R * 1.08, R * 1.08, 0.05, 0.10, 'dark', 3, 1, 1, 'dark');
const t1 = frustum(0, 0, 6, 15, R, R * 0.95, 0.10, 0.44, 'panel', 3, 2, 2, 'trim');
frustum(0, 0, 6, 15, R * 1.06, R * 1.06, 0.44, 0.52, 'trim', 3, 1, 3, 'trim');
frustum(0, 0, 6, 15, R * 0.93, R * 0.74, 0.52, 0.90, 'panel', 3, 3, 4, 'trim');
frustum(0, 0, 6, 15, R * 0.80, R * 0.80, 0.90, 0.97, 'trim', 2, 1, 5, 'trim');
frustum(0, 0, 6, 15, R * 0.70, R * 0.48, 0.97, 1.30, 'panel', 3, 3, 6, 'dark');
// ledge vents on the trim band ledge
frustum(0, 0, 6, 15, R * 0.36, R * 0.30, 1.30, 1.40, 'gun', 2, 1, 7, 'dark');
frustum(0, 0, 6, 15, R * 0.28, R * 0.12, 1.40, 1.62, 'dark', 2, 2, 8, 'gun');
shape([P(0, 0, 1.62), P(0.07, 0, 1.62), P(0.07, 0.07, 1.62), P(0, 0.07, 1.62)], [{ type: 'SOLID', color: col('worn', 0.9) }], null, 0);
// mast
const m0 = proj([0, 0, 1.62]), m1 = proj([0, 0, 2.05]);
line2(m0, m1, col('worn', 0.82), 3, 1);
decal([[-0.05, 0, 2.0], [0.05, 0, 2.0], [0.05, 0, 2.08], [-0.05, 0, 2.08]], [0, 1, 0], 0, 1, 0, 1, 0, 'trim', false);
decal([[-0.04, 0, 2.08], [0.04, 0, 2.08], [0.04, 0, 2.13], [-0.04, 0, 2.13]], [0, 1, 0], 0, 1, 0, 1, 0, 'worn', true);
// gate on the face that looks at the camera (largest facing, normal 45 degrees)
const front = t1.slice().sort((a, b) => dot(b.n, VIEW) - dot(a.n, VIEW))[1];
hazardStrip(front.q, front.n, 0.30, 0.70, 0.0, 0.07, 0.012, 14);
decal(front.q, front.n, 0.30, 0.70, 0.07, 0.62, 0.015, 'rubber', false);
decal(front.q, front.n, 0.34, 0.36, 0.14, 0.52, 0.02, 'rubber', true);
decal(front.q, front.n, 0.64, 0.66, 0.14, 0.52, 0.02, 'rubber', true);
decal(front.q, front.n, 0.46, 0.54, 0.40, 0.52, 0.02, 'rubber', true);
for (const [a, b] of [[0.08, 0.24], [0.76, 0.92]]) decal(front.q, front.n, a, b, 0.10, 0.80, 0.02, 'gun', false);
// front pylon
pylon(...pylons[3], 150);
return { children: frame.children.length, shapes: count, frameId: frame.id, w: frame.width, h: frame.height };
