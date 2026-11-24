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
test('ignore un point coupé par le bord de l\'image, mais détecte juste à côté', () => {
  assert.strictEqual(D.analyze(img(320, 240, [90, 90, 90], [{ x: 0, y: 1, r: 1, c: WHITE }, { x: 319, y: 238, r: 1, c: WHITE }])).blobs.length, 0);
  assert.strictEqual(D.analyze(img(320, 240, [90, 90, 90], [{ x: 5, y: 5, r: 1, c: WHITE }, { x: 314, y: 234, r: 1, c: WHITE }])).blobs.length, 2);
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

function rect(im, x0, y0, x1, y1, c) {
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const i = (y * im.width + x) * 4; im.data[i] = c[0]; im.data[i + 1] = c[1]; im.data[i + 2] = c[2]; }
}
test('ignore les coins et détails d\'un écran de télévision', () => {
  const im = img(320, 240, [70, 70, 70], []);
  rect(im, 100, 60, 220, 130, [230, 230, 235]);                  // écran lumineux
  rect(im, 150, 90, 170, 125, [90, 90, 140]);                    // personnage sombre dans l'image
  rect(im, 158, 100, 160, 102, WHITE);                           // reflet dans l'image
  for (const [x, y] of [[100, 60], [219, 60], [100, 129], [219, 129]]) rect(im, x - 1, y - 1, x + 2, y + 2, WHITE); // coins
  const r = D.analyze(im, { sensitivity: 8 });
  assert.ok(r.blobs.every(b => b.x < 95 || b.x > 225 || b.y < 55 || b.y > 135) || r.blobs.length <= 1, JSON.stringify(r.blobs));
  assert.ok(!r.blobs.some(b => Math.hypot(b.x - 100, b.y - 60) < 4 || Math.hypot(b.x - 219, b.y - 129) < 4), 'coin détecté');
});
test('ignore un reflet sur une tige métallique en diagonale', () => {
  const im = img(320, 240, [120, 120, 120], []);
  for (let k = 0; k < 10; k++) rect(im, 100 + k, 100 - k, 102 + k, 102 - k, WHITE);
  assert.strictEqual(D.analyze(im, { sensitivity: 8 }).blobs.length, 0);
});
test('détecte toujours une lentille sur un objet sombre (réveil, détecteur…)', () => {
  const im = img(320, 240, [150, 150, 150], []);
  rect(im, 140, 100, 180, 130, [30, 30, 30]);                    // boîtier noir
  rect(im, 159, 114, 161, 116, WHITE);                            // reflet de l'objectif
  assert.strictEqual(D.analyze(im).blobs.length, 1);
});

function gauss(bg, cx, cy, sigma, peak) {
  const im = img(320, 240, [bg, bg, bg], []);
  for (let y = 0; y < 240; y++) for (let x = 0; x < 320; x++) {
    const v = bg + (peak - bg) * Math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (2 * sigma * sigma));
    const i = (y * 320 + x) * 4; im.data[i] = im.data[i + 1] = im.data[i + 2] = v;
  }
  return im;
}
test('détecte un reflet d\'objectif réaliste, un peu flou', () => {
  for (const sigma of [0.7, 1, 1.4]) assert.strictEqual(D.analyze(gauss(70, 160, 120, sigma, 255)).blobs.length, 1, 'sigma ' + sigma);
});
test('ignore un reflet doux sur une surface bombée (bouton métallique)', () => {
  assert.strictEqual(D.analyze(gauss(70, 160, 120, 2.6, 255), { sensitivity: 8 }).blobs.length, 0);
});
test('ignore un panneau de voyants (3 points ou plus groupés) en mode reflet', () => {
  const pts = [[150, 100], [162, 103], [174, 100], [158, 118]].map(([x, y]) => ({ x, y, r: 1, c: WHITE }));
  assert.strictEqual(D.analyze(img(320, 240, [25, 25, 25], pts)).blobs.length, 0);
  assert.strictEqual(D.analyze(img(320, 240, [25, 25, 25], [{ x: 150, y: 100, r: 1, c: WHITE }])).blobs.length, 1);
});
test('garde un anneau de LED en mode infrarouge (caméra de vision nocturne)', () => {
  const pts = [0, 1, 2, 3, 4, 5].map(k => ({ x: Math.round(160 + 12 * Math.cos(k)), y: Math.round(120 + 12 * Math.sin(k)), r: 1, c: [210, 130, 235] }));
  assert.ok(D.analyze(img(320, 240, [15, 15, 20], pts), { mode: 'ir' }).blobs.length >= 4);
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
    assert.ok(dict.delete, code + ' : delete');
    for (const k of ['permAndroid', 'permIOS', 'permDesktop']) assert.strictEqual(dict[k].length, T.fr[k].length, code + ' : ' + k + ' incomplet');
    for (const k of ['photoPoints', 'magField', 'cameraError', 'magUnavailable']) {
      const want = (T.fr[k].match(/\{\w+\}/g) || []).sort().join();
      assert.strictEqual((dict[k].match(/\{\w+\}/g) || []).sort().join(), want, code + ' : variables de ' + k);
    }
  }
});

test('le rapport de scan est traduit dans toutes les langues', () => {
  const R = require('../app/i18n-report.js').REPORT_T;
  const ref = Object.keys(R.fr);
  assert.deepStrictEqual(Object.keys(R).sort(), ['ar', 'de', 'en', 'es', 'fr', 'it', 'pt', 'tr']);
  for (const [code, dict] of Object.entries(R)) {
    for (const k of ref) assert.ok(dict[k] != null && dict[k] !== '', code + ' : clé manquante ' + k);
    assert.strictEqual(dict.repSuggest.length, R.fr.repSuggest.length, code + ' : pièces suggérées');
    for (const k of ['roomStats', 'repSummarySuspect', 'repSummaryClear', 'roomScanning', 'roomResultTitle']) {
      const want = (R.fr[k].match(/\{\w+\}/g) || []).sort().join();
      assert.strictEqual((dict[k].match(/\{\w+\}/g) || []).sort().join(), want, code + ' : variables de ' + k);
    }
  }
});
