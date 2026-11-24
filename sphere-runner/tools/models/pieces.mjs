// Lists the connected pieces of the mesh (vertices joined by position), with size and main bone.
import { NodeIO } from '@gltf-transform/core';
const [,, src] = process.argv;
const doc = await new NodeIO().read(src);
const prim = doc.getRoot().listMeshes()[0].listPrimitives()[0];
const P = prim.getAttribute('POSITION').getArray(), I = prim.getIndices().getArray();
const J = prim.getAttribute('JOINTS_0').getArray(), Wt = prim.getAttribute('WEIGHTS_0').getArray();
const joints = doc.getRoot().listSkins()[0].listJoints().map(j => j.getName().replace('mixamorig:', ''));
const n = P.length / 3, key = i => P[i*3].toFixed(4) + ',' + P[i*3+1].toFixed(4) + ',' + P[i*3+2].toFixed(4);
const par = [...Array(n).keys()], find = x => { while (par[x] !== x) x = par[x] = par[par[x]]; return x; }, uni = (a, b) => { a = find(a); b = find(b); if (a !== b) par[a] = b; };
const byPos = new Map(); for (let i = 0; i < n; i++) { const k = key(i); if (byPos.has(k)) uni(i, byPos.get(k)); else byPos.set(k, i); }
for (let t = 0; t < I.length; t += 3) { uni(I[t], I[t+1]); uni(I[t], I[t+2]); }
const comps = new Map();
for (let t = 0; t < I.length; t += 3) { const r = find(I[t]); if (!comps.has(r)) comps.set(r, { tris: 0, min: [9,9,9], max: [-9,-9,-9], bones: {} }); const c = comps.get(r); c.tris++;
  for (const v of [I[t], I[t+1], I[t+2]]) { for (let a = 0; a < 3; a++) { c.min[a] = Math.min(c.min[a], P[v*3+a]); c.max[a] = Math.max(c.max[a], P[v*3+a]); }
    for (let k = 0; k < 4; k++) if (Wt[v*4+k] > 0.3) c.bones[joints[J[v*4+k]]] = (c.bones[joints[J[v*4+k]]] || 0) + 1; } }
const list = [...comps.values()].sort((a, b) => b.tris - a.tris);
list.forEach((c, i) => { const top = Object.entries(c.bones).sort((a, b) => b[1] - a[1]).slice(0, 2).map(e => e[0]).join('+');
  console.log(`#${i} tris ${c.tris}  size ${c.max.map((v, a) => (v - c.min[a]).toFixed(2)).join(' x ')}  centre ${c.max.map((v, a) => ((v + c.min[a]) / 2).toFixed(2)).join(',')}  bones ${top}`); });
