(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const video = $('video'), overlay = $('overlay'), octx = overlay.getContext('2d');
  const statusEl = $('status');
  const work = document.createElement('canvas');
  const wctx = work.getContext('2d', { willReadFrequently: true });
  const PROC_W = 320;

  let stream = null, track = null, running = false, torchOn = false;
  let tracker = new Detector.Tracker({ minHits: 4 });
  let lastShot = 0, lastAlert = 0;
  let audioCtx = null;

  // ---------- Onglets ----------
  document.querySelectorAll('.tab').forEach(b => b.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t === b));
    document.querySelectorAll('.panel').forEach(p => p.classList.toggle('active', p.id === b.dataset.tab));
    if (b.dataset.tab === 'photos') renderGallery();
  }));

  $('sens').addEventListener('input', e => { $('sensVal').textContent = e.target.value; });
  $('mode').addEventListener('change', () => { tracker = new Detector.Tracker({ minHits: 4 }); });

  function setStatus(text, cls) { statusEl.textContent = text; statusEl.className = 'status ' + cls; }

  // ---------- Caméra ----------
  async function start() {
    if (running) return stop();
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setStatus('Caméra non disponible. Ouvrez la page en HTTPS dans Chrome ou Safari.', 'alert');
      return;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } }
      });
    } catch (err) {
      setStatus('Accès caméra refusé : ' + err.message, 'alert');
      return;
    }
    video.srcObject = stream;
    await video.play();
    track = stream.getVideoTracks()[0];
    const caps = track.getCapabilities ? track.getCapabilities() : {};
    $('torchBtn').disabled = !caps.torch;
    $('torchBtn').title = caps.torch ? '' : 'Lampe non pilotable sur cet appareil';
    $('snapBtn').disabled = false;
    $('startBtn').textContent = '⏹ Arrêter';
    running = true;
    initAudio();
    startMagnetometer();
    setStatus('Scan en cours… balayez lentement', 'ok');
    requestAnimationFrame(loop);
  }

  function stop() {
    running = false;
    if (stream) stream.getTracks().forEach(t => t.stop());
    stream = null; track = null; torchOn = false;
    $('torchBtn').classList.remove('on'); $('torchBtn').disabled = true; $('snapBtn').disabled = true;
    $('startBtn').textContent = '▶ Démarrer le scan';
    octx.clearRect(0, 0, overlay.width, overlay.height);
    setStatus('Scan arrêté', 'idle');
  }

  async function toggleTorch() {
    if (!track) return;
    try {
      torchOn = !torchOn;
      await track.applyConstraints({ advanced: [{ torch: torchOn }] });
      $('torchBtn').classList.toggle('on', torchOn);
    } catch (e) { torchOn = false; setStatus('Impossible d\'allumer la lampe', 'alert'); }
  }

  // ---------- Boucle d'analyse ----------
  let lastProc = 0;
  function loop(ts) {
    if (!running) return;
    requestAnimationFrame(loop);
    if (ts - lastProc < 66 || !video.videoWidth) return; // ~15 analyses / seconde
    lastProc = ts;

    const vw = video.videoWidth, vh = video.videoHeight;
    const pw = PROC_W, ph = Math.round(PROC_W * vh / vw);
    if (work.width !== pw) { work.width = pw; work.height = ph; }
    wctx.drawImage(video, 0, 0, pw, ph);
    const img = wctx.getImageData(0, 0, pw, ph);
    const res = Detector.analyze(img, { mode: $('mode').value, sensitivity: +$('sens').value });
    const confirmed = tracker.update(res.blobs);

    drawOverlay(res.blobs, confirmed, pw, ph);

    if (confirmed.length) {
      const label = $('mode').value === 'ir' ? 'LED infrarouge suspecte !' : 'Objectif de caméra suspect !';
      setStatus('⚠️ ' + label + ' (' + confirmed.length + ')', 'alert');
      const now = Date.now();
      if ($('sound').checked && now - lastAlert > 1500) { beep(); if (navigator.vibrate) navigator.vibrate([150, 80, 150]); lastAlert = now; }
      const fresh = confirmed.filter(t => !t.shot);
      if ($('autoShot').checked && fresh.length && now - lastShot > 2500) {
        fresh.forEach(t => (t.shot = true));
        takePhoto(confirmed, pw, ph, true);
        lastShot = now;
      }
    } else if (res.noisy) {
      setStatus('Trop de reflets ici (surface brillante) — changez d\'angle', 'idle');
    } else {
      setStatus('Scan en cours… rien de suspect', 'ok');
    }
  }

  // Conversion coordonnées d'analyse -> écran (vidéo en object-fit: cover)
  function mapper(pw, ph) {
    const W = overlay.clientWidth, H = overlay.clientHeight;
    const scale = Math.max(W / pw, H / ph);
    const ox = (W - pw * scale) / 2, oy = (H - ph * scale) / 2;
    return { W, H, f: (x, y) => [ox + x * scale, oy + y * scale], scale };
  }

  function drawOverlay(blobs, confirmed, pw, ph) {
    const dpr = window.devicePixelRatio || 1;
    const m = mapper(pw, ph);
    if (overlay.width !== Math.round(m.W * dpr)) { overlay.width = Math.round(m.W * dpr); overlay.height = Math.round(m.H * dpr); }
    octx.setTransform(dpr, 0, 0, dpr, 0, 0);
    octx.clearRect(0, 0, m.W, m.H);
    octx.lineWidth = 2;
    octx.strokeStyle = 'rgba(250,204,21,.8)';
    for (const b of blobs) {
      const [x, y] = m.f(b.x, b.y);
      octx.beginPath(); octx.arc(x, y, Math.max(8, b.r * m.scale + 6), 0, Math.PI * 2); octx.stroke();
    }
    octx.lineWidth = 4; octx.strokeStyle = '#ef4444'; octx.fillStyle = '#ef4444';
    octx.font = 'bold 14px system-ui';
    for (const t of confirmed) {
      const [x, y] = m.f(t.x, t.y);
      const r = Math.max(16, t.r * m.scale + 14);
      octx.beginPath(); octx.arc(x, y, r, 0, Math.PI * 2); octx.stroke();
      octx.fillText(Math.round(t.score * 100) + '%', x + r + 4, y + 5);
    }
  }

  // ---------- Photo ----------
  function takePhoto(marks, pw, ph, auto) {
    if (!video.videoWidth) return;
    const c = document.createElement('canvas');
    c.width = video.videoWidth; c.height = video.videoHeight;
    const ctx = c.getContext('2d');
    ctx.drawImage(video, 0, 0);
    const k = c.width / pw;
    ctx.lineWidth = Math.max(4, c.width / 200); ctx.strokeStyle = '#ef4444';
    for (const t of marks || []) {
      ctx.beginPath(); ctx.arc(t.x * k, t.y * k, Math.max(30, t.r * k * 3), 0, Math.PI * 2); ctx.stroke();
    }
    const date = new Date();
    const fs = Math.max(18, c.width / 45);
    ctx.font = 'bold ' + fs + 'px system-ui';
    ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(0, c.height - fs * 1.8, c.width, fs * 1.8);
    ctx.fillStyle = '#fff';
    const what = marks && marks.length ? (marks.length + ' point(s) suspect(s) — ' + ($('mode').value === 'ir' ? 'infrarouge' : 'reflet d\'objectif')) : 'Photo manuelle';
    ctx.fillText(date.toLocaleString('fr-FR') + '  •  ' + what, fs * 0.5, c.height - fs * 0.6);

    $('flash').style.opacity = .8; setTimeout(() => ($('flash').style.opacity = 0), 120);
    c.toBlob(blob => {
      savePhoto({ blob, date: date.toISOString(), info: what, auto: !!auto, mag: lastMag })
        .then(updateCount).catch(() => setStatus('Impossible d\'enregistrer la photo', 'alert'));
    }, 'image/jpeg', 0.9);
  }

  // ---------- Stockage local (IndexedDB) ----------
  let dbp = null;
  function db() {
    if (!dbp) dbp = new Promise((res, rej) => {
      const r = indexedDB.open('detecteur', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('photos', { keyPath: 'id', autoIncrement: true });
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    return dbp;
  }
  function store(mode) { return db().then(d => d.transaction('photos', mode).objectStore('photos')); }
  function req(r) { return new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); }); }
  const savePhoto = p => store('readwrite').then(s => req(s.add(p)));
  const allPhotos = () => store('readonly').then(s => req(s.getAll()));
  const delPhoto = id => store('readwrite').then(s => req(s.delete(id)));
  const clearPhotos = () => store('readwrite').then(s => req(s.clear()));

  function updateCount() { allPhotos().then(l => ($('photoCount').textContent = l.length)).catch(() => {}); }

  let urls = [];
  async function renderGallery() {
    urls.forEach(u => URL.revokeObjectURL(u)); urls = [];
    const g = $('gallery'); g.innerHTML = '';
    const list = (await allPhotos()).reverse();
    if (!list.length) { g.innerHTML = '<p class="small">Aucune photo pour le moment.</p>'; return; }
    for (const p of list) {
      const u = URL.createObjectURL(p.blob); urls.push(u);
      const el = document.createElement('div'); el.className = 'shot';
      el.innerHTML = '<a href="' + u + '" target="_blank"><img src="' + u + '" alt="détection"></a>' +
        '<div class="meta"></div><div class="acts"><button data-a="save">💾 Enregistrer</button><button data-a="del">🗑</button></div>';
      el.querySelector('.meta').textContent = new Date(p.date).toLocaleString('fr-FR') + ' — ' + p.info + (p.auto ? ' (auto)' : '');
      el.querySelector('[data-a=save]').onclick = () => {
        const a = document.createElement('a'); a.href = u;
        a.download = 'detection-' + p.date.replace(/[:.]/g, '-') + '.jpg'; a.click();
      };
      el.querySelector('[data-a=del]').onclick = async () => { await delPhoto(p.id); renderGallery(); updateCount(); };
      g.appendChild(el);
    }
  }
  $('clearBtn').onclick = async () => { if (confirm('Effacer toutes les photos ?')) { await clearPhotos(); renderGallery(); updateCount(); } };

  // ---------- Son ----------
  function initAudio() { try { audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)(); audioCtx.resume(); } catch (e) {} }
  function beep() {
    if (!audioCtx) return;
    const o = audioCtx.createOscillator(), g = audioCtx.createGain();
    o.frequency.value = 1200; o.type = 'square'; g.gain.value = 0.08;
    o.connect(g).connect(audioCtx.destination); o.start(); o.stop(audioCtx.currentTime + 0.15);
  }

  // ---------- Magnétomètre (micros / électronique) ----------
  let lastMag = null, magBase = null, magStarted = false;
  function startMagnetometer() {
    if (magStarted) return;
    if (!('Magnetometer' in window)) {
      $('magInfo').textContent = 'Magnétomètre non accessible depuis le navigateur sur ce téléphone (sur Android/Chrome, il faut activer chrome://flags → « Generic Sensor Extra Classes »).';
      return;
    }
    try {
      const mag = new Magnetometer({ frequency: 10 });
      mag.addEventListener('reading', () => {
        const v = Math.hypot(mag.x, mag.y, mag.z);
        magBase = magBase == null ? v : magBase * 0.995 + v * 0.005; // champ terrestre moyen
        const delta = Math.abs(v - magBase);
        lastMag = Math.round(v);
        $('magBar').style.width = Math.min(100, delta * 2) + '%';
        $('magInfo').textContent = 'Champ : ' + Math.round(v) + ' µT  •  écart : ' + Math.round(delta) + ' µT' + (delta > 25 ? '  ⚠️ électronique/métal proche !' : '');
        if (delta > 25 && running && $('sound').checked && Date.now() - lastAlert > 1500) { beep(); lastAlert = Date.now(); }
      });
      mag.addEventListener('error', e => { $('magInfo').textContent = 'Magnétomètre indisponible : ' + e.error.name; });
      mag.start(); magStarted = true;
    } catch (e) { $('magInfo').textContent = 'Magnétomètre indisponible : ' + e.message; }
  }

  $('startBtn').onclick = start;
  $('torchBtn').onclick = toggleTorch;
  $('snapBtn').onclick = () => takePhoto(tracker.tracks.filter(t => t.hits >= tracker.minHits), work.width, work.height, false);

  updateCount();
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
})();
