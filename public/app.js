'use strict';

/*
 * Holescope · сбор данных v0.1 — запись акселерометра, гироскопа и GPS в поездке.
 * Задача версии: собрать размеченные данные по ташкентским дорогам,
 * чтобы подобрать алгоритм определения ям до разработки полноценного приложения.
 *
 * Всё хранится на телефоне (IndexedDB), на сервер ничего не отправляется.
 */

const APP_VERSION = '0.1.0';

const LABELS = {
  pothole: 'Яма',
  manhole: 'Люк',
  bump: 'Лежачий',
  rail: 'Рельсы / стык',
};

// Порядок колонок CSV. Пустые значения — пустые ячейки.
const COLS = [
  'type', 't_ms', 'lat', 'lon', 'gps_acc_m', 'speed_ms', 'heading_deg',
  'ax', 'ay', 'az', 'lx', 'ly', 'lz', 'rx', 'ry', 'rz', 'label', 'note',
];
/*
 * type: m — отсчёт датчиков, g — GPS-фикс, k — отметка вручную,
 *       a — авто-кандидат, u — отмена отметки (note = t_ms отменённой),
 *       v — экран скрыт/показан (разрыв данных)
 * ax,ay,az — accelerationIncludingGravity (м/с²); lx,ly,lz — acceleration без гравитации;
 * rx,ry,rz — rotationRate beta, gamma, alpha (°/с)
 */

const FLUSH_MS = 10000;        // как часто сбрасывать буфер в IndexedDB
const MIN_SPEED_MS = 3;        // ниже ~11 км/ч автоопределение молчит
const GPS_STALE_MS = 4000;     // GPS-скорость старше этого считается неизвестной
const AUTO_WINDOW_MS = 150;    // окно, в котором ищем пик после срабатывания порога
const AUTO_COOLDOWN_MS = 1500; // не чаще одного кандидата за это время
const GRAV_K = 0.985;          // коэффициент фильтра гравитации
const GRAPH_MS = 6000;         // сколько секунд показывает график

const $ = (id) => document.getElementById(id);

/* ---------- утилиты ---------- */

const pad = (n) => String(n).padStart(2, '0');
const r4 = (v) => (v == null ? null : Math.round(v * 1e4) / 1e4);

function fmtDur(sec) {
  sec = Math.max(0, Math.round(sec));
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}
function fmtClock(ms) {
  const d = new Date(ms);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}
function fmtStamp(ms) {
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
}
function fmtDate(ms) {
  const d = new Date(ms);
  return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371000, rad = Math.PI / 180;
  const dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

function csvCell(v) {
  if (v == null) return '';
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : '';
  const s = String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function lsGet(key, fallback) {
  try { const v = localStorage.getItem(key); return v == null ? fallback : v; } catch (e) { return fallback; }
}
function lsSet(key, value) {
  try { localStorage.setItem(key, value); } catch (e) { /* приватный режим — не критично */ }
}

/* ---------- хранилище (IndexedDB с запасным вариантом в памяти) ---------- */

const store = (() => {
  let db = null;
  let inMemory = false;
  const mem = { sessions: new Map(), chunks: new Map() };

  function open() {
    return new Promise((resolve) => {
      if (!('indexedDB' in window)) { inMemory = true; resolve(); return; }
      let req;
      try { req = indexedDB.open('pothole-logger', 1); } catch (e) { inMemory = true; resolve(); return; }
      req.onupgradeneeded = () => {
        const d = req.result;
        d.createObjectStore('sessions', { keyPath: 'id' });
        d.createObjectStore('chunks', { keyPath: ['sid', 'seq'] });
      };
      req.onsuccess = () => { db = req.result; resolve(); };
      req.onerror = () => { inMemory = true; resolve(); };
    });
  }

  function run(storeName, mode, fn) {
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, mode);
      let result;
      const r = fn(tx.objectStore(storeName));
      if (r) r.onsuccess = () => { result = r.result; };
      tx.oncomplete = () => resolve(result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  }

  const range = (sid) => IDBKeyRange.bound([sid, 0], [sid, Infinity]);

  return {
    open,
    get inMemory() { return inMemory; },
    async putSession(s) {
      if (inMemory) { mem.sessions.set(s.id, { ...s }); return; }
      await run('sessions', 'readwrite', (st) => st.put(s));
    },
    async getSession(id) {
      if (inMemory) return mem.sessions.get(id);
      return run('sessions', 'readonly', (st) => st.get(id));
    },
    async allSessions() {
      if (inMemory) return [...mem.sessions.values()];
      return run('sessions', 'readonly', (st) => st.getAll());
    },
    async putChunk(sid, seq, rows) {
      if (inMemory) {
        if (!mem.chunks.has(sid)) mem.chunks.set(sid, []);
        mem.chunks.get(sid).push({ sid, seq, rows });
        return;
      }
      await run('chunks', 'readwrite', (st) => st.put({ sid, seq, rows }));
    },
    async getChunks(sid) {
      if (inMemory) return mem.chunks.get(sid) || [];
      return run('chunks', 'readonly', (st) => st.getAll(range(sid)));
    },
    async deleteSession(sid) {
      if (inMemory) { mem.sessions.delete(sid); mem.chunks.delete(sid); return; }
      await run('chunks', 'readwrite', (st) => st.delete(range(sid)));
      await run('sessions', 'readwrite', (st) => st.delete(sid));
    },
  };
})();

/* ---------- состояние ---------- */

const S = {
  recording: false,
  starting: false,
  sid: null,
  session: null,
  seq: 0,
  buf: [],
  rowCount: 0,
  flushChain: Promise.resolve(),
  flushTimer: null,
  tickTimer: null,
  raf: 0,
  watchId: null,
  startT: 0,

  motionN: 0,
  gpsN: 0,
  autoN: 0,
  marks: [],            // активные (не отменённые) отметки текущей записи
  lastMotionT: 0,

  fix: null,            // последний GPS-фикс
  gpsError: null,
  grav: null,           // оценка гравитации (фильтр нижних частот)
  vz: 0,
  graph: [],            // [t, vz]
  pend: null,           // окно поиска пика автокандидата
  lastAutoT: 0,
  lastPeak: null,

  threshold: 5,
  sound: true,
  wake: 'off',
  lock: null,
  hzPrevN: 0,
  hzPrevT: 0,
  hz: 0,

  files: new Map(),     // sid -> File (подготовленные CSV)
  confirmDelete: null,
};

/* ---------- звук ---------- */

let actx = null;
function initAudio() {
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    if (actx.state === 'suspended') actx.resume();
  } catch (e) { actx = null; }
}
function beep(freq, ms) {
  if (!S.sound || !actx) return;
  try {
    const o = actx.createOscillator(), g = actx.createGain();
    o.frequency.value = freq;
    g.gain.value = 0.08;
    o.connect(g); g.connect(actx.destination);
    o.start();
    o.stop(actx.currentTime + ms / 1000);
  } catch (e) { /* звук — удобство, не необходимость */ }
}

/* ---------- запись строк ---------- */

function mk(type, t, o) {
  o = o || {};
  const r = new Array(COLS.length);
  for (let i = 0; i < COLS.length; i++) {
    const c = COLS[i];
    r[i] = c === 'type' ? type : c === 't_ms' ? t : (o[c] == null ? null : o[c]);
  }
  return r;
}
function pushRow(r) { S.buf.push(r); S.rowCount++; }

function curSpeed() {
  const f = S.fix;
  if (!f || Date.now() - f.recvT > GPS_STALE_MS) return null;
  return f.speed;
}

function flush() {
  if (!S.sid) return S.flushChain;
  const sid = S.sid, session = S.session;
  const rows = S.buf;
  S.buf = [];
  const seq = rows.length ? S.seq++ : -1;
  session.rows = S.rowCount;
  session.motion = S.motionN;
  session.gps = S.gpsN;
  session.marks = S.marks.length;
  session.auto = S.autoN;
  session.lastT = Date.now();
  const snapshot = { ...session };
  S.flushChain = S.flushChain
    .then(async () => {
      if (seq >= 0) await store.putChunk(sid, seq, rows);
      await store.putSession(snapshot);
    })
    .catch((e) => {
      console.error(e);
      showBanner('Не удалось сохранить часть данных в память браузера.', 'error');
    });
  return S.flushChain;
}

/* ---------- датчики движения ---------- */

function onMotion(e) {
  if (!S.recording) return;
  const t = Date.now();
  const g = e.accelerationIncludingGravity || {};
  const l = e.acceleration || {};
  const r = e.rotationRate || {};
  S.motionN++;
  S.lastMotionT = t;
  pushRow(mk('m', t, {
    ax: r4(g.x), ay: r4(g.y), az: r4(g.z),
    lx: r4(l.x), ly: r4(l.y), lz: r4(l.z),
    rx: r4(r.beta), ry: r4(r.gamma), rz: r4(r.alpha),
  }));

  if (g.x == null || g.y == null || g.z == null) return;

  // Вертикальная динамическая составляющая: ускорение минус оценка гравитации,
  // спроецированное на направление гравитации. Не зависит от положения телефона,
  // пока он неподвижен относительно машины.
  const gv = [g.x, g.y, g.z];
  if (!S.grav) S.grav = gv.slice();
  for (let i = 0; i < 3; i++) S.grav[i] = GRAV_K * S.grav[i] + (1 - GRAV_K) * gv[i];
  const gm = Math.hypot(S.grav[0], S.grav[1], S.grav[2]) || 1;
  const vz = ((gv[0] - S.grav[0]) * S.grav[0] + (gv[1] - S.grav[1]) * S.grav[1] + (gv[2] - S.grav[2]) * S.grav[2]) / gm;
  S.vz = vz;

  S.graph.push([t, vz]);
  while (S.graph.length && t - S.graph[0][0] > GRAPH_MS) S.graph.shift();

  detect(t, vz);
}

function detect(t, vz) {
  const av = Math.abs(vz);

  // Окно поиска пика уже открыто: ищем максимум и закрываем по истечении
  if (S.pend) {
    if (av > S.pend.peak) S.pend.peak = av;
    if (t - S.pend.t >= AUTO_WINDOW_MS) finalizeAuto();
    return;
  }

  const sp = curSpeed();
  if (sp == null || sp < MIN_SPEED_MS) return;
  if (av < S.threshold) return;
  if (t - S.lastAutoT < AUTO_COOLDOWN_MS) return;

  S.pend = { t, peak: av, lat: S.fix.lat, lon: S.fix.lon, acc: S.fix.acc, speed: sp };
}

function finalizeAuto() {
  const p = S.pend;
  if (!p) return;
  S.pend = null;
  S.lastAutoT = p.t;
  S.autoN++;
  S.lastPeak = p.peak;
  pushRow(mk('a', p.t, {
    lat: p.lat, lon: p.lon, gps_acc_m: p.acc, speed_ms: p.speed,
    label: 'auto', note: p.peak.toFixed(2),
  }));
  beep(520, 70);
}

/* ---------- GPS ---------- */

function onPos(p) {
  if (!S.recording) return;
  const c = p.coords;
  const t = p.timestamp || Date.now();
  let sp = c.speed != null && c.speed >= 0 ? c.speed : null;
  if (sp == null && S.fix) {
    // Скорость по смещению считаем, только если оно заметно больше погрешности GPS.
    // Иначе «дрожание» точки (±20 м) превращается в ложное движение.
    const dt = (t - S.fix.t) / 1000;
    if (dt > 0 && dt < 10) {
      const d = haversine(S.fix.lat, S.fix.lon, c.latitude, c.longitude);
      const noise = Math.max(c.accuracy || 0, S.fix.acc || 0);
      sp = d > noise ? d / dt : 0;
    }
  }
  S.fix = { t, recvT: Date.now(), lat: c.latitude, lon: c.longitude, acc: c.accuracy, speed: sp };
  S.gpsError = null;
  S.gpsN++;
  // В файл идёт «сырая» скорость от GPS (может быть пустой); производную считает анализатор.
  pushRow(mk('g', t, {
    lat: c.latitude, lon: c.longitude, gps_acc_m: c.accuracy,
    speed_ms: c.speed != null && c.speed >= 0 ? r4(c.speed) : null,
    heading_deg: c.heading != null && !Number.isNaN(c.heading) ? r4(c.heading) : null,
  }));
}

function onPosErr(err) {
  S.gpsError = err && err.code === 1 ? 'denied' : 'error';
  if (err && err.code === 1) {
    showBanner('Нет доступа к геолокации. iPhone: Настройки → Конфиденциальность → Службы геолокации → Safari → «При использовании».', 'error');
  }
}

/* ---------- экран не должен гаснуть ---------- */

async function requestWakeLock() {
  if (!('wakeLock' in navigator)) { S.wake = 'unsupported'; return; }
  try {
    S.lock = await navigator.wakeLock.request('screen');
    S.wake = 'on';
    S.lock.addEventListener('release', () => { S.wake = 'off'; });
  } catch (e) {
    S.wake = 'off';
  }
}
function releaseWakeLock() {
  try { if (S.lock) S.lock.release(); } catch (e) { /* уже освобождён */ }
  S.lock = null;
  S.wake = 'off';
}

document.addEventListener('visibilitychange', () => {
  if (!S.recording) return;
  const t = Date.now();
  if (document.visibilityState === 'hidden') {
    pushRow(mk('v', t, { note: 'hidden' }));
    flush();
  } else {
    pushRow(mk('v', t, { note: 'visible' }));
    requestWakeLock();
    showBanner('Экран гас или приложение сворачивалось — часть данных потеряна. Поставьте Автоблокировку «Никогда» (Настройки → Экран и яркость).', 'warn');
  }
});
window.addEventListener('pagehide', () => {
  if (!S.recording) return;
  pushRow(mk('v', Date.now(), { note: 'pagehide' }));
  flush();
});

/* ---------- запуск / остановка ---------- */

async function start() {
  if (S.recording || S.starting) return;
  S.starting = true;
  hideBanner();
  initAudio(); // должно произойти внутри жеста пользователя

  try {
    if (typeof DeviceMotionEvent === 'undefined') {
      throw new Error('Датчики движения недоступны в этом браузере.');
    }
    if (typeof DeviceMotionEvent.requestPermission === 'function') {
      const res = await DeviceMotionEvent.requestPermission();
      if (res !== 'granted') {
        throw new Error('Доступ к датчикам запрещён. Закройте вкладку, откройте страницу заново и нажмите «Разрешить».');
      }
    }
  } catch (e) {
    showBanner(e.message || String(e), 'error');
    S.starting = false;
    return;
  }

  const car = $('car').value.trim();
  const mount = $('mount').value;
  const now = Date.now();
  S.sid = 's' + now;
  S.session = {
    id: S.sid, startedAt: now, endedAt: null, lastT: now,
    car, mount, threshold: S.threshold, version: APP_VERSION, ua: navigator.userAgent,
    rows: 0, motion: 0, gps: 0, marks: 0, auto: 0,
  };
  try { await store.putSession(S.session); } catch (e) { console.error(e); }

  Object.assign(S, {
    seq: 0, buf: [], rowCount: 0, flushChain: Promise.resolve(),
    motionN: 0, gpsN: 0, autoN: 0, marks: [], fix: null, gpsError: null,
    grav: null, vz: 0, graph: [], pend: null, lastAutoT: 0, lastPeak: null,
    hzPrevN: 0, hzPrevT: now, hz: 0, startT: now, lastMotionT: 0,
  });

  window.addEventListener('devicemotion', onMotion);
  if ('geolocation' in navigator) {
    S.watchId = navigator.geolocation.watchPosition(onPos, onPosErr, {
      enableHighAccuracy: true, maximumAge: 0, timeout: 20000,
    });
  } else {
    S.gpsError = 'unsupported';
    showBanner('Геолокация недоступна: скорость неизвестна, автоопределение работать не будет.', 'warn');
  }

  S.recording = true;
  S.starting = false;
  await requestWakeLock();
  S.flushTimer = setInterval(flush, FLUSH_MS);
  S.tickTimer = setInterval(tick, 500);
  S.raf = requestAnimationFrame(loop);
  beep(700, 80);
  renderAll();
}

async function stop() {
  if (!S.recording) return;
  S.recording = false;
  window.removeEventListener('devicemotion', onMotion);
  if (S.watchId != null && navigator.geolocation) navigator.geolocation.clearWatch(S.watchId);
  S.watchId = null;
  clearInterval(S.flushTimer);
  clearInterval(S.tickTimer);
  cancelAnimationFrame(S.raf);
  releaseWakeLock();
  finalizeAuto();

  const sid = S.sid;
  S.session.endedAt = Date.now();
  await flush();
  await refreshSessions();
  renderAll();
  await prepareFile(sid);
  await refreshSessions();
}

/* ---------- отметки ---------- */

function mark(label) {
  if (!S.recording) return;
  const t = Date.now();
  const f = S.fix;
  pushRow(mk('k', t, {
    lat: f ? f.lat : null, lon: f ? f.lon : null, gps_acc_m: f ? f.acc : null,
    speed_ms: curSpeed(), label,
  }));
  S.marks.push({ t, label });
  beep(1000, 70);
  renderLastMark();
  renderCounts();
  const btn = document.querySelector(`.mk[data-label="${label}"]`);
  if (btn) { btn.classList.add('flash'); setTimeout(() => btn.classList.remove('flash'), 180); }
}

function undoMark() {
  if (!S.recording || !S.marks.length) return;
  const m = S.marks.pop();
  pushRow(mk('u', Date.now(), { label: m.label, note: String(m.t) }));
  renderLastMark();
  renderCounts();
}

/* ---------- интерфейс ---------- */

function showBanner(text, kind) {
  const b = $('banner');
  b.textContent = text;
  b.dataset.kind = kind || 'warn';
  b.hidden = false;
}
function hideBanner() { $('banner').hidden = true; }

function setChip(id, text, state) {
  const el = $(id);
  el.textContent = text;
  el.dataset.state = state || '';
}

function renderCounts() {
  $('nMarks').textContent = String(S.marks.length);
  $('nAuto').textContent = String(S.autoN);
}

function renderLastMark() {
  const el = $('lastMark');
  el.replaceChildren();
  if (!S.recording && !S.marks.length) { el.textContent = 'Отметок пока нет'; return; }
  const last = S.marks[S.marks.length - 1];
  if (!last) { el.textContent = 'Отметок пока нет'; return; }
  const span = document.createElement('span');
  span.textContent = `Последняя: ${LABELS[last.label]} в ${fmtClock(last.t)}`;
  el.appendChild(span);
  if (S.recording) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = 'Отменить';
    b.addEventListener('click', undoMark);
    el.appendChild(b);
  }
}

function renderAll() {
  const btn = $('startBtn');
  btn.textContent = S.recording ? 'Остановить запись' : 'Начать запись';
  btn.dataset.recording = String(S.recording);
  document.querySelectorAll('.mk').forEach((b) => { b.disabled = !S.recording; });
  renderCounts();
  renderLastMark();
  tick();
  drawGraph();
}

function tick() {
  const now = Date.now();
  if (S.recording) {
    $('timer').textContent = fmtDur((now - S.startT) / 1000);
    const sp = curSpeed();
    $('speed').textContent = sp == null ? '—' : String(Math.round(sp * 3.6));
    $('speed').classList.toggle('empty', sp == null);

    const dt = (now - S.hzPrevT) / 1000;
    if (dt >= 1) {
      S.hz = (S.motionN - S.hzPrevN) / dt;
      S.hzPrevN = S.motionN;
      S.hzPrevT = now;
    }
    if (S.motionN === 0 && now - S.startT > 3000) {
      setChip('chipMotion', 'Датчик: нет данных', 'bad');
    } else {
      setChip('chipMotion', `Датчик: ${Math.round(S.hz)} Гц`, S.hz >= 20 ? 'ok' : 'warn');
    }

    if (S.gpsError === 'denied') setChip('chipGps', 'GPS: нет доступа', 'bad');
    else if (S.gpsError === 'unsupported') setChip('chipGps', 'GPS: недоступен', 'bad');
    else if (!S.fix) setChip('chipGps', 'GPS: ищу…', 'warn');
    else if (now - S.fix.recvT > GPS_STALE_MS) setChip('chipGps', 'GPS: нет сигнала', 'bad');
    else setChip('chipGps', `GPS: ±${Math.round(S.fix.acc)} м`, S.fix.acc <= 20 ? 'ok' : 'warn');

    if (S.wake === 'on') setChip('chipWake', 'Экран: не гаснет', 'ok');
    else if (S.wake === 'unsupported') setChip('chipWake', 'Экран: может погаснуть', 'warn');
    else setChip('chipWake', 'Экран: может погаснуть', 'warn');

    renderCounts();
  } else {
    $('speed').textContent = '—';
    $('speed').classList.add('empty');
    setChip('chipGps', 'GPS: —', '');
    setChip('chipMotion', 'Датчик: —', '');
    setChip('chipWake', 'Экран: —', '');
  }
}

/* ---------- график ---------- */

let graphW = 0, graphH = 0;
function drawGraph() {
  const cv = $('graph');
  const dpr = window.devicePixelRatio || 1;
  const w = cv.clientWidth, h = cv.clientHeight;
  if (!w || !h) return;
  if (w !== graphW || h !== graphH) {
    graphW = w; graphH = h;
    cv.width = Math.round(w * dpr);
    cv.height = Math.round(h * dpr);
  }
  const ctx = cv.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  const range = Math.max(10, S.threshold * 2);
  const y = (v) => h / 2 - (Math.max(-range, Math.min(range, v)) / range) * (h / 2 - 4);

  ctx.lineWidth = 1;
  ctx.strokeStyle = '#2a2f3a';
  ctx.beginPath(); ctx.moveTo(0, h / 2); ctx.lineTo(w, h / 2); ctx.stroke();

  ctx.setLineDash([5, 4]);
  ctx.strokeStyle = '#6b4b10';
  for (const s of [1, -1]) {
    ctx.beginPath(); ctx.moveTo(0, y(s * S.threshold)); ctx.lineTo(w, y(s * S.threshold)); ctx.stroke();
  }
  ctx.setLineDash([]);

  if (S.graph.length > 1) {
    const now = S.graph[S.graph.length - 1][0];
    ctx.strokeStyle = '#ffb020';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    S.graph.forEach(([t, v], i) => {
      const x = w - ((now - t) / GRAPH_MS) * w;
      if (i === 0) ctx.moveTo(x, y(v)); else ctx.lineTo(x, y(v));
    });
    ctx.stroke();
  }
}

function loop() {
  if (!S.recording) return;
  drawGraph();
  S.raf = requestAnimationFrame(loop);
}

/* ---------- экспорт ---------- */

function sessionName(s) { return `pothole_${fmtStamp(s.startedAt)}.csv`; }

async function buildCsv(sid) {
  const s = await store.getSession(sid);
  if (!s) throw new Error('Запись не найдена');
  const chunks = await store.getChunks(sid);
  const clean = (v) => String(v == null ? '' : v).replace(/[\r\n]+/g, ' ');
  const out = [
    `# pothole-logger ${s.version}`,
    `# session=${s.id}`,
    `# started=${new Date(s.startedAt).toISOString()}`,
    `# ended=${s.endedAt ? new Date(s.endedAt).toISOString() : 'interrupted'}`,
    `# car=${clean(s.car)}`,
    `# mount=${clean(s.mount)}`,
    `# auto_threshold_ms2=${s.threshold}`,
    `# user_agent=${clean(s.ua)}`,
    COLS.join(','),
  ];
  for (const ch of chunks) {
    for (const r of ch.rows) out.push(r.map(csvCell).join(','));
  }
  return { name: sessionName(s), text: out.join('\n') + '\n' };
}

async function prepareFile(sid) {
  try {
    const { name, text } = await buildCsv(sid);
    S.files.set(sid, new File([text], name, { type: 'text/csv' }));
  } catch (e) {
    console.error(e);
    showBanner('Не удалось подготовить файл: ' + (e.message || e), 'error');
  }
}

function downloadFile(file) {
  const url = URL.createObjectURL(file);
  const a = document.createElement('a');
  a.href = url;
  a.download = file.name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

async function shareFile(file) {
  try {
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title: file.name });
      return;
    }
  } catch (e) {
    if (e && e.name === 'AbortError') return; // пользователь закрыл меню
  }
  downloadFile(file);
}

async function refreshSessions() {
  const list = (await store.allSessions()).sort((a, b) => b.startedAt - a.startedAt);
  const root = $('sessions');
  root.replaceChildren();
  if (!list.length) {
    const p = document.createElement('p');
    p.className = 'empty';
    p.textContent = 'Пока пусто. После остановки записи здесь появится файл для отправки на компьютер.';
    root.appendChild(p);
    return;
  }
  for (const s of list) root.appendChild(sessionItem(s));
}

function sessionItem(s) {
  const el = document.createElement('div');
  el.className = 'session';

  const title = document.createElement('div');
  title.className = 'title';
  title.textContent = fmtDate(s.startedAt) + (s.car ? ` · ${s.car}` : '');
  el.appendChild(title);

  const end = s.endedAt || s.lastT || s.startedAt;
  const meta = document.createElement('div');
  meta.className = 'meta';
  const interrupted = !s.endedAt && !(S.recording && S.sid === s.id);
  meta.textContent = `${fmtDur((end - s.startedAt) / 1000)} · отметок ${s.marks || 0} · авто ${s.auto || 0} · строк ${s.rows || 0}` + (interrupted ? ' · прервана' : '');
  el.appendChild(meta);

  if (S.recording && S.sid === s.id) {
    const rec = document.createElement('div');
    rec.className = 'meta';
    rec.textContent = 'Идёт запись…';
    el.appendChild(rec);
    return el;
  }

  const actions = document.createElement('div');
  actions.className = 'actions';

  const file = S.files.get(s.id);
  if (file) {
    const share = document.createElement('button');
    share.type = 'button';
    share.className = 'accent';
    share.textContent = 'Поделиться';
    share.addEventListener('click', () => shareFile(file));
    actions.appendChild(share);

    const dl = document.createElement('button');
    dl.type = 'button';
    dl.textContent = 'Скачать';
    dl.addEventListener('click', () => downloadFile(file));
    actions.appendChild(dl);
  } else {
    const prep = document.createElement('button');
    prep.type = 'button';
    prep.className = 'accent';
    prep.textContent = 'Подготовить файл';
    prep.addEventListener('click', async () => {
      prep.disabled = true;
      prep.textContent = 'Готовлю…';
      await prepareFile(s.id);
      await refreshSessions();
    });
    actions.appendChild(prep);
  }

  const del = document.createElement('button');
  del.type = 'button';
  del.className = 'danger';
  if (S.confirmDelete === s.id) {
    del.className = 'confirm';
    del.textContent = 'Точно удалить?';
    del.addEventListener('click', async () => {
      S.confirmDelete = null;
      S.files.delete(s.id);
      await store.deleteSession(s.id);
      await refreshSessions();
    });
  } else {
    del.textContent = 'Удалить';
    del.addEventListener('click', () => {
      S.confirmDelete = s.id;
      refreshSessions();
      setTimeout(() => { if (S.confirmDelete === s.id) { S.confirmDelete = null; refreshSessions(); } }, 4000);
    });
  }
  actions.appendChild(del);

  el.appendChild(actions);
  return el;
}

/* ---------- инициализация ---------- */

function initSettings() {
  $('car').value = lsGet('pl.car', '');
  $('mount').value = lsGet('pl.mount', 'holder');
  S.threshold = Number(lsGet('pl.thr', '5')) || 5;
  S.sound = lsGet('pl.sound', '1') === '1';
  $('thr').value = String(S.threshold);
  $('thrVal').textContent = S.threshold.toFixed(1);
  $('sound').checked = S.sound;

  $('car').addEventListener('change', () => lsSet('pl.car', $('car').value.trim()));
  $('mount').addEventListener('change', () => lsSet('pl.mount', $('mount').value));
  $('thr').addEventListener('input', () => {
    S.threshold = Number($('thr').value);
    $('thrVal').textContent = S.threshold.toFixed(1);
    lsSet('pl.thr', String(S.threshold));
    drawGraph();
  });
  $('sound').addEventListener('change', () => {
    S.sound = $('sound').checked;
    lsSet('pl.sound', S.sound ? '1' : '0');
  });
}

async function init() {
  $('ver').textContent = 'v' + APP_VERSION;
  initSettings();

  if (!window.isSecureContext) {
    showBanner('Страница открыта без HTTPS — датчики и GPS не заработают. Откройте адрес, который начинается с https://', 'error');
  }

  await store.open();
  if (store.inMemory) {
    showBanner('Браузер не даёт сохранять данные (приватный режим?). Записи пропадут при закрытии страницы — не забудьте отправить файл.', 'warn');
  }

  $('startBtn').addEventListener('click', () => { if (S.recording) stop(); else start(); });
  document.querySelectorAll('.mk').forEach((b) => b.addEventListener('click', () => mark(b.dataset.label)));
  window.addEventListener('resize', drawGraph);

  await refreshSessions();
  renderAll();

  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost')) {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
}

init();
