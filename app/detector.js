// Détecteur d'objectifs de caméra (reflets) et de LED infrarouges.
// Fonction pure : fonctionne sur un objet {data, width, height} (ImageData).
(function (root) {
  'use strict';

  function analyze(img, opts) {
    const o = Object.assign({ mode: 'reflet', sensitivity: 5 }, opts || {});
    const { data, width: W, height: H } = img;
    const N = W * H;
    const lum = new Float32Array(N);
    for (let i = 0, p = 0; i < N; i++, p += 4) {
      lum[i] = 0.299 * data[p] + 0.587 * data[p + 1] + 0.114 * data[p + 2];
    }

    // Image intégrale pour calculer la luminosité moyenne autour de chaque pixel.
    const integ = new Float64Array((W + 1) * (H + 1));
    let sceneSum = 0;
    for (let y = 0; y < H; y++) {
      let row = 0;
      for (let x = 0; x < W; x++) {
        row += lum[y * W + x];
        integ[(y + 1) * (W + 1) + x + 1] = integ[y * (W + 1) + x + 1] + row;
      }
      sceneSum += row;
    }
    const sceneMean = sceneSum / N;
    const R = Math.max(4, Math.round(W / 40));
    function localMean(x, y) {
      const x0 = Math.max(0, x - R), y0 = Math.max(0, y - R);
      const x1 = Math.min(W, x + R + 1), y1 = Math.min(H, y + R + 1);
      const s = integ[y1 * (W + 1) + x1] - integ[y0 * (W + 1) + x1]
              - integ[y1 * (W + 1) + x0] + integ[y0 * (W + 1) + x0];
      return s / ((x1 - x0) * (y1 - y0));
    }

    // Sensibilité 1 (stricte) .. 10 (très sensible)
    const s = Math.min(10, Math.max(1, o.sensitivity));
    const minBright = o.mode === 'ir' ? 190 - s * 8 : 250 - s * 4;   // 182..110 / 246..210
    const minContrast = o.mode === 'ir' ? 70 - s * 4 : 100 - s * 6;  // 66..30 / 94..40

    const mask = new Uint8Array(N);
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const i = y * W + x;
        const L = lum[i];
        if (L < minBright) continue;
        if (L - localMean(x, y) < minContrast) continue;
        if (o.mode === 'ir') {
          const p = i * 4, r = data[p], g = data[p + 1], b = data[p + 2];
          // Les LED infrarouges apparaissent violettes/roses ou blanches dans une pièce sombre.
          const purple = b > g + 12 && r > g + 5;
          const whiteInDark = sceneMean < 70 && L > 200;
          if (!purple && !whiteInDark) continue;
        }
        mask[i] = 1;
      }
    }

    // Composantes connexes (taches lumineuses).
    const maxArea = Math.max(12, Math.round((W * H) / 600));
    const maxSide = Math.max(5, Math.round(W / 18));
    const blobs = [];
    const stack = new Int32Array(N);
    for (let start = 0; start < N; start++) {
      if (mask[start] !== 1) continue;
      let sp = 0, area = 0, sx = 0, sy = 0, sumL = 0;
      let minX = W, minY = H, maxX = 0, maxY = 0;
      stack[sp++] = start; mask[start] = 2;
      while (sp) {
        const i = stack[--sp];
        const x = i % W, y = (i / W) | 0;
        area++; sx += x; sy += y; sumL += lum[i];
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        const nb = [i - 1, i + 1, i - W, i + W];
        for (let k = 0; k < 4; k++) {
          const j = nb[k];
          if (j < 0 || j >= N) continue;
          if ((k === 0 && x === 0) || (k === 1 && x === W - 1)) continue;
          if (mask[j] === 1) { mask[j] = 2; stack[sp++] = j; }
        }
      }
      const bw = maxX - minX + 1, bh = maxY - minY + 1;
      if (area < 1 || area > maxArea) continue;          // trop gros = lampe, fenêtre…
      if (bw > maxSide || bh > maxSide) continue;
      const aspect = Math.max(bw, bh) / Math.min(bw, bh);
      if (aspect > 2.2) continue;                        // une lentille est ronde
      const fill = area / (bw * bh);
      if (area > 3 && fill < 0.35) continue;
      const cx = sx / area, cy = sy / area;
      const contrast = sumL / area - localMean(Math.round(cx), Math.round(cy));
      const roundness = 1 / aspect;
      const score = Math.min(1, (contrast / 160) * 0.6 + roundness * 0.25 + fill * 0.15);
      blobs.push({ x: cx, y: cy, r: Math.max(bw, bh) / 2 + 1, area, contrast, score });
    }

    blobs.sort((a, b) => b.score - a.score);
    // Beaucoup de taches = surface brillante/pailletée : on ne garde que les meilleures.
    const noisy = blobs.length > 25;
    return { blobs: blobs.slice(0, noisy ? 3 : 10), noisy, sceneMean };
  }

  // Suivi dans le temps : une vraie lentille reste visible plusieurs images de suite.
  function Tracker(opts) {
    this.minHits = (opts && opts.minHits) || 4;
    this.maxDist = (opts && opts.maxDist) || 14;
    this.tracks = [];
    this.nextId = 1;
  }
  Tracker.prototype.update = function (blobs) {
    const used = new Set();
    for (const t of this.tracks) {
      let best = -1, bestD = this.maxDist;
      blobs.forEach((b, i) => {
        if (used.has(i)) return;
        const d = Math.hypot(b.x - t.x, b.y - t.y);
        if (d < bestD) { bestD = d; best = i; }
      });
      if (best >= 0) {
        const b = blobs[best]; used.add(best);
        t.x = t.x * 0.5 + b.x * 0.5; t.y = t.y * 0.5 + b.y * 0.5;
        t.r = b.r; t.score = b.score; t.hits++; t.miss = 0;
      } else {
        t.miss++;
      }
    }
    this.tracks = this.tracks.filter(t => t.miss < 3);
    blobs.forEach((b, i) => {
      if (!used.has(i)) this.tracks.push({ id: this.nextId++, x: b.x, y: b.y, r: b.r, score: b.score, hits: 1, miss: 0, shot: false });
    });
    return this.tracks.filter(t => t.hits >= this.minHits && t.miss === 0);
  };

  const api = { analyze, Tracker };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Detector = api;
})(this);
