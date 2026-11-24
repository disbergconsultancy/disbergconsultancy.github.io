// Bakes the base colour texture into vertex colours, drops UVs and textures, welds and
// simplifies to a target triangle count, recomputes normals. Usage: node bake.mjs in.glb out.glb 10000
import { NodeIO } from '@gltf-transform/core';
import { weld, simplify, prune, dedup } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
const [,, src, dst, target] = process.argv;
const io = new NodeIO();
const doc = await io.read(src);
await MeshoptSimplifier.ready;
let before = 0;
for (const mesh of doc.getRoot().listMeshes()) for (const prim of mesh.listPrimitives()) {
  const mat = prim.getMaterial();
  const tex = mat.getBaseColorTexture();
  const img = await sharp(Buffer.from(tex.getImage())).raw().ensureAlpha().toBuffer({ resolveWithObject: true });
  const { width: w, height: h } = img.info;
  const uv = prim.getAttribute('TEXCOORD_0'); const n = uv.getCount();
  const col = new Float32Array(n * 4); const t = [0, 0];
  for (let i = 0; i < n; i++) {
    uv.getElement(i, t);
    const x = Math.min(w - 1, Math.max(0, Math.floor(t[0] * w))), y = Math.min(h - 1, Math.max(0, Math.floor(t[1] * h)));
    const o = (y * w + x) * 4;
    for (let c = 0; c < 3; c++) col[i * 4 + c] = img.data[o + c] / 255;   // kept as stored (Godot shows vertex colours as given)
    col[i * 4 + 3] = 1;
  }
  const acc = doc.createAccessor().setType('VEC4').setArray(col).setBuffer(uv.getBuffer());
  prim.setAttribute('COLOR_0', acc);
  prim.setAttribute('TEXCOORD_0', null); prim.setAttribute('NORMAL', null);
  before += prim.getIndices().getCount() / 3;
  mat.setBaseColorTexture(null).setNormalTexture(null).setMetallicRoughnessTexture(null).setMetallicFactor(0).setRoughnessFactor(1);
}
await doc.transform(weld(), dedup());
let ratio = Number(target) / before;
await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.05 }), prune());
// smooth normals: sum the (area-weighted) face normals at each vertex
for (const mesh of doc.getRoot().listMeshes()) for (const prim of mesh.listPrimitives()) {
  const pos = prim.getAttribute('POSITION'), idx = prim.getIndices().getArray(), n = pos.getCount();
  const P = pos.getArray(), N = new Float32Array(n * 3);
  for (let i = 0; i < idx.length; i += 3) {
    const a = idx[i] * 3, b = idx[i + 1] * 3, c = idx[i + 2] * 3;
    const ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2];
    const vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2];
    const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    for (const v of [a, b, c]) { N[v] += nx; N[v + 1] += ny; N[v + 2] += nz; }
  }
  for (let i = 0; i < n; i++) { const l = Math.hypot(N[i*3], N[i*3+1], N[i*3+2]) || 1; N[i*3] /= l; N[i*3+1] /= l; N[i*3+2] /= l; }
  prim.setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(N).setBuffer(pos.getBuffer()));
}
let after = 0;
for (const mesh of doc.getRoot().listMeshes()) for (const prim of mesh.listPrimitives()) after += prim.getIndices().getCount() / 3;
await io.write(dst, doc);
console.log(`${src.split('/').pop()}: ${before} -> ${after} triangles`);
