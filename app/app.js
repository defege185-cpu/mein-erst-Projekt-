(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  window.App = window.App || { context: null };
  const t = (k, v) => I18N.t(k, v);
  const video = $('video'), overlay = $('overlay'), octx = overlay.getContext('2d');
  const statusEl = $('status');
  const work = document.createElement('canvas');
  const wctx = work.getContext('2d', { willReadFrequently: true });
  const PROC_W = 320;
  const MIN_HITS = 4;

  let stream = null, track = null, running = false, starting = false, torchOn = false;
  let facing = 'environment';
  let tracker = new Detector.Tracker({ minHits: MIN_HITS });
  let lastShot = 0, lastAlert = 0, audioCtx = null;

  // ---------- Langue ----------
  const langSel = $('lang');
  I18N.languages.forEach(l => { const o = document.createElement('option'); o.value = l.code; o.textContent = l.name; langSel.appendChild(o); });
  langSel.value = I18N.lang;
  langSel.addEventListener('change', () => I18N.set(langSel.value));
  document.addEventListener('langchange', refreshTexts);

  function refreshTexts() {
    I18N.apply();
    $('startBtn').textContent = t(running ? 'stop' : 'start');
    renderStatus();
    renderMag();
    $('torchBtn').title = track && $('torchBtn').disabled ? t('torchUnsupported') : '';
    if ($('photos').classList.contains('active')) renderGallery();
  }

  // ---------- Statut (mémorisé pour pouvoir changer de langue) ----------
  let status = { key: 'statusIdle', cls: 'idle', vars: null }, holdUntil = 0;
  function setStatus(key, cls, vars, holdMs) {
    if (!holdMs && Date.now() < holdUntil) return; // un message important reste affiché un moment
    status = { key, cls, vars: vars || null };
    holdUntil = holdMs ? Date.now() + holdMs : 0;
    renderStatus();
  }
  function renderStatus() {
    let txt = t(status.key, status.vars);
    statusEl.textContent = (status.cls === 'alert' && status.vars && status.vars.count ? '⚠️ ' + txt + ' (' + status.vars.count + ')' : txt);
    statusEl.className = 'status ' + status.cls;
  }

  // ---------- Onglets ----------
  function showTab(name) {
    document.querySelectorAll('.tab').forEach(x => x.classList.toggle('active', x.dataset.tab === name));
    document.querySelectorAll('.panel').forEach(p => p.classList.toggle('active', p.id === name));
    if (name === 'photos') renderGallery();
    emit('tab', name);
  }
  document.querySelectorAll('.tab').forEach(b => b.addEventListener('click', () => showTab(b.dataset.tab)));

  // ---------- Petite API pour les modules (rapport de scan) ----------
  const listeners = {};
  function on(evt, fn) { (listeners[evt] = listeners[evt] || []).push(fn); }
  function emit(evt, data) { (listeners[evt] || []).forEach(fn => { try { fn(data); } catch (e) { console.error(e); } }); }

  $('sens').addEventListener('input', e => { $('sensVal').textContent = e.target.value; });
  $('mode').addEventListener('change', () => { tracker = new Detector.Tracker({ minHits: MIN_HITS }); });

  // ---------- Caméra ----------
  async function openCamera() {
    const s = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: { ideal: facing }, width: { ideal: 1920 }, height: { ideal: 1080 } }
    });
    if (stream) stream.getTracks().forEach(x => x.stop());
    stream = s;
    track = stream.getVideoTracks()[0];
    track.addEventListener('ended', () => { if (running) { stop(); setStatus('cameraLost', 'alert', null, 4000); } });
    video.srcObject = stream;
    try { await video.play(); } catch (e) { /* autoplay : la vidéo démarrera quand même (muted + playsinline) */ }
    torchOn = false;
    $('torchBtn').classList.remove('on');
    const caps = track.getCapabilities ? track.getCapabilities() : {};
    $('torchBtn').disabled = !caps.torch;
    $('torchBtn').title = caps.torch ? '' : t('torchUnsupported');
    tracker = new Detector.Tracker({ minHits: MIN_HITS });
  }

  // ---------- Aide « autoriser la caméra » ----------
  // Un site web ne peut pas ouvrir les réglages du téléphone : on affiche les étapes exactes
  // pour l'appareil, et le scan démarre tout seul dès que la caméra est autorisée.
  const ua = navigator.userAgent || '';
  const platform = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) ? 'ios'
    : /Android/.test(ua) ? 'android' : 'desktop';
  const isMobile = platform !== 'desktop';
  function renderPermHelp() {
    const ol = $('permSteps'); ol.innerHTML = '';
    const steps = location.protocol === 'file:' && isMobile ? [t('permFile')]
      : t(platform === 'ios' ? 'permIOS' : platform === 'android' ? 'permAndroid' : 'permDesktop');
    steps.forEach(x => { const li = document.createElement('li'); li.textContent = x; ol.appendChild(li); });
  }
  function showPermHelp() { renderPermHelp(); $('permHelp').hidden = false; $('permRetry').focus(); }
  function hidePermHelp() { $('permHelp').hidden = true; }
  $('permRetry').onclick = () => { hidePermHelp(); start(); };
  $('permClose').onclick = hidePermHelp;
  document.addEventListener('langchange', () => { if (!$('permHelp').hidden) renderPermHelp(); });
  // Dès que la caméra est autorisée dans les réglages, on démarre le scan automatiquement.
  try {
    navigator.permissions.query({ name: 'camera' }).then(ps => {
      ps.onchange = () => { if (ps.state === 'granted' && !$('permHelp').hidden && !running) { hidePermHelp(); start(); } };
    }).catch(() => {});
  } catch (e) {}

  async function start() {
    if (starting) return;
    if (running) { stop(); return; }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setStatus('noCamera', 'alert', null, 6000);
      if (location.protocol === 'file:' || !window.isSecureContext) showPermHelp();
      return;
    }
    starting = true;
    initAudio();
    try {
      await openCamera();
    } catch (err) {
      starting = false;
      const denied = err && (err.name === 'NotAllowedError' || err.name === 'SecurityError');
      setStatus(denied ? 'cameraDenied' : 'cameraError', 'alert', { e: (err && (err.message || err.name)) || '?' }, 6000);
      showPermHelp();
      return;
    }
    hidePermHelp();
    starting = false;
    running = true;
    $('snapBtn').disabled = false;
    $('switchBtn').disabled = false;
    $('startBtn').textContent = t('stop');
    startMagnetometer();
    holdUntil = 0;
    setStatus('scanning', 'ok');
    requestAnimationFrame(loop);
  }

  function stop() {
    running = false;
    if (stream) stream.getTracks().forEach(x => x.stop());
    stream = null; track = null; torchOn = false;
    video.srcObject = null;
    $('torchBtn').classList.remove('on');
    ['torchBtn', 'snapBtn', 'switchBtn'].forEach(id => ($(id).disabled = true));
    $('startBtn').textContent = t('start');
    octx.clearRect(0, 0, overlay.width, overlay.height);
    setStatus('stopped', 'idle');
  }

  async function switchCamera() {
    if (!running) return;
    facing = facing === 'environment' ? 'user' : 'environment';
    try { await openCamera(); }
    catch (err) { facing = facing === 'environment' ? 'user' : 'environment'; setStatus('cameraError', 'alert', { e: err.message || err.name }, 4000); }
  }

  async function toggleTorch() {
    if (!track) return;
    const want = !torchOn;
    try {
      await track.applyConstraints({ advanced: [{ torch: want }] });
      torchOn = want;
      $('torchBtn').classList.toggle('on', torchOn);
    } catch (e) { setStatus('torchFail', 'alert', null, 3000); }
  }

  // Couper la caméra quand l'application passe en arrière-plan (vie privée + batterie).
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && running) stop();
    // Retour depuis les réglages du téléphone : on réessaie tout seul.
    else if (!document.hidden && !$('permHelp').hidden && !running) {
      try {
        navigator.permissions.query({ name: 'camera' }).then(ps => { if (ps.state === 'granted') { hidePermHelp(); start(); } }).catch(() => {});
      } catch (e) {}
    }
  });

  // ---------- Boucle d'analyse ----------
  let lastProc = 0;
  function loop(ts) {
    if (!running) return;
    requestAnimationFrame(loop);
    if (ts - lastProc < 66 || !video.videoWidth || video.readyState < 2) return; // ~15 analyses / seconde
    lastProc = ts;

    const vw = video.videoWidth, vh = video.videoHeight;
    const pw = PROC_W, ph = Math.round(PROC_W * vh / vw);
    if (work.width !== pw || work.height !== ph) { work.width = pw; work.height = ph; tracker = new Detector.Tracker({ minHits: MIN_HITS }); }
    wctx.drawImage(video, 0, 0, pw, ph);
    let img;
    try { img = wctx.getImageData(0, 0, pw, ph); } catch (e) { return; }
    const mode = $('mode').value;
    const res = Detector.analyze(img, { mode, sensitivity: +$('sens').value });
    const confirmed = tracker.update(res.blobs);
    emit('frame', { confirmed, crowded: confirmed.length >= 4 });

    drawOverlay(res.blobs, confirmed, pw, ph);

    if (confirmed.length >= 4) {
      // Beaucoup de points à la fois : écran, lustre ou surface brillante, pas des caméras.
      setStatus('noisy', 'idle');
    } else if (confirmed.length) {
      setStatus(mode === 'ir' ? 'alertIR' : 'alertLens', 'alert', { count: confirmed.length });
      const now = Date.now();
      if ($('sound').checked && now - lastAlert > 1500) { beep(); vibrate(); lastAlert = now; }
      const fresh = confirmed.filter(x => !x.shot);
      if ($('autoShot').checked && fresh.length && now - lastShot > 4000) {
        fresh.forEach(x => (x.shot = true));
        takePhoto(confirmed, pw, true);
        lastShot = now;
      }
    } else if (res.noisy) {
      setStatus('noisy', 'idle');
    } else {
      setStatus('nothing', 'ok');
    }
  }

  // Conversion coordonnées d'analyse -> écran (vidéo en object-fit: cover)
  function mapper(pw, ph) {
    const W = overlay.clientWidth, H = overlay.clientHeight;
    const scale = Math.max(W / pw, H / ph);
    const ox = (W - pw * scale) / 2, oy = (H - ph * scale) / 2;
    return { W, H, scale, f: (x, y) => [ox + x * scale, oy + y * scale] };
  }

  function drawOverlay(blobs, confirmed, pw, ph) {
    const dpr = window.devicePixelRatio || 1;
    const m = mapper(pw, ph);
    if (!m.W || !m.H) return;
    const cw = Math.round(m.W * dpr), ch = Math.round(m.H * dpr);
    if (overlay.width !== cw || overlay.height !== ch) { overlay.width = cw; overlay.height = ch; }
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
    octx.direction = 'ltr'; octx.textAlign = 'left';
    for (const c of confirmed) {
      const [x, y] = m.f(c.x, c.y);
      const r = Math.max(16, c.r * m.scale + 14);
      octx.beginPath(); octx.arc(x, y, r, 0, Math.PI * 2); octx.stroke();
      octx.fillText(Math.round(c.score * 100) + '%', x + r + 4, y + 5);
    }
  }

  // ---------- Photo ----------
  function takePhoto(marks, pw, auto) {
    if (!video.videoWidth) return;
    const c = document.createElement('canvas');
    c.width = video.videoWidth; c.height = video.videoHeight;
    const ctx = c.getContext('2d');
    ctx.drawImage(video, 0, 0);
    marks = marks || [];
    if (marks.length && pw) {
      const k = c.width / pw;
      ctx.lineWidth = Math.max(4, c.width / 200); ctx.strokeStyle = '#ef4444';
      for (const m of marks) { ctx.beginPath(); ctx.arc(m.x * k, m.y * k, Math.max(30, m.r * k * 3), 0, Math.PI * 2); ctx.stroke(); }
    }
    const date = new Date();
    const modeKey = $('mode').value === 'ir' ? 'modeNameIR' : 'modeNameReflect';
    const info = marks.length ? { key: 'photoPoints', n: marks.length, m: modeKey } : { key: 'photoManual' };
    const fs = Math.max(18, c.width / 45);
    ctx.font = 'bold ' + fs + 'px system-ui, sans-serif';
    ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(0, c.height - fs * 1.8, c.width, fs * 1.8);
    ctx.fillStyle = '#fff';
    const rtl = document.documentElement.dir === 'rtl';
    ctx.direction = rtl ? 'rtl' : 'ltr'; ctx.textAlign = 'start';
    ctx.fillText(date.toLocaleString(I18N.lang) + '  •  ' + infoText(info), rtl ? c.width - fs * 0.5 : fs * 0.5, c.height - fs * 0.6, c.width - fs);

    $('flash').style.opacity = 0.8; setTimeout(() => ($('flash').style.opacity = 0), 120);
    c.toBlob(blob => {
      if (!blob) { setStatus('saveFail', 'alert', null, 3000); return; }
      const ctxInfo = window.App.context ? { reportId: App.context.reportId, roomId: App.context.roomId } : {};
      savePhoto(Object.assign({ blob, date: date.toISOString(), info, auto: !!auto }, ctxInfo))
        .then(id => { updateCount(); emit('photo', { id, auto: !!auto }); })
        .catch(() => setStatus('saveFail', 'alert', null, 3000));
    }, 'image/jpeg', 0.9);
  }
  function infoText(info) {
    if (!info) return '';
    if (typeof info === 'string') return info; // anciennes photos
    return info.key === 'photoPoints' ? t('photoPoints', { n: info.n, m: t(info.m) }) : t(info.key);
  }

  // ---------- Stockage local (IndexedDB) ----------
  let dbp = null;
  function db() {
    if (!dbp) {
      dbp = new Promise((res, rej) => {
        if (!window.indexedDB) return rej(new Error('no indexedDB'));
        const r = indexedDB.open('detecteur', 2);
        r.onupgradeneeded = () => {
          const d = r.result;
          if (!d.objectStoreNames.contains('photos')) d.createObjectStore('photos', { keyPath: 'id', autoIncrement: true });
          if (!d.objectStoreNames.contains('reports')) d.createObjectStore('reports', { keyPath: 'id', autoIncrement: true });
        };
        r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
      });
      dbp.catch(() => { dbp = null; });
    }
    return dbp;
  }
  function run(mode, fn, storeName) {
    storeName = storeName || 'photos';
    return db().then(d => new Promise((res, rej) => {
      const tx = d.transaction(storeName, mode);
      const r = fn(tx.objectStore(storeName));
      tx.oncomplete = () => res(r.result); tx.onerror = () => rej(tx.error); tx.onabort = () => rej(tx.error);
    }));
  }
  const savePhoto = p => run('readwrite', s => s.add(p));
  const allPhotos = () => run('readonly', s => s.getAll());
  const delPhoto = id => run('readwrite', s => s.delete(id));
  const clearPhotos = () => run('readwrite', s => s.clear());

  function updateCount() { allPhotos().then(l => ($('photoCount').textContent = l.length)).catch(() => {}); }

  let urls = [];
  async function renderGallery() {
    const g = $('gallery');
    let list;
    try { list = (await allPhotos()).reverse(); }
    catch (e) { g.textContent = t('storageFail'); return; }
    urls.forEach(u => URL.revokeObjectURL(u)); urls = [];
    g.innerHTML = '';
    if (!list.length) { const p = document.createElement('p'); p.className = 'small'; p.textContent = t('noPhotos'); g.appendChild(p); return; }
    for (const p of list) {
      const u = URL.createObjectURL(p.blob); urls.push(u);
      const name = 'detection-' + p.date.replace(/[:.]/g, '-') + '.jpg';
      const el = document.createElement('div'); el.className = 'shot';
      const a = document.createElement('button'); a.className = 'thumb';
      const im = document.createElement('img'); im.src = u; im.alt = ''; a.appendChild(im);
      a.onclick = () => openViewer(u);
      const meta = document.createElement('div'); meta.className = 'meta';
      meta.textContent = new Date(p.date).toLocaleString(I18N.lang) + ' — ' + infoText(p.info) + (p.auto ? ' ' + t('auto') : '');
      const acts = document.createElement('div'); acts.className = 'acts';
      const bSave = iconBtn('💾', t('save'));
      bSave.onclick = () => { const d = document.createElement('a'); d.href = u; d.download = name; document.body.appendChild(d); d.click(); d.remove(); };
      acts.appendChild(bSave);
      const file = (typeof File === 'function') ? new File([p.blob], name, { type: 'image/jpeg' }) : null;
      if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
        const bShare = iconBtn('📤', t('share'));
        bShare.onclick = () => navigator.share({ files: [file] }).catch(() => {});
        acts.appendChild(bShare);
      }
      const bDel = iconBtn('🗑', t('delete'));
      bDel.onclick = async () => { try { await delPhoto(p.id); } catch (e) {} renderGallery(); updateCount(); };
      acts.appendChild(bDel);
      el.append(a, meta, acts);
      g.appendChild(el);
    }
  }
  function iconBtn(icon, label) {
    label = String(label).replace(/^[^\p{L}]+/u, ''); // retire l'emoji du libellé
    const b = document.createElement('button'); b.textContent = icon; b.title = label; b.setAttribute('aria-label', label);
    return b;
  }
  function openViewer(u) { $('viewerImg').src = u; $('photoViewer').hidden = false; }
  function closeViewer() { $('photoViewer').hidden = true; $('viewerImg').removeAttribute('src'); }
  $('photoViewer').onclick = closeViewer;
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeViewer(); hidePermHelp(); } });

  $('clearBtn').onclick = async () => {
    if (!confirm(t('confirmClear'))) return;
    try { await clearPhotos(); } catch (e) {}
    renderGallery(); updateCount();
  };

  // ---------- Son et vibration ----------
  function initAudio() {
    try { audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)(); if (audioCtx.state === 'suspended') audioCtx.resume(); } catch (e) { audioCtx = null; }
  }
  function beep() {
    if (!audioCtx) return;
    try {
      const o = audioCtx.createOscillator(), g = audioCtx.createGain();
      o.frequency.value = 1200; o.type = 'square'; g.gain.value = 0.08;
      o.connect(g); g.connect(audioCtx.destination); o.start(); o.stop(audioCtx.currentTime + 0.15);
    } catch (e) {}
  }
  function vibrate() { try { if (navigator.vibrate) navigator.vibrate([150, 80, 150]); } catch (e) {} }

  // ---------- Magnétomètre (micros / électronique) ----------
  let mag = { state: 'init', v: 0, d: 0, err: '' }, magBase = null, magStarted = false;
  function renderMag() {
    let s;
    if (mag.state === 'init') s = t('magInit');
    else if (mag.state === 'unsupported') s = t('magNotSupported');
    else if (mag.state === 'error') s = t('magUnavailable', { e: mag.err });
    else s = t('magField', { v: mag.v, d: mag.d }) + (mag.d > 25 ? t('magWarn') : '');
    $('magInfo').textContent = s;
  }
  function startMagnetometer() {
    if (magStarted) return;
    if (!('Magnetometer' in window)) { mag.state = 'unsupported'; renderMag(); return; }
    try {
      const sensor = new Magnetometer({ frequency: 10 });
      sensor.addEventListener('reading', () => {
        const v = Math.hypot(sensor.x, sensor.y, sensor.z);
        if (!isFinite(v)) return;
        magBase = magBase == null ? v : magBase * 0.995 + v * 0.005; // champ terrestre moyen
        const d = Math.abs(v - magBase);
        mag = { state: 'ok', v: Math.round(v), d: Math.round(d), err: '' };
        $('magBar').style.width = Math.min(100, d * 2) + '%';
        renderMag();
        if (d > 25 && running && $('sound').checked && Date.now() - lastAlert > 1500) { beep(); lastAlert = Date.now(); }
      });
      sensor.addEventListener('error', e => { mag = { state: 'error', err: (e.error && e.error.name) || '?' }; renderMag(); });
      sensor.start(); magStarted = true;
    } catch (e) { mag = { state: 'error', err: e.name || e.message }; renderMag(); }
  }

  $('startBtn').onclick = start;
  $('torchBtn').onclick = toggleTorch;
  $('switchBtn').onclick = switchCamera;
  $('snapBtn').onclick = () => takePhoto(tracker.tracks.filter(x => x.hits >= MIN_HITS && x.miss === 0), work.width, false);

  const App = window.App;
  Object.assign(App, {
    t, on, showTab, start, stop, setStatus, iconBtn, openViewer, infoText,
    isRunning: () => running,
    settings: () => ({ mode: $('mode').value, sensitivity: +$('sens').value }),
    store: (name, mode, fn) => run(mode, fn, name),
    getPhoto: id => run('readonly', s => s.get(id))
  });
  refreshTexts();
  updateCount();
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
})();
