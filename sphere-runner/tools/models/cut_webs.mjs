// Finds triangles that would stretch between limbs: their corners are mostly driven by
// different limbs (an arm and a leg, or the two legs). Usage: node webs.mjs in.glb out.glb show|cut
import { NodeIO } from '@gltf-transform/core';
const [,, src, dst, mode] = process.argv;
const doc = await new NodeIO().read(src);
const prim = doc.getRoot().listMeshes()[0].listPrimitives()[0];
const P = prim.getAttribute('POSITION').getArray(), I = prim.getIndices().getArray();
const J = prim.getAttribute('JOINTS_0').getArray(), W = prim.getAttribute('WEIGHTS_0').getArray();
const names = doc.getRoot().listSkins()[0].listJoints().map(j => j.getName().replace('mixamorig:', ''));
const limb = n => /^Left(Arm|ForeArm|Hand)/.test(n) ? 'armL' : /^Right(Arm|ForeArm|Hand)/.test(n) ? 'armR'
  : /^Left(UpLeg|Leg|Foot|Toe)/.test(n) ? 'legL' : /^Right(UpLeg|Leg|Foot|Toe)/.test(n) ? 'legR' : 'body';
const vlimb = v => { const acc = {}; for (let k = 0; k < 4; k++) { const l = limb(names[J[v*4+k]]); acc[l] = (acc[l] || 0) + W[v*4+k]; }
  let best = 'body', bw = 0; for (const l in acc) if (acc[l] > bw) { best = l; bw = acc[l]; } return [best, bw]; };
const tris = I.length / 3, hit = new Uint8Array(tris); let count = 0; const kinds = {};
for (let t = 0; t < tris; t++) {
  const ls = [I[t*3], I[t*3+1], I[t*3+2]].map(vlimb);
  const set = new Set(ls.filter(([l, w]) => l !== 'body' && w > 0.6).map(([l]) => l));
  if (set.size >= 2) { hit[t] = 1; count++; const k = [...set].sort().join('+'); kinds[k] = (kinds[k] || 0) + 1; }
}
console.log(`stretching triangles: ${count}`, kinds);
if (mode === 'show') {
  const n = P.length / 3, col = new Float32Array(n * 4).fill(1);
  for (let t = 0; t < tris; t++) if (hit[t]) for (let k = 0; k < 3; k++) col.set([1, 0, 1, 1], I[t*3+k] * 4);
  prim.setAttribute('COLOR_0', doc.createAccessor().setType('VEC4').setArray(col).setBuffer(prim.getAttribute('POSITION').getBuffer()));
} else {
  const out = []; for (let t = 0; t < tris; t++) if (!hit[t]) out.push(I[t*3], I[t*3+1], I[t*3+2]);
  prim.getIndices().setArray(new Uint16Array(out));
}
await new NodeIO().write(dst, doc);
