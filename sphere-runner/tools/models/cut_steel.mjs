// Marks (show) or removes (cut) triangles whose texture colour is light steel (bright, unsaturated)
// below the face (y < maxY). Usage: node steel.mjs in.glb out.glb show|cut [maxY]
import { NodeIO } from '@gltf-transform/core';
import sharp from 'sharp';
const [,, src, dst, mode, maxYArg] = process.argv;
const maxY = Number(maxYArg || 0.55);
const doc = await new NodeIO().read(src);
const prim = doc.getRoot().listMeshes()[0].listPrimitives()[0];
const P = prim.getAttribute('POSITION').getArray(), UV = prim.getAttribute('TEXCOORD_0').getArray(), I = prim.getIndices().getArray();
const img = await sharp(Buffer.from(prim.getMaterial().getBaseColorTexture().getImage())).raw().ensureAlpha().toBuffer({ resolveWithObject: true });
const { width: w, height: h } = img.info;
const steel = v => { const x = Math.min(w - 1, Math.floor(UV[v*2] * w)), y = Math.min(h - 1, Math.floor(UV[v*2+1] * h)), o = (y * w + x) * 4;
  const r = img.data[o], g = img.data[o+1], b = img.data[o+2], mx = Math.max(r, g, b), mn = Math.min(r, g, b);
  return mx > 120 && (mx - mn) < 60; };
const tris = I.length / 3, hit = new Uint8Array(tris);
let count = 0;
for (let t = 0; t < tris; t++) { const vs = [I[t*3], I[t*3+1], I[t*3+2]];
  if (vs.every(v => P[v*3+1] < maxY && P[v*3+1] > 0.07) && vs.filter(steel).length >= 2) { hit[t] = 1; count++; } }
console.log(`steel triangles below y ${maxY}: ${count} of ${tris}`);
if (mode === 'show') {
  const n = P.length / 3, col = new Float32Array(n * 4).fill(1);
  for (let t = 0; t < tris; t++) if (hit[t]) for (let k = 0; k < 3; k++) col.set([1, 0, 1, 1], I[t*3+k] * 4);
  prim.setAttribute('COLOR_0', doc.createAccessor().setType('VEC4').setArray(col).setBuffer(prim.getAttribute('POSITION').getBuffer()));
} else {
  const out = []; for (let t = 0; t < tris; t++) if (!hit[t]) out.push(I[t*3], I[t*3+1], I[t*3+2]);
  prim.getIndices().setArray(new Uint16Array(out));
}
await new NodeIO().write(dst, doc);
