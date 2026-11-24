// Mode « Rapport de scan » : vérification pièce par pièce + rapport daté avec photos.
(function () {
  'use strict';
  const App = window.App;
  const $ = id => document.getElementById(id);
  const t = (k, v) => I18N.t(k, v);
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const SHORT_SCAN_MS = 20000;

  // ---------- Stockage ----------
  const reports = {
    all: () => App.store('reports', 'readonly', s => s.getAll()),
    get: id => App.store('reports', 'readonly', s => s.get(id)),
    put: r => App.store('reports', 'readwrite', s => s.put(r)),
    del: id => App.store('reports', 'readwrite', s => s.delete(id))
  };
  let draft = null;          // rapport en cours
  let session = null;        // pièce en cours de scan

  async function loadDraft() {
    try { draft = (await reports.all()).find(r => r.status === 'draft') || null; } catch (e) { draft = null; }
  }
  async function saveDraft() { if (draft) draft.id = await reports.put(draft); }

  // ---------- Écran « Rapport » ----------
  async function render() {
    $('reportNew').hidden = !!draft;
    $('reportCurrent').hidden = !draft;
    renderSuggestions();
    if (draft) renderDraft();
    renderList();
  }

  function renderSuggestions() {
    const box = $('roomSuggest'); box.innerHTML = '';
    const names = draft ? draft.rooms.map(r => r.name.toLowerCase()) : [];
    (t('repSuggest') || []).forEach(name => {
      if (names.includes(name.toLowerCase())) return;
      const b = document.createElement('button'); b.className = 'chip'; b.type = 'button'; b.textContent = '+ ' + name;
      b.onclick = () => addRoom(name);
      box.appendChild(b);
    });
  }

  function statusBadge(st) {
    const map = { clear: ['ok', 'stClear'], false: ['warn', 'stFalse'], suspect: ['bad', 'stSuspect'], pending: ['idle', 'stPending'] };
    const [cls, key] = map[st] || map.pending;
    const s = document.createElement('span'); s.className = 'badge ' + cls; s.textContent = t(key);
    return s;
  }

  function renderDraft() {
    $('repHead').textContent = draft.property + (draft.address ? ' — ' + draft.address : '');
    const ul = $('roomList'); ul.innerHTML = '';
    draft.rooms.forEach(room => {
      const li = document.createElement('li'); li.className = 'room';
      const top = document.createElement('div'); top.className = 'room-top';
      const name = document.createElement('b'); name.textContent = room.name;
      top.append(name, statusBadge(room.status));
      li.appendChild(top);
      if (room.status !== 'pending') {
        const st = document.createElement('div'); st.className = 'small';
        st.textContent = t('roomStats', { d: fmtDur(room.durationMs), a: room.alerts, p: room.photoIds.length })
          + (room.durationMs < SHORT_SCAN_MS ? ' • ⚠️ ' + t('repShortScan') : '') + (room.note ? ' • ' + room.note : '');
        li.appendChild(st);
      }
      const acts = document.createElement('div'); acts.className = 'room-acts';
      const bScan = document.createElement('button'); bScan.textContent = t(room.status === 'pending' ? 'repScanRoom' : 'repRescan');
      bScan.className = room.status === 'pending' ? 'primary' : '';
      bScan.onclick = () => startRoom(room.id);
      const bDel = App.iconBtn('🗑', t('delete'));
      bDel.onclick = async () => { draft.rooms = draft.rooms.filter(r => r.id !== room.id); await saveDraft(); render(); };
      acts.append(bScan, bDel);
      li.appendChild(acts);
      ul.appendChild(li);
    });
  }

  async function renderList() {
    const box = $('reportList'); box.innerHTML = '';
    let list = [];
    try { list = (await reports.all()).filter(r => r.status === 'final').reverse(); } catch (e) { /* stockage indisponible */ }
    if (!list.length) { const p = document.createElement('p'); p.className = 'small'; p.textContent = t('repNone'); box.appendChild(p); return; }
    list.forEach(r => {
      const card = document.createElement('div'); card.className = 'card rep-card';
      const h = document.createElement('b'); h.textContent = r.property;
      const meta = document.createElement('div'); meta.className = 'small';
      const susp = r.rooms.filter(x => x.status === 'suspect').length;
      meta.textContent = new Date(r.finishedAt).toLocaleString(I18N.lang) + ' • ' + t('repId') + ' ' + r.hash;
      const sum = document.createElement('div'); sum.className = 'small';
      sum.textContent = susp ? t('repSummarySuspect', { s: susp, n: r.rooms.length }) : t('repSummaryClear', { n: r.rooms.length });
      const acts = document.createElement('div'); acts.className = 'room-acts';
      const bView = document.createElement('button'); bView.textContent = t('repView'); bView.onclick = () => openReport(r);
      const bShare = document.createElement('button'); bShare.textContent = t('repShare'); bShare.onclick = () => shareReport(r);
      const bDel = App.iconBtn('🗑', t('delete'));
      bDel.onclick = async () => { if (confirm(t('repDeleteConfirm'))) { await reports.del(r.id); renderList(); } };
      acts.append(bView, bShare, bDel);
      card.append(h, meta, sum, acts);
      box.appendChild(card);
    });
  }

  // ---------- Création / pièces ----------
  async function createDraft() {
    const property = $('repProperty').value.trim();
    if (!property) { alert(t('repNeedName')); $('repProperty').focus(); return; }
    draft = {
      status: 'draft', property, address: $('repAddress').value.trim(), by: $('repBy').value.trim(),
      createdAt: new Date().toISOString(), rooms: [], nextRoom: 1
    };
    await saveDraft();
    $('repProperty').value = $('repAddress').value = $('repBy').value = '';
    render();
  }

  async function addRoom(name) {
    name = String(name || '').trim();
    if (!name || !draft) return;
    draft.rooms.push({ id: draft.nextRoom++, name, status: 'pending', note: '', durationMs: 0, frames: 0, alerts: 0, photoIds: [], scannedAt: null });
    await saveDraft();
    render();
  }

  async function cancelDraft() {
    if (!draft || !confirm(t('repConfirmCancel'))) return;
    endSession(false);
    await reports.del(draft.id);
    draft = null;
    render();
  }

  // ---------- Scan d'une pièce ----------
  function startRoom(roomId) {
    const room = draft && draft.rooms.find(r => r.id === roomId);
    if (!room) return;
    session = { roomId, start: Date.now(), frames: 0, alertIds: new Set(), photoIds: [] };
    App.context = { reportId: draft.id, roomId };
    $('roomBarName').textContent = t('roomScanning', { room: room.name });
    $('roomBar').hidden = false;
    App.showTab('scan');
    if (!App.isRunning()) App.start();
  }

  App.on('frame', ({ confirmed, crowded }) => {
    if (!session || !App.isRunning()) return;
    session.frames++;
    if (!crowded) confirmed.forEach(c => session.alertIds.add(c.id));
  });
  App.on('photo', ({ id }) => { if (session) session.photoIds.push(id); });

  function finishRoom() {
    if (!session) return;
    if (App.isRunning()) App.stop();
    const room = draft.rooms.find(r => r.id === session.roomId);
    const dur = Date.now() - session.start, alerts = session.alertIds.size;
    $('resTitle').textContent = t('roomResultTitle', { room: room.name });
    $('resStats').textContent = t('roomStats', { d: fmtDur(dur), a: alerts, p: session.photoIds.length }) + (dur < SHORT_SCAN_MS ? ' • ⚠️ ' + t('repShortScan') : '');
    document.querySelectorAll('input[name=roomRes]').forEach(i => { i.checked = i.value === (alerts ? 'false' : 'clear'); });
    $('resNote').value = room.note || '';
    session.durationMs = dur; session.alerts = alerts;
    $('roomResult').hidden = false;
  }

  async function saveRoomResult() {
    const room = draft.rooms.find(r => r.id === session.roomId);
    const choice = document.querySelector('input[name=roomRes]:checked');
    Object.assign(room, {
      status: choice ? choice.value : 'clear', note: $('resNote').value.trim(),
      durationMs: session.durationMs, frames: session.frames, alerts: session.alerts,
      photoIds: session.photoIds.slice(), scannedAt: new Date().toISOString()
    });
    $('roomResult').hidden = true;
    endSession(true);
    await saveDraft();
    App.showTab('report');
  }

  function endSession(keep) {
    session = null;
    App.context = null;
    $('roomBar').hidden = true;
    if (!keep) $('roomResult').hidden = true;
  }

  // ---------- Rapport final ----------
  async function finishDraft() {
    if (!draft) return;
    const scanned = draft.rooms.filter(r => r.status !== 'pending');
    if (!scanned.length) { alert(t('repNeedRoom')); return; }
    const btn = $('repFinishBtn'); btn.disabled = true; btn.textContent = t('repGenerating');
    try {
      const photos = {};
      for (const room of scanned) {
        for (const pid of room.photoIds) {
          try { const p = await App.getPhoto(pid); if (p && p.blob) photos[pid] = await shrink(p.blob, 1000); } catch (e) { /* photo supprimée */ }
        }
      }
      const final = {
        status: 'final', property: draft.property, address: draft.address, by: draft.by,
        createdAt: draft.createdAt, finishedAt: new Date().toISOString(), lang: I18N.lang,
        settings: App.settings(), rooms: scanned.map(r => Object.assign({}, r, { photoIds: r.photoIds.filter(id => photos[id]) })),
        photos
      };
      final.hash = await fingerprint(final);
      final.id = draft.id;
      await reports.put(final);
      draft = null;
      await render();
      openReport(final);
    } finally {
      btn.disabled = false; btn.textContent = t('repFinish');
    }
  }

  // Réduit une photo pour que le rapport reste léger (et partageable).
  function shrink(blob, max) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(blob);
      const img = new Image();
      img.onload = () => {
        const k = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
        const c = document.createElement('canvas');
        c.width = Math.round(img.naturalWidth * k); c.height = Math.round(img.naturalHeight * k);
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(url);
        resolve(c.toDataURL('image/jpeg', 0.72));
      };
      img.onerror = e => { URL.revokeObjectURL(url); reject(e); };
      img.src = url;
    });
  }

  // N° du rapport : empreinte du contenu (change si le contenu change).
  async function fingerprint(rep) {
    const txt = JSON.stringify([rep.property, rep.address, rep.by, rep.createdAt, rep.finishedAt, rep.rooms, Object.keys(rep.photos).map(k => rep.photos[k].length)]);
    try {
      const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(txt));
      return Array.from(new Uint8Array(buf).slice(0, 5)).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
    } catch (e) {
      let h = 2166136261; for (let i = 0; i < txt.length; i++) { h ^= txt.charCodeAt(i); h = Math.imul(h, 16777619); }
      return (h >>> 0).toString(16).toUpperCase().padStart(8, '0');
    }
  }

  function fmtDur(ms) {
    const s = Math.round((ms || 0) / 1000), m = Math.floor(s / 60);
    return m ? m + ' min ' + String(s % 60).padStart(2, '0') + ' s' : s + ' s';
  }

  // Le document du rapport (le même pour l'affichage, l'impression et le fichier partagé).
  const REP_CSS = `
.rep{background:#fff;color:#111;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;line-height:1.4;max-width:800px;margin:0 auto;padding:24px}
.rep h1{font-size:1.35rem;margin:0 0 4px}.rep h2{font-size:1.1rem;margin:0}
.rep .muted{color:#555;font-size:.9rem}.rep table{border-collapse:collapse;width:100%;margin:12px 0;font-size:.92rem}
.rep td{border:1px solid #ccc;padding:6px 8px;vertical-align:top}.rep td:first-child{width:35%;color:#444}
.rep .sum{padding:10px 12px;border-radius:8px;margin:12px 0;font-weight:600}.rep .sum.ok{background:#e8f6ec}.rep .sum.bad{background:#fdeaea}
.rep .rroom{background:#fff;color:#111;border:1px solid #ccc;border-radius:8px;padding:10px 12px;margin:10px 0;break-inside:avoid}
.rep .st{display:inline-block;padding:2px 8px;border-radius:10px;font-size:.85rem;font-weight:600;margin-top:4px}
.rep .st.clear{background:#e8f6ec;color:#14532d}.rep .st.false{background:#fff4d6;color:#713f12}.rep .st.suspect{background:#fdeaea;color:#7f1d1d}
.rep .ph{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:6px;margin-top:8px}.rep .ph img{width:100%;border-radius:4px}
.rep .disc{font-size:.82rem;color:#444;border-top:1px solid #ccc;margin-top:16px;padding-top:10px}
.rep .sig{margin-top:28px;display:flex;gap:24px}.rep .sig div{flex:1;border-top:1px solid #888;padding-top:4px;font-size:.85rem;color:#444}
.rep[dir=rtl] td:first-child{text-align:right}`;

  function reportBody(r) {
    const L = (k, v) => I18N.tIn(r.lang, k, v);
    const loc = r.lang;
    const dir = I18N._T[r.lang] && I18N._T[r.lang]._rtl ? 'rtl' : 'ltr';
    const susp = r.rooms.filter(x => x.status === 'suspect').length;
    const modeName = L(r.settings && r.settings.mode === 'ir' ? 'modeNameIR' : 'modeNameReflect');
    const stKey = { clear: 'stClear', false: 'stFalse', suspect: 'stSuspect' };
    let h = `<div class="rep" dir="${dir}" lang="${esc(loc)}">`;
    h += `<h1>${esc(L('repDocTitle'))}</h1><h2><bdi>${esc(r.property)}</bdi></h2>`;
    if (r.address) h += `<div class="muted"><bdi>${esc(r.address)}</bdi></div>`;
    h += `<table>
      <tr><td>${esc(L('repId'))}</td><td><b>${esc(r.hash)}</b></td></tr>
      <tr><td>${esc(L('repStarted'))}</td><td>${esc(new Date(r.createdAt).toLocaleString(loc))}</td></tr>
      <tr><td>${esc(L('repFinished'))}</td><td>${esc(new Date(r.finishedAt).toLocaleString(loc))}</td></tr>
      ${r.by ? `<tr><td>${esc(L('repBy').replace(/\s*\(.*\)\s*$/, ''))}</td><td><bdi>${esc(r.by)}</bdi></td></tr>` : ''}
      <tr><td>${esc(L('repSettings'))}</td><td>${esc(modeName)} • ${esc(L('sensitivity'))} ${esc(r.settings ? r.settings.sensitivity : '')}</td></tr>
    </table>`;
    h += susp ? `<div class="sum bad">${esc(L('repSummarySuspect', { s: susp, n: r.rooms.length }))}</div>`
              : `<div class="sum ok">${esc(L('repSummaryClear', { n: r.rooms.length }))}</div>`;
    r.rooms.forEach(room => {
      h += `<div class="rroom"><b><bdi>${esc(room.name)}</bdi></b><br><span class="st ${esc(room.status)}">${esc(L(stKey[room.status] || 'stClear'))}</span>`;
      h += `<div class="muted">${esc(new Date(room.scannedAt).toLocaleTimeString(loc))} • ${esc(L('roomStats', { d: fmtDur(room.durationMs), a: room.alerts, p: room.photoIds.length }))}${room.durationMs < SHORT_SCAN_MS ? ' • ⚠️ ' + esc(L('repShortScan')) : ''}</div>`;
      if (room.note) h += `<div><bdi>${esc(room.note)}</bdi></div>`;
      if (room.photoIds.length) h += '<div class="ph">' + room.photoIds.map(id => `<img src="${r.photos[id]}" alt="">`).join('') + '</div>';
      h += '</div>';
    });
    h += `<div class="disc">${esc(L('repDisclaimer'))}</div>`;
    h += `<div class="sig"><div>${esc(L('repSignature'))}</div><div>${esc(L('repDateSig'))}</div></div></div>`;
    return h;
  }

  function reportFile(r) {
    const title = I18N.tIn(r.lang, 'repDocTitle') + ' — ' + r.property;
    return `<!doctype html><html lang="${esc(r.lang)}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title><style>body{margin:0;background:#fff}${REP_CSS}</style></head><body>${reportBody(r)}</body></html>`;
  }
  function fileName(r) {
    const slug = String(r.property).normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'rapport';
    return 'rapport-' + slug + '-' + r.finishedAt.slice(0, 10) + '.html';
  }

  let viewing = null;
  function openReport(r) {
    viewing = r;
    $('reportDoc').innerHTML = '<style>' + REP_CSS + '</style>' + reportBody(r);
    $('reportOverlay').hidden = false;
    $('reportOverlay').scrollTop = 0;
  }
  function closeReport() { $('reportOverlay').hidden = true; $('reportDoc').innerHTML = ''; viewing = null; }

  async function shareReport(r) {
    const html = reportFile(r);
    const name = fileName(r);
    const file = typeof File === 'function' ? new File([html], name, { type: 'text/html' }) : null;
    if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
      try { await navigator.share({ files: [file], title: r.property }); return; } catch (e) { if (e && e.name === 'AbortError') return; }
    }
    const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }));
    const a = document.createElement('a'); a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }

  function printReport() {
    document.body.classList.add('print-report');
    const done = () => { document.body.classList.remove('print-report'); window.removeEventListener('afterprint', done); };
    window.addEventListener('afterprint', done);
    window.print();
    setTimeout(done, 60000);
  }

  // ---------- Événements ----------
  $('repStartBtn').onclick = createDraft;
  $('repCancelBtn').onclick = cancelDraft;
  $('repFinishBtn').onclick = finishDraft;
  $('roomAddBtn').onclick = () => { addRoom($('roomName').value); $('roomName').value = ''; };
  $('roomName').addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); $('roomAddBtn').click(); } });
  $('roomDoneBtn').onclick = finishRoom;
  $('resSave').onclick = saveRoomResult;
  $('repViewClose').onclick = closeReport;
  $('repViewPrint').onclick = printReport;
  $('repViewShare').onclick = () => viewing && shareReport(viewing);
  App.on('tab', name => { if (name === 'report') render(); });
  document.addEventListener('langchange', () => {
    if (session) { const room = draft.rooms.find(r => r.id === session.roomId); $('roomBarName').textContent = t('roomScanning', { room: room.name }); }
    if ($('report').classList.contains('active')) render();
  });

  loadDraft().then(render);
  window.Report = { _reportBody: reportBody, _fmtDur: fmtDur };
})();
