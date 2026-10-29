// board.js — renders the consumer's non-secret status. SSE with polling fallback.
const $ = (id) => document.getElementById(id)
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
let lastVersion = null
let flashTimer = null

function text(el, value) { el.textContent = value ?? '—' }
function ago(iso) {
  if (!iso) return null
  const s = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 1000))
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s ago`
  return `${Math.floor(s / 3600)}h ago`
}
function time(iso) { return iso ? new Date(iso).toLocaleTimeString() : '—' }
function secs(v) { return v === null || v === undefined ? '—' : `${Number(v).toFixed(2)} s` }

function setDoor(state, verdict, versionText) {
  const door = document.querySelector('.door')
  door.dataset.state = state
  text($('door-state'), verdict)
  text($('door-version'), versionText)
}

function draw(s) {
  const c = s.consumer ?? {}
  const d = s.door ?? {}
  const credState = c.state ?? 'no-data'
  text($('door-secret'), s.secret)
  text($('door-fp'), c.fingerprint)

  // The hero: the door's last verdict, with the consumer's credential state.
  let heroState = 'unknown', heroText = 'No credential yet'
  if (credState === 'stale') { heroState = 'stale'; heroText = 'STALE' }
  else if (d.last_verdict === 'GRANTED') { heroState = 'granted'; heroText = 'ACCESS GRANTED' }
  else if (d.last_verdict === 'DENIED') { heroState = 'denied'; heroText = 'ACCESS DENIED' }
  else if (d.last_verdict === 'UNAVAILABLE') { heroState = 'unknown'; heroText = 'Door unavailable' }

  // On a new version, show the stale → fresh sequence for a moment (text only with reduced motion).
  const rot = (s.rotations ?? [])[0]
  if (c.version && lastVersion !== null && c.version !== lastVersion && rot && rot.to === c.version) {
    clearTimeout(flashTimer)
    setDoor('denied', `ACCESS DENIED · v${rot.from} is stale`, `v${rot.from}`)
    flashTimer = setTimeout(() => { flashTimer = null; setDoor(heroState, heroText, c.version ? `v${c.version}` : '—') }, reduceMotion ? 1200 : 1800)
  } else if (!flashTimer) {
    setDoor(heroState, heroText, c.version ? `v${c.version}` : '—')
  }
  lastVersion = c.version ?? lastVersion
  text($('door-status'), `credential ${credState}${c.reason ? ` — ${c.reason}` : ''} · ${d.meaning ?? 'no door check yet'}`)

  // Health: three signals, each with its own evidence.
  text($('sig-credential'), c.version ? `v${c.version} loaded ${ago(c.loaded_at)} (${time(c.loaded_at)}) · state ${credState}` : 'no credential yet')
  const ag = s.agent ?? {}
  const refresh = ag.last_refresh ?? {}
  text($('sig-refresh'), refresh.observable
    ? `${ago(refresh.at) ?? '—'} (${refresh.source})`
    : `not observable — last change rendered ${ago(ag.last_change_rendered_at) ?? 'never'} (unchanged secrets are not re-written)`)
  if (ag.last_fetch_error) $('sig-refresh').textContent += ` · fetch error ${ago(ag.last_fetch_error.at)}`
  const v = s.vault ?? {}
  const vaultText = v.probe === 'reachable' ? `reachable · ${v.detail} · ${ago(v.at)}`
    : v.probe === 'unknown' ? 'unknown — no probe result yet'
      : `${v.probe} since ${time(v.since)} (${v.detail})`
  text($('sig-vault'), vaultText)
  for (const [id, good] of [['sig-credential', credState === 'current'], ['sig-vault', v.probe === 'reachable'],
    ['sig-refresh', refresh.observable && !ag.last_fetch_error]]) {
    $(id).dataset.tone = good ? 'good' : (id === 'sig-vault' && v.probe !== 'unknown') || credState === 'stale' ? 'bad' : 'neutral'
  }

  // Latency: measured vs configured.
  const lat = s.latency ?? {}
  const rows = [
    ['Vault created → Agent wrote file', `render interval ${ag.render_interval_s ?? '—'} s`, lat.vault_to_file_s],
    ['Agent wrote file → consumer reloaded', `poll ${c.poll_interval_s ?? '—'} s`, lat.file_to_reload_s],
  ]
  $('latency-rows').replaceChildren(...rows.map(([stage, conf, m]) => {
    const tr = document.createElement('tr')
    for (const cell of [stage, conf, m?.n ? secs(m.p50) : 'not measured yet', m?.n ? secs(m.max) : '—', String(m?.n ?? 0)]) {
      const td = document.createElement('td'); td.textContent = cell; tr.append(td)
    }
    return tr
  }))

  // Timeline.
  const rots = s.rotations ?? []
  $('timeline-empty').hidden = rots.length > 0
  $('timeline').replaceChildren(...rots.map((r) => {
    const li = document.createElement('li')
    const head = document.createElement('p')
    head.className = 'rot-head'
    const strong = document.createElement('strong'); strong.textContent = `v${r.from} → v${r.to}`
    head.append(strong)
    if (r.missed) { const chip = document.createElement('span'); chip.className = 'vg-pill vg-pill--pending'; chip.textContent = `missed ${r.missed}`; head.append(' ', chip) }
    if (r.while_stopped) { const chip = document.createElement('span'); chip.className = 'vg-pill vg-pill--manual'; chip.textContent = 'while stopped'; head.append(' ', chip) }
    const verdicts = document.createElement('span'); verdicts.className = 'verdicts'
    if (r.stale_denied !== null && r.stale_denied !== undefined) {
      const a = document.createElement('span'); a.className = `vg-pill ${r.stale_denied ? 'vg-pill--rejected' : 'vg-pill--pending'}`; a.textContent = `v${r.from} ${r.stale_denied ? 'denied' : 'not denied'}`
      const b = document.createElement('span'); b.className = `vg-pill ${r.fresh_granted ? 'vg-pill--healthy' : 'vg-pill--pending'}`; b.textContent = `v${r.to} ${r.fresh_granted ? 'granted' : 'not granted'}`
      verdicts.append(a, ' ', b)
    }
    head.append(' ', verdicts)
    const times = document.createElement('p'); times.className = 'rot-times'
    times.textContent = `Vault created ${time(r.vault_created_at)} · file written ${time(r.file_seen_at)} · reloaded ${time(r.reloaded_at)}`
      + (r.vault_to_file_s !== null && r.vault_to_file_s !== undefined ? ` · Vault→file ${secs(r.vault_to_file_s)}` : '')
      + (r.file_to_reload_s !== null && r.file_to_reload_s !== undefined ? ` · file→reload ${secs(r.file_to_reload_s)}` : '')
    li.append(head, times)
    return li
  }))

  // Log.
  const log = $('log')
  const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 8
  log.replaceChildren(...(s.log ?? []).map((l) => {
    const div = document.createElement('div'); div.className = `line lvl-${(l.level || '').toLowerCase()}`
    div.textContent = `${l.at} ${String(l.level).padEnd(5)} [${l.source}] ${l.msg}`
    return div
  }))
  if (atBottom) log.scrollTop = log.scrollHeight
}

function setConn(state) {
  const el = $('conn'); el.dataset.state = state
  el.textContent = state === 'live' ? 'live' : state === 'polling' ? 'polling every 2 s' : 'connection lost — retrying'
}

async function poll() {
  try {
    const res = await fetch('/api/state', { cache: 'no-store' })
    if (res.ok) { render(await res.json()); setConn('polling') } else setConn('lost')
  } catch { setConn('lost') }
}

function connect() {
  if (!('EventSource' in window)) { setInterval(poll, 2000); poll(); return }
  const es = new EventSource('/api/events')
  let fallback = null
  es.addEventListener('state', (e) => { setConn('live'); clearInterval(fallback); fallback = null; render(JSON.parse(e.data)) })
  es.onerror = () => { setConn('lost'); if (!fallback) fallback = setInterval(poll, 2000) }
}

let last = null
function render(s) { last = s; draw(s) }
setInterval(() => { if (last) draw(last) }, 5000)   // keep relative times ("12s ago") honest
connect()
