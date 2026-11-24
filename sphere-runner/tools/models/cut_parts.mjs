// Finds blade pieces: triangles far from every body bone segment (bind pose), grouped into
// connected clusters. mode "show": paint each cluster a flat colour; mode "cut": remove the
// listed clusters (and the flat floor shards). Usage: node blades.mjs in.glb out.glb show|cut [keep ids...]
import { NodeIO } from '@gltf-transform/core';
const [,, src, dst, mode, ...keepArg] = process.argv;
const keep = new Set(keepArg.map(Number));
const doc = await new NodeIO().read(src);
const root = doc.getRoot();
const prim = root.listMeshes()[0].listPrimitives()[0];
const P = prim.getAttribute('POSITION').getArray(), I = prim.getIndices().getArray();
const skin = root.listSkins()[0], joints = skin.listJoints(), ibm = skin.getInverseBindMatrices().getArray();
// joint bind positions = translation of inverse(IBM)
function inv4(m) { const a = Array.from(m), r = new Array(16).fill(0);  // general 4x4 inverse
  const s0 = a[0]*a[5]-a[4]*a[1], s1 = a[0]*a[6]-a[4]*a[2], s2 = a[0]*a[7]-a[4]*a[3], s3 = a[1]*a[6]-a[5]*a[2], s4 = a[1]*a[7]-a[5]*a[3], s5 = a[2]*a[7]-a[6]*a[3];
  const c5 = a[10]*a[15]-a[14]*a[11], c4 = a[9]*a[15]-a[13]*a[11], c3 = a[9]*a[14]-a[13]*a[10], c2 = a[8]*a[15]-a[12]*a[11], c1 = a[8]*a[14]-a[12]*a[10], c0 = a[8]*a[13]-a[12]*a[9];
  const d = 1 / (s0*c5 - s1*c4 + s2*c3 + s3*c2 - s4*c1 + s5*c0);
  r[12] = (-a[4]*c3 + a[5]*c1 - a[6]*c0) * d; r[13] = (a[0]*c3 - a[1]*c1 + a[2]*c0) * d; r[14] = (-a[12]*s3 + a[13]*s1 - a[14]*s0) * d; return r; }
const pos = joints.map((j, i) => { const r = inv4(ibm.slice(i * 16, i * 16 + 16)); return [r[12], r[13], r[14]]; });
const name = joints.map(j => j.getName().replace('mixamorig:', ''));
const idxOf = new Map(name.map((n, i) => [n, i]));
const parentOf = new Map(); for (const n of root.listNodes()) for (const c of n.listChildren()) parentOf.set(c, n);
// body segments (no fingers): parent joint -> joint, with a radius per region
const segs = [];
joints.forEach((j, i) => { const p = parentOf.get(j); const pi = joints.indexOf(p); if (pi < 0) return;
  const n = name[i]; if (/Hand(Index|Middle|Ring|Pinky|Thumb)/.test(n) || /Toe_End|HeadTop_End/.test(n)) return;
  const r = /Spine|Hips|Neck|Shoulder/.test(n) ? 0.16 : /Head/.test(n) ? 0.17 : /UpLeg|Leg/.test(n) ? 0.12 : /Foot|Toe/.test(n) ? 0.09 : /Hand/.test(n) ? 0.07 : 0.085;
  segs.push([pos[pi], pos[i], r, n]); });
segs.push([pos[idxOf.get('Head')], [pos[idxOf.get('Head')][0], pos[idxOf.get('Head')][1] + 0.12, pos[idxOf.get('Head')][2]], 0.17, 'HeadTop']);
function segDist(p, a, b) { const ab = [b[0]-a[0], b[1]-a[1], b[2]-a[2]], ap = [p[0]-a[0], p[1]-a[1], p[2]-a[2]];
  const L = ab[0]*ab[0] + ab[1]*ab[1] + ab[2]*ab[2]; const t = L ? Math.max(0, Math.min(1, (ap[0]*ab[0] + ap[1]*ab[1] + ap[2]*ab[2]) / L)) : 0;
  return Math.hypot(ap[0] - ab[0]*t, ap[1] - ab[1]*t, ap[2] - ab[2]*t); }
const n = P.length / 3, far = new Uint8Array(n);
for (let v = 0; v < n; v++) { const p = [P[v*3], P[v*3+1], P[v*3+2]]; far[v] = segs.every(([a, b, r]) => segDist(p, a, b) > r) ? 1 : 0; }
// floor shards
const tris = I.length / 3, isFloor = new Uint8Array(tris), isFar = new Uint8Array(tris);
for (let t = 0; t < tris; t++) { const vs = [I[t*3], I[t*3+1], I[t*3+2]];
  if (Math.max(...vs.map(v => P[v*3+1])) < 0.01) isFloor[t] = 1;
  else if (vs.filter(v => far[v]).length >= 2) isFar[t] = 1; }
// clusters of far triangles (connected by shared positions)
const key = v => P[v*3].toFixed(4) + ',' + P[v*3+1].toFixed(4) + ',' + P[v*3+2].toFixed(4);
const par = [...Array(tris).keys()], find = x => { while (par[x] !== x) x = par[x] = par[par[x]]; return x; };
const owner = new Map();
for (let t = 0; t < tris; t++) if (isFar[t]) for (let k = 0; k < 3; k++) { const kk = key(I[t*3+k]); if (owner.has(kk)) { const a = find(t), b = find(owner.get(kk)); if (a !== b) par[a] = b; } else owner.set(kk, t); }
const groups = new Map();
for (let t = 0; t < tris; t++) if (isFar[t]) { const r = find(t); if (!groups.has(r)) groups.set(r, []); groups.get(r).push(t); }
const list = [...groups.values()].filter(g => g.length >= 6).sort((a, b) => b.length - a.length);
const cid = new Int32Array(tris).fill(-1); list.forEach((g, i) => g.forEach(t => cid[t] = i));
const COLS = [[1,0,1],[0,1,1],[1,1,0],[0,1,0],[1,0.5,0],[0.3,0.3,1],[1,0,0],[1,1,1]];
list.forEach((g, i) => { const mn = [9,9,9], mx = [-9,-9,-9]; for (const t of g) for (let k = 0; k < 3; k++) { const v = I[t*3+k]; for (let a = 0; a < 3; a++) { mn[a] = Math.min(mn[a], P[v*3+a]); mx[a] = Math.max(mx[a], P[v*3+a]); } }
  console.log(`cluster ${i} (${['magenta','cyan','yellow','green','orange','blue','red','white'][i % 8]}): ${g.length} tris, from ${mn.map(x => x.toFixed(2))} to ${mx.map(x => x.toFixed(2))}`); });
console.log(`floor shards: ${isFloor.reduce((a, b) => a + b, 0)} tris; far tris in small bits: ${isFar.reduce((a, b) => a + b, 0) - list.reduce((a, g) => a + g.length, 0)}`);
if (mode === 'show') {
  const col = new Float32Array(n * 4).fill(1);
  for (let t = 0; t < tris; t++) if (cid[t] >= 0) for (let k = 0; k < 3; k++) col.set([...COLS[cid[t] % 8], 1], I[t*3+k] * 4);
  prim.setAttribute('COLOR_0', doc.createAccessor().setType('VEC4').setArray(col).setBuffer(prim.getAttribute('POSITION').getBuffer()));
} else {
  const out = []; for (let t = 0; t < tris; t++) { if (isFloor[t]) continue; if (cid[t] >= 0 && !keep.has(cid[t])) continue; out.push(I[t*3], I[t*3+1], I[t*3+2]); }
  prim.getIndices().setArray(n > 65535 ? new Uint32Array(out) : new Uint16Array(out));
  console.log(`kept ${out.length / 3} of ${tris} triangles`);
}
await new NodeIO().write(dst, doc);
