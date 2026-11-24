// Recolours a hero's base colour texture: the red accents (scarf, belt) take a new hue, the dark
// cloth becomes a lighter tone (grey, white...), keeping each pixel's shading. Skin and light
// parts stay. Usage: node recolor.mjs in.glb out.glb <accent hue 0-1> <accent sat x> <cloth: "r,g,b" light tone> <cloth strength 0-1>
import { NodeIO } from '@gltf-transform/core';
import sharp from 'sharp';
const [,, src, dst, hueA, satA, clothRGB, clothK] = process.argv;
const doc = await new NodeIO().read(src);
const tex = doc.getRoot().listMaterials()[0].getBaseColorTexture();
const { data, info } = await sharp(Buffer.from(tex.getImage())).raw().removeAlpha().toBuffer({ resolveWithObject: true });
const tone = clothRGB.split(',').map(Number), K = Number(clothK), HA = Number(hueA), SA = Number(satA);
const sm = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
function hsv(r, g, b) { const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; let h = 0;
  if (d) h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6; if (h < 0) h += 1; return [h, mx ? d / mx : 0, mx]; }
function rgb(h, s, v) { const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][((i % 6) + 6) % 6]; }
const out = Buffer.alloc(data.length);
for (let i = 0; i < data.length; i += 3) {
  let r = data[i] / 255, g = data[i + 1] / 255, b = data[i + 2] / 255;
  const [h, s, v] = hsv(r, g, b);
  const hd = Math.min(h, 1 - h);                                    // distance from red
  const wRed = sm(0.18, 0.38, s) * sm(0.12, 0.07, hd) * sm(0.07, 0.16, v);
  const skin = sm(0.15, 0.3, s) * sm(0.03, 0.06, h) * sm(0.14, 0.10, h) * sm(0.35, 0.5, v);
  const wCloth = sm(0.62, 0.45, v) * (1 - wRed) * (1 - skin);
  let o = [r, g, b];
  if (wRed > 0) { const n = rgb(HA, Math.min(1, s * SA), Math.min(1, v * 1.1)); o = o.map((c, k) => c + (n[k] - c) * wRed); }
  if (wCloth > 0 && K > 0) {                                        // keep the shading: brightness relative to the cloth's
    const shade = Math.min(1.25, 0.45 + v * 1.6);
    const n = tone.map(c => Math.min(1, c * shade));
    o = o.map((c, k) => c + (n[k] - c) * wCloth * K);
  }
  for (let k = 0; k < 3; k++) out[i + k] = Math.round(Math.max(0, Math.min(1, o[k])) * 255);
}
const jpg = await sharp(out, { raw: { width: info.width, height: info.height, channels: 3 } }).jpeg({ quality: 92 }).toBuffer();
tex.setImage(new Uint8Array(jpg)).setMimeType('image/jpeg');
await new NodeIO().write(dst, doc);
console.log('recoloured', dst.split('/').pop());
