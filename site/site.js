(() => {
'use strict'
const $ = (s, r = document) => r.querySelector(s)
const $$ = (s, r = document) => [...r.querySelectorAll(s)]
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches
const fine = matchMedia('(pointer:fine)').matches
const clamp = (v, a, b) => Math.min(b, Math.max(a, v))
const AMBER = '#ffb020', RED = '#ff5d5d'

/* ---------- заголовок по словам ---------- */
function splitWords(el) {
  let i = 0
  const walk = (node) => {
    [...node.childNodes].forEach((n) => {
      if (n.nodeType === 3) {
        const frag = document.createDocumentFragment()
        n.textContent.split(/(\s+)/).forEach((t) => {
          if (!t) return
          if (/^\s+$/.test(t)) { frag.append(' '); return }
          const w = document.createElement('span'); w.className = 'w'
          const s = document.createElement('span'); s.textContent = t
          s.style.transitionDelay = (i++ * 0.09) + 's'
          w.append(s); frag.append(w)
        })
        n.replaceWith(frag)
      } else if (n.nodeType === 1 && n.tagName !== 'BR') walk(n)
    })
  }
  walk(el)
  requestAnimationFrame(() => setTimeout(() => el.classList.add('in'), 120))
}
$$('[data-split]').forEach(splitWords)

/* ---------- появление при прокрутке ---------- */
const io = new IntersectionObserver((es) => es.forEach((e) => {
  if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target) }
}), { threshold: 0.15, rootMargin: '0px 0px -6% 0px' })
$$('.reveal').forEach((el) => io.observe(el))

/* ---------- прогресс, меню, подсветка ссылок ---------- */
const progress = $('#progress'), nav = $('#nav')
const secs = $$('main section[id]'), links = $$('.links a')
let lastY = 0
function onScroll() {
  const y = scrollY, max = document.documentElement.scrollHeight - innerHeight
  progress.style.transform = `scaleX(${max > 0 ? y / max : 0})`
  nav.classList.toggle('hide', y > lastY && y > 400)
  lastY = y
  const mid = y + innerHeight * 0.4
  let cur = ''
  secs.forEach((s) => { if (s.offsetTop <= mid) cur = '#' + s.id })
  links.forEach((a) => a.classList.toggle('on', a.getAttribute('href') === cur))
}
addEventListener('scroll', onScroll, { passive: true }); onScroll()

/* ---------- свет за курсором, подсветка карточек, магнит, наклон ---------- */
const glow = $('#glow')
if (fine) {
  addEventListener('pointermove', (e) => { glow.style.left = e.clientX + 'px'; glow.style.top = e.clientY + 'px' }, { passive: true })
  $$('.spot').forEach((c) => c.addEventListener('pointermove', (e) => {
    const r = c.getBoundingClientRect()
    c.style.setProperty('--mx', e.clientX - r.left + 'px'); c.style.setProperty('--my', e.clientY - r.top + 'px')
  }))
  $$('.magnetic').forEach((b) => {
    b.addEventListener('pointermove', (e) => {
      const r = b.getBoundingClientRect()
      b.style.transform = `translate(${(e.clientX - r.left - r.width / 2) * 0.22}px,${(e.clientY - r.top - r.height / 2) * 0.3}px)`
    })
    b.addEventListener('pointerleave', () => { b.style.transform = '' })
  })
  const ph = $('#phone')
  const host = ph.parentElement
  host.addEventListener('pointermove', (e) => {
    const r = host.getBoundingClientRect()
    const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5
    ph.style.transform = `perspective(900px) rotateY(${x * 18}deg) rotateX(${-y * 14}deg)`
  })
  host.addEventListener('pointerleave', () => { ph.style.transform = '' })
}

/* ---------- живые данные ---------- */
const live = {}
const fmt = (v, d = 0) => Number(v).toLocaleString('ru-RU', { minimumFractionDigits: d, maximumFractionDigits: d })
function countUp(el) {
  const key = el.dataset.live, dec = +el.dataset.dec || 0
  const to = key && live[key] != null ? +live[key] : parseFloat(el.textContent.replace(',', '.')) || 0
  if (reduce) { el.textContent = fmt(to, dec); return }
  const t0 = performance.now(), dur = 1800
  const tick = (t) => {
    const p = clamp((t - t0) / dur, 0, 1), e = 1 - Math.pow(1 - p, 4)
    el.textContent = fmt(to * e, dec)
    if (p < 1) requestAnimationFrame(tick)
  }
  requestAnimationFrame(tick)
}
const counted = new WeakSet()
const cio = new IntersectionObserver((es) => es.forEach((e) => {
  if (e.isIntersecting && !counted.has(e.target)) { counted.add(e.target); countUp(e.target) }
}), { threshold: 0.4 })
function watchCounts() { $$('[data-count]').forEach((el) => { counted.delete(el); cio.unobserve(el); cio.observe(el) }) }

const api = (p) => fetch('/api/v1/' + p).then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
const shortDistrict = (n) => n.replace(/ский район$/, '').replace(/ район$/, '')

async function loadLive() {
  const [w, d, s] = await Promise.allSettled([api('reports/weekly'), api('rankings/districts'), api('rankings/streets')])
  if (w.status === 'fulfilled') Object.assign(live, w.value)
  watchCounts()
  if (d.status === 'fulfilled') {
    const ds = d.value.districts.slice().sort((a, b) => b.score - a.score)
    $('#cityScore').textContent = 'Город: ' + fmt(d.value.city_score, 1) + ' из 100'
    $('#districts').innerHTML = ds.map((x) => {
      const c = x.score >= 85 ? '#3ecf8e' : x.score >= 70 ? '#ffd24d' : x.score >= 55 ? '#ff9a3c' : '#ff5d5d'
      return `<div class="bar"><span title="${esc(x.name)}">${esc(shortDistrict(x.name))}</span><div class="tr"><i style="--c:${c}" data-w="${x.score}"></i></div><b>${fmt(x.score, 0)}</b></div>`
    }).join('')
    const bio = new IntersectionObserver((es) => es.forEach((e) => {
      if (e.isIntersecting) { $$('.tr i', e.target).forEach((i) => { i.style.width = i.dataset.w + '%' }); bio.disconnect() }
    }), { threshold: 0.3 })
    bio.observe($('#districts'))
  } else $('#districts').innerHTML = '<p class="sub">Данные временно недоступны.</p>'
  if (s.status === 'fulfilled') {
    $('#streets').innerHTML = s.value.streets.slice(0, 5).map((x) =>
      `<li><div>${esc(x.name)}<small>${fmt(x.covered_km, 1)} км проверено · ${x.potholes} ям</small></div><strong>${fmt(x.per_km, 1)}</strong></li>`).join('')
  } else $('#streets').innerHTML = '<li><div>Данные временно недоступны</div></li>'
}
watchCounts()
loadLive()
const chain = $('.chain')
new IntersectionObserver((es, o) => es.forEach((e) => { if (e.isIntersecting) { $('#chainFill').style.width = '100%'; o.disconnect() } }), { threshold: 0.5 }).observe(chain)
new IntersectionObserver((es, o) => es.forEach((e) => { if (e.isIntersecting) { $('#railFill').style.width = '72%'; o.disconnect() } }), { threshold: 0.3 }).observe($('#rail'))

/* ---------- ГЕРОЙ: дорога в перспективе ---------- */
const cv = $('#road'), cx = cv.getContext('2d')
let W = 0, H = 0, DPR = 1, mouseX = 0, mouseY = 0, heroVisible = true
function size() {
  DPR = Math.min(devicePixelRatio || 1, 2)
  W = cv.clientWidth; H = cv.clientHeight
  cv.width = W * DPR; cv.height = H * DPR
}
size(); addEventListener('resize', size)
addEventListener('pointermove', (e) => { mouseX = e.clientX / innerWidth - 0.5; mouseY = e.clientY / innerHeight - 0.5 }, { passive: true })
new IntersectionObserver((es) => { heroVisible = es[0].isIntersecting }).observe($('.hero'))

const holes = [], trace = new Array(150).fill(0), stars = Array.from({ length: 70 }, () => ({ x: Math.random(), y: Math.random() * 0.36, r: Math.random() * 1.3 + 0.2, p: Math.random() * 6 }))
let dist = 0, lastT = performance.now(), nextSpawn = 0, shake = 0, impact = 0, hits = 0
const speed = 26 // м/с
function spawn() {
  holes.push({ d: 330, lat: (Math.random() - 0.5) * 4.4, w: 0.55 + Math.random() * 0.5, hit: false })
}
for (let i = 0; i < 4; i++) holes.push({ d: 70 + i * 85, lat: (Math.random() - 0.5) * 4.4, w: 0.7, hit: false })

function frame(t) {
  requestAnimationFrame(frame)
  if (!heroVisible) { lastT = t; return }
  const dt = Math.min((t - lastT) / 1000, 0.05); lastT = t
  const step = reduce ? 0 : speed * dt
  dist += step; nextSpawn -= step
  if (nextSpawn <= 0) { spawn(); nextSpawn = 110 + Math.random() * 90 }

  const f = H * 1.1, hz = H * 0.36 + mouseY * 14, vx = W * (W > 900 ? 0.7 : 0.5) + mouseX * 40, camH = 1.25
  shake *= 0.9; impact *= 0.93
  cx.setTransform(DPR, 0, 0, DPR, (Math.random() - 0.5) * shake * DPR, (Math.random() - 0.5) * shake * DPR)
  cx.clearRect(-20, -20, W + 40, H + 40)

  // небо: звёзды и зарево на горизонте
  const g = cx.createLinearGradient(0, 0, 0, hz)
  g.addColorStop(0, '#07090d'); g.addColorStop(1, '#1a1410')
  cx.fillStyle = g; cx.fillRect(0, 0, W, hz)
  stars.forEach((s) => { cx.globalAlpha = 0.35 + 0.35 * Math.sin(t / 700 + s.p); cx.fillStyle = '#fff'; cx.fillRect(s.x * W + mouseX * -10, s.y * H, s.r, s.r) })
  cx.globalAlpha = 1
  const hg = cx.createRadialGradient(vx, hz, 0, vx, hz, W * 0.5)
  hg.addColorStop(0, 'rgba(255,176,32,.35)'); hg.addColorStop(1, 'rgba(255,176,32,0)')
  cx.fillStyle = hg; cx.fillRect(0, 0, W, hz + 40)

  // земля и дорога
  cx.fillStyle = '#0a0c11'; cx.fillRect(0, hz, W, H - hz)
  const P = (lat, d) => [vx + (lat * f) / d, hz + (camH * f) / d]
  const dMin = 1.9, dMax = 400
  const a = P(-3.6, dMax), b = P(3.6, dMax), c = P(3.6, dMin), e = P(-3.6, dMin)
  const rg = cx.createLinearGradient(0, hz, 0, H)
  rg.addColorStop(0, '#14171f'); rg.addColorStop(1, '#1b1f2a')
  cx.fillStyle = rg; cx.beginPath(); cx.moveTo(...a); cx.lineTo(...b); cx.lineTo(...c); cx.lineTo(...e); cx.fill()
  // обочины
  cx.strokeStyle = 'rgba(255,255,255,.35)'; cx.lineWidth = 2
  ;[-3.5, 3.5].forEach((l) => { cx.beginPath(); cx.moveTo(...P(l, dMax)); cx.lineTo(...P(l, dMin)); cx.stroke() })
  // разметка (бегущая)
  const off = dist % 14
  cx.fillStyle = 'rgba(255,176,32,.9)'
  for (let d0 = -off; d0 < dMax; d0 += 14) {
    const d1 = Math.max(d0, dMin + 0.01), d2 = d0 + 6
    if (d2 < dMin) continue
    const w1 = 0.09, p1 = P(-w1, d1), p2 = P(w1, d1), p3 = P(w1, d2), p4 = P(-w1, d2)
    cx.globalAlpha = clamp(1.2 - d1 / 260, 0.1, 1)
    cx.beginPath(); cx.moveTo(...p1); cx.lineTo(...p2); cx.lineTo(...p3); cx.lineTo(...p4); cx.fill()
  }
  cx.globalAlpha = 1
  // фонари вдоль дороги
  const loff = dist % 40
  for (let d0 = 40 - loff; d0 < dMax; d0 += 40) {
    ;[-5.2, 5.2].forEach((l) => {
      const [px, py] = P(l, d0), [, py2] = P(l, d0), h = (5.5 * f) / d0
      cx.strokeStyle = 'rgba(255,255,255,.25)'; cx.lineWidth = Math.max(1, 6 / d0 * 3)
      cx.beginPath(); cx.moveTo(px, py2); cx.lineTo(px, py2 - h); cx.stroke()
      const lg = cx.createRadialGradient(px, py2 - h, 0, px, py2 - h, 90 / d0 * 8 + 6)
      lg.addColorStop(0, 'rgba(255,200,100,.9)'); lg.addColorStop(1, 'rgba(255,200,100,0)')
      cx.fillStyle = lg; cx.beginPath(); cx.arc(px, py2 - h, 90 / d0 * 8 + 6, 0, 7); cx.fill()
    })
  }

  // ямы
  let label = null
  holes.sort((p, q) => q.d - p.d)
  for (const h of holes) {
    h.d -= step
    if (!h.hit && h.d < 3.2) {
      h.hit = true; hits++
      shake = Math.max(shake, 7); impact = 1
    }
  }
  while (holes.length && holes[holes.length - 1].d < 1.6) holes.pop()
  for (const h of holes) {
    if (h.d > dMax) continue
    const [px, py] = P(h.lat, h.d), rw = (h.w * f) / h.d, rh = rw * 0.28
    const near = clamp(1 - h.d / 220, 0, 1)
    cx.save()
    cx.shadowColor = AMBER; cx.shadowBlur = 24 * near + 4
    cx.fillStyle = '#05060a'; cx.strokeStyle = 'rgba(255,176,32,' + (0.35 + near * 0.6) + ')'; cx.lineWidth = Math.max(1, rw * 0.06)
    cx.beginPath(); cx.ellipse(px, py, rw, rh, 0, 0, 7); cx.fill(); cx.stroke()
    cx.restore()
    if (h.d < 170 && h.d > 25 && (!label || h.d < label.d)) label = { d: h.d, px, py, rw }
  }
  if (label && W > 600) {
    const txt = `Яма через ${Math.round(label.d)} м`
    cx.font = '700 14px Inter,sans-serif'
    const tw = cx.measureText(txt).width + 34, x = clamp(label.px - tw / 2, 10, W - tw - 10), y = label.py - label.rw * 0.5 - 52
    cx.fillStyle = 'rgba(21,25,34,.9)'; cx.strokeStyle = RED; cx.lineWidth = 1.5
    cx.beginPath(); cx.roundRect(x, y, tw, 34, 17); cx.fill(); cx.stroke()
    cx.fillStyle = RED; cx.beginPath(); cx.arc(x + 17, y + 17, 4.5, 0, 7); cx.fill()
    cx.fillStyle = '#fff'; cx.fillText(txt, x + 29, y + 22)
    cx.strokeStyle = 'rgba(255,93,93,.6)'; cx.setLineDash([3, 4]); cx.beginPath(); cx.moveTo(label.px, y + 34); cx.lineTo(label.px, label.py - label.rw * 0.2); cx.stroke(); cx.setLineDash([])
  }

  // датчик внизу справа
  trace.shift(); trace.push((Math.random() - 0.5) * 0.12 + Math.sin(t / 90) * 0.04 + (impact > 0.2 ? (Math.random() - 0.5) * impact * 2.4 : 0))
  if (W > 700) {
    const bw = 300, bh = 70, bx = W - bw - 36, by = H - bh - 86
    cx.fillStyle = 'rgba(7,9,13,.72)'; cx.beginPath(); cx.roundRect(bx - 12, by - 28, bw + 24, bh + 44, 16); cx.fill()
    cx.strokeStyle = 'rgba(255,255,255,.08)'; cx.stroke()
    cx.fillStyle = '#8f99ab'; cx.font = '600 11px Inter,sans-serif'; cx.fillText('АКСЕЛЕРОМЕТР · ударов: ' + hits, bx, by - 8)
    cx.strokeStyle = impact > 0.3 ? RED : AMBER; cx.lineWidth = 2; cx.shadowColor = cx.strokeStyle; cx.shadowBlur = 8
    cx.beginPath(); trace.forEach((v, i) => { const x = bx + (i / (trace.length - 1)) * bw, y = by + bh / 2 - v * bh * 0.45; i ? cx.lineTo(x, y) : cx.moveTo(x, y) }); cx.stroke(); cx.shadowBlur = 0
  }
  if (impact > 0.5) { cx.fillStyle = `rgba(255,93,93,${(impact - 0.5) * 0.18})`; cx.fillRect(0, 0, W, H) }
}
requestAnimationFrame(frame)

/* ---------- как работает: шаги ↔ экраны телефона ---------- */
const steps = $$('.step'), screens = $$('.screen')
const sio = new IntersectionObserver((es) => es.forEach((e) => {
  if (e.isIntersecting) setStep(+e.target.dataset.step)
}), { rootMargin: '-42% 0px -42% 0px' })
steps.forEach((s) => sio.observe(s))
let curStep = -1, ringT = null
function setStep(n) {
  if (n === curStep) return
  curStep = n
  steps.forEach((s, i) => s.classList.toggle('active', i === n))
  screens.forEach((s, i) => s.classList.toggle('on', i === n))
  clearInterval(ringT)
  if (n === 2) {
    let m = 150; $('#ringM').textContent = m
    ringT = setInterval(() => { m = m <= 8 ? 150 : m - 6; $('#ringM').textContent = m; $('#ringFg').style.strokeDashoffset = 327 * (m / 150) }, 90)
  }
}
setStep(0)
// волна на экране «записи»
const wp = $('#wavePath')
function wave(t) {
  requestAnimationFrame(wave)
  if (curStep !== 0) return
  let d = ''
  for (let x = 0; x <= 300; x += 4) {
    const spike = Math.exp(-Math.pow(((x / 300 + t / 3600) % 1) - 0.55, 2) * 900) * 46
    const y = 60 + Math.sin(x / 9 + t / 160) * 5 + Math.sin(x / 3.1 + t / 70) * 2.5 - spike
    d += (x ? 'L' : 'M') + x + ' ' + y.toFixed(1)
  }
  wp.setAttribute('d', d)
}
requestAnimationFrame(wave)
// пины на картах
function pins(host, list) {
  host.innerHTML = list.map(([x, y, c]) => `<i class="pin ${c || ''}" style="left:${x}%;top:${y}%;animation-delay:${(Math.random() * 2).toFixed(2)}s"></i>`).join('')
}
pins($('#mapbox'), [[22, 30], [60, 22, 'o'], [45, 58], [75, 70, 'o'], [30, 80, 'g'], [84, 40], [12, 55, 'g'], [55, 85]])
pins($('#miniMap'), [[10, 40], [24, 70, 'o'], [38, 30], [52, 60], [66, 25, 'g'], [78, 68], [90, 38, 'o']])

/* ---------- лаборатория: удар от скорости ---------- */
const sc = $('#scope'), sx = sc.getContext('2d'), spd = $('#spd')
let SW = 0, SH = 0, speedKmh = 40, phase = 0
function sizeScope() { const d = Math.min(devicePixelRatio || 1, 2); SW = sc.clientWidth; SH = sc.clientHeight; sc.width = SW * d; sc.height = SH * d; sx.setTransform(d, 0, 0, d, 0, 0) }
sizeScope(); addEventListener('resize', sizeScope)
const peakOf = (v) => 0.6 * Math.pow(v / 40, 0.8) * 6.5 // м/с², как в модели score = peak/(v/40)^0.8
function advice(p) {
  if (p < 2.5) return ['Слабый', 'Можно ехать как есть']
  if (p < 5) return ['Заметный', 'Снизьте до 40 км/ч']
  if (p < 8) return ['Сильный', 'Снизьте до 30 км/ч']
  return ['Опасный', 'Снизьте до 20 км/ч']
}
function upd() {
  speedKmh = +spd.value; $('#spdV').textContent = speedKmh
  const p = peakOf(speedKmh), a = advice(p)
  $('#labPeak').textContent = fmt(p, 1) + ' м/с² · ' + a[0]
  $('#labAdvice').textContent = a[1]
  $('#labPeak').style.color = p < 2.5 ? '#3ecf8e' : p < 5 ? '#ffd24d' : p < 8 ? '#ff9a3c' : '#ff5d5d'
}
spd.addEventListener('input', upd); upd()
let scopeVisible = false
new IntersectionObserver((es) => { scopeVisible = es[0].isIntersecting }).observe(sc)
function scope(t) {
  requestAnimationFrame(scope)
  if (!scopeVisible) return
  phase = (t / 1000) * (0.35 + speedKmh / 100)
  sx.clearRect(0, 0, SW, SH)
  sx.strokeStyle = 'rgba(255,255,255,.06)'; sx.lineWidth = 1
  for (let i = 1; i < 8; i++) { sx.beginPath(); sx.moveTo(0, SH * i / 8); sx.lineTo(SW, SH * i / 8); sx.stroke() }
  const mid = SH / 2, peak = peakOf(speedKmh), k = (SH * 0.42) / 12
  sx.strokeStyle = '#ffb020'; sx.lineWidth = 2.4; sx.shadowColor = '#ffb020'; sx.shadowBlur = 12
  sx.beginPath()
  for (let x = 0; x <= SW; x += 3) {
    const u = (x / SW + phase * 0.25) % 1
    const hit = Math.exp(-Math.pow((u - 0.5) * 22, 2)) * Math.sin((u - 0.5) * 120) * peak
    const hit2 = Math.exp(-Math.pow((u - 0.56) * 24, 2)) * Math.sin((u - 0.56) * 130) * peak * 0.6
    const noise = Math.sin(x / 7 + t / 90) * 0.35 + Math.sin(x / 2.3 + t / 40) * 0.18
    const y = mid - (hit + hit2 + noise) * k
    x ? sx.lineTo(x, y) : sx.moveTo(x, y)
  }
  sx.stroke(); sx.shadowBlur = 0
  // порог
  sx.setLineDash([6, 6]); sx.strokeStyle = 'rgba(255,93,93,.7)'; sx.lineWidth = 1.2
  const ty = mid - 2.5 * k; sx.beginPath(); sx.moveTo(0, ty); sx.lineTo(SW, ty); sx.stroke(); sx.setLineDash([])
  sx.fillStyle = 'rgba(255,93,93,.9)'; sx.font = '600 11px Inter,sans-serif'; sx.fillText('порог события', SW - 90, ty - 6)
}
requestAnimationFrame(scope)

/* ---------- Холи: диалог ---------- */
const script = [
  ['ho', 'Холи слушает'],
  ['me', 'Холи, яма!'],
  ['ho', 'Отметила яму. Спасибо, записала.'],
  ['ho', 'Яма через 150 метров, снизьте до 30.'],
  ['ho', 'Только что была яма? Скажите: да или нет.'],
  ['me', 'Да'],
  ['ho', 'Подтверждено. Хорошей дороги!'],
]
const dlg = $('#dialog'), core = $('.orb-core')
let di = 0, dlgOn = false
function say() {
  if (!dlgOn) return
  if (di >= script.length) { setTimeout(() => { dlg.innerHTML = ''; di = 0; say() }, 3200); return }
  const [who, text] = script[di++]
  const m = document.createElement('div'); m.className = 'msg ' + who; m.textContent = text
  dlg.append(m)
  core.style.transform = 'scale(' + (who === 'ho' ? 1.18 : 0.94) + ')'
  setTimeout(() => { core.style.transform = '' }, 500)
  if (dlg.children.length > 5) dlg.firstChild.remove()
  setTimeout(say, 1700 + text.length * 22)
}
new IntersectionObserver((es) => { const on = es[0].isIntersecting; if (on && !dlgOn) { dlgOn = true; say() } else if (!on) dlgOn = false }, { threshold: 0.35 }).observe($('#holi'))
})()
