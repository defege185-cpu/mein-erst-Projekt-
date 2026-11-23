// Tests automatiques : node --test tests/
const test = require('node:test');
const assert = require('node:assert');
const D = require('../app/detector.js');

function img(W, H, bg, spots) {
  const d = new Uint8ClampedArray(W * H * 4);
  for (let i = 0; i < W * H; i++) { d[i * 4] = bg[0]; d[i * 4 + 1] = bg[1]; d[i * 4 + 2] = bg[2]; d[i * 4 + 3] = 255; }
  for (const s of spots) for (let y = -s.r; y <= s.r; y++) for (let x = -s.r; x <= s.r; x++) {
    if (x * x + y * y > s.r * s.r) continue;
    const px = s.x + x, py = s.y + y; if (px < 0 || py < 0 || px >= W || py >= H) continue;
    const i = (py * W + px) * 4; d[i] = s.c[0]; d[i + 1] = s.c[1]; d[i + 2] = s.c[2];
  }
  return { data: d, width: W, height: H };
}
const WHITE = [255, 255, 255];

test('détecte un petit reflet de lentille', () => {
  const r = D.analyze(img(320, 240, [90, 90, 90], [{ x: 100, y: 80, r: 2, c: WHITE }]));
  assert.strictEqual(r.blobs.length, 1);
  assert.ok(Math.abs(r.blobs[0].x - 100) < 1 && Math.abs(r.blobs[0].y - 80) < 1);
});
test('ignore une image vide', () => {
  assert.strictEqual(D.analyze(img(320, 240, [90, 90, 90], [])).blobs.length, 0);
});
test('ignore les grosses lampes, même à sensibilité maximale', () => {
  for (const r of [8, 15, 30, 60]) assert.strictEqual(D.analyze(img(320, 240, [60, 60, 60], [{ x: 160, y: 120, r, c: WHITE }]), { sensitivity: 10 }).blobs.length, 0, 'r=' + r);
});
test('ignore un trait fin (reflet allongé)', () => {
  const im = img(320, 240, [80, 80, 80], []);
  for (let x = 50; x < 70; x++) { const i = (100 * 320 + x) * 4; im.data[i] = im.data[i + 1] = im.data[i + 2] = 255; }
  assert.strictEqual(D.analyze(im).blobs.length, 0);
});
test('ignore une image entièrement blanche', () => {
  assert.strictEqual(D.analyze(img(320, 240, [255, 255, 255], [])).blobs.length, 0);
});
test('détecte une LED infrarouge violette dans le noir', () => {
  assert.strictEqual(D.analyze(img(320, 240, [20, 20, 25], [{ x: 200, y: 100, r: 2, c: [200, 120, 230] }]), { mode: 'ir' }).blobs.length, 1);
});
test('fonctionne sur les bords de l\'image', () => {
  const r = D.analyze(img(320, 240, [90, 90, 90], [{ x: 1, y: 1, r: 1, c: WHITE }, { x: 318, y: 238, r: 1, c: WHITE }]));
  assert.strictEqual(r.blobs.length, 2);
});
test('le suivi confirme seulement après plusieurs images', () => {
  const tr = new D.Tracker({ minHits: 4 });
  const b = D.analyze(img(320, 240, [90, 90, 90], [{ x: 100, y: 80, r: 2, c: WHITE }])).blobs;
  for (let k = 0; k < 3; k++) assert.strictEqual(tr.update(b).length, 0);
  assert.strictEqual(tr.update(b).length, 1);
});
test('un reflet passager (1 image) n\'est jamais confirmé', () => {
  const tr = new D.Tracker({ minHits: 4 });
  const b = D.analyze(img(320, 240, [90, 90, 90], [{ x: 100, y: 80, r: 2, c: WHITE }])).blobs;
  tr.update(b); for (let k = 0; k < 5; k++) assert.strictEqual(tr.update([]).length, 0);
});

test('toutes les langues ont toutes les traductions', () => {
  const T = require('../app/i18n.js').I18N._T;
  const ref = Object.keys(T.fr);
  for (const [code, dict] of Object.entries(T)) {
    for (const k of ref) {
      if (k === '_rtl') continue;
      assert.ok(dict[k] != null && dict[k] !== '', code + ' : clé manquante ' + k);
    }
    assert.strictEqual(dict.guide.length, T.fr.guide.length, code + ' : guide incomplet');
    for (const k of ['permAndroid', 'permIOS', 'permDesktop']) assert.strictEqual(dict[k].length, T.fr[k].length, code + ' : ' + k + ' incomplet');
    for (const k of ['photoPoints', 'magField', 'cameraError', 'magUnavailable']) {
      const want = (T.fr[k].match(/\{\w+\}/g) || []).sort().join();
      assert.strictEqual((dict[k].match(/\{\w+\}/g) || []).sort().join(), want, code + ' : variables de ' + k);
    }
  }
});
