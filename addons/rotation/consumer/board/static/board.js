// board.js — renders both parties' non-secret status. SSE with polling fallback.
const $ = (id) => document.getElementById(id)
const el = (tag, cls, txt) => { const e = document.createElement(tag); if (cls) e.className = cls; if (txt !== undefined) e.textContent = txt; return e }

function text(node, value) { node.textContent = value ?? '—' }
function ago(iso) {
  if (!iso) return null
  const s = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 1000))
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s ago`
  return `${Math.floor(s / 3600)}h ago`
}
function time(iso) { return iso ? new Date(iso).toLocaleTimeString() : '—' }
function secs(v) { return v === null || v === undefined ? '—' : `${Number(v).toFixed(2)} s` }
function pill(tone, label) { return el('span', `vg-pill vg-pill--${tone}`, label) }

// One party's health signals: credential, refresh evidence, reachability.
function drawHealth(prefix, st, body) {
  const credState = body.state ?? 'no-data'
  const version = body.version ?? body.current_version
  text($(`${prefix}-credential`), version ? `v${version} · state ${credState}${body.reason ? ` (${body.reason})` : ''}` : 'no credential yet')
  const ag = st.agent ?? {}
  const refresh = ag.last_refresh ?? {}
  text($(`${prefix}-refresh`), refresh.observable
    ? `${ago(refresh.at) ?? '—'} (${refresh.source})`
    : `not observable; last change rendered ${ago(ag.last_change_rendered_at) ?? 'never'}`)
  if (ag.last_fetch_error) $(`${prefix}-refresh`).textContent += ` · fetch error ${ago(ag.last_fetch_error.at)}`
  const v = st.vault ?? {}
  text($(`${prefix}-vault`), v.probe === 'reachable' ? `reachable · ${v.detail} · ${ago(v.at)}`
    : v.probe === 'unknown' || !v.probe ? 'unknown, no probe result yet' : `${v.probe} since ${time(v.since)} (${v.detail})`)
  for (const [id, good, bad] of [[`${prefix}-credential`, credState === 'current', credState === 'stale' || credState === 'error'],
    [`${prefix}-vault`, v.probe === 'reachable', v.probe && v.probe !== 'unknown' && v.probe !== 'reachable'],
    [`${prefix}-refresh`, refresh.observable && !ag.last_fetch_error, !!ag.last_fetch_error]]) {
    $(id).dataset.tone = good ? 'good' : bad ? 'bad' : 'neutral'
  }
}

function drawAnswering(prefix, p) {
  const node = $(`${prefix}-answering`)
  node.className = `vg-pill vg-pill--${p?.answering ? 'healthy' : 'rejected'}`
  node.textContent = p?.answering ? 'answering' : `not answering${p?.error ? ` (${p.error})` : ''}`
}

function draw(s) {
  const P = s.parties ?? {}
  const vst = P.verifier?.status ?? {}
  const cst = P.client?.status ?? {}
  const V = vst.verifier ?? {}
  const C = cst.client ?? {}
  text($('door-secret'), s.secret)
  text($('door-client-version'), C.version ? `v${C.version}` : null)
  text($('door-verifier-version'), V.current_version ? `v${V.current_version}` : null)
  text($('door-mode'), V.mode ? (V.mode === 'strict' ? 'strict' : `grace ${V.grace_seconds} s`) : null)

  // The hero: the verifier's answer to the client's last request.
  const last = C.last
  const door = document.querySelector('.door')
  let state = 'unknown', verdict = 'No request yet'
  if (!P.client?.answering && !P.verifier?.answering) { verdict = 'Parties not answering' }
  else if (C.state === 'stale') { state = 'stale'; verdict = 'STALE' }
  else if (last?.verdict === 'GRANTED') { state = 'granted'; verdict = 'ACCESS GRANTED' }
  else if (last?.verdict === 'DENIED') { state = 'denied'; verdict = 'ACCESS DENIED' }
  else if (last?.verdict === 'UNREACHABLE') { verdict = 'Verifier unreachable' }
  door.dataset.state = state
  text($('door-state'), verdict)
  text($('door-status'), last
    ? `last request ${ago(last.at)}: v${last.version} ${last.verdict.toLowerCase()} (${last.reason})${last.fallback ? ', previous key used while the verifier caught up' : ''}`
    : 'the client has not knocked yet')

  // Lanes.
  drawAnswering('verifier', P.verifier)
  drawAnswering('client', P.client)
  drawHealth('verifier', vst, V)
  drawHealth('client', cst, C)
  const ring = V.ring ?? []
  $('verifier-ring').replaceChildren(...(ring.length ? ring.map((k) => {
    const li = el('li')
    li.append(el('strong', 'mono', `v${k.version}`), ' ',
      k.current ? pill('healthy', 'current') : pill('pending', `accepted until ${time(k.retires_at)}`))
    return li
  }) : [el('li', 'dim', 'empty: no version adopted yet')]))
  const o = C.outcomes ?? {}
  const parts = [['GRANTED', 'granted'], ['DENIED', 'denied'], ['UNREACHABLE', 'unreachable'], ['fallback', 'fallbacks']]
    .filter(([k]) => o[k]).map(([k, label]) => `${o[k]} ${label}`)
  text($('client-outcomes'), parts.length
    ? `${parts.join(' · ')}${C.holds_previous ? ` · still holds v${C.holds_previous} for a fallback` : ''}`
    : 'no request yet')

  // Denial windows (open one first).
  const wins = [...(C.open_window ? [{ ...C.open_window, open: true }] : []), ...(C.windows ?? [])]
  $('windows-empty').hidden = wins.length > 0
  $('window-rows').replaceChildren(...wins.map((w) => {
    const tr = el('tr')
    for (const cell of [time(w.start), w.reason, `v${w.version}`, String(w.denied), w.open ? 'still open' : secs(w.seconds)]) tr.append(el('td', null, cell))
    return tr
  }))

  // Verifier decisions.
  const counts = Object.entries(V.verdicts ?? {}).sort((a, b) => b[1] - a[1])
  $('verdict-counts').replaceChildren(...(counts.length ? counts.flatMap(([k, n]) => {
    const [verdict, reason] = k.split(':')
    return [pill(verdict === 'GRANTED' ? (reason === 'grace' ? 'approved' : 'healthy') : 'rejected', `${verdict.toLowerCase()} · ${reason} · ${n}`), ' ']
  }) : [el('span', 'dim', 'no decision yet')]))

  const refused = (V.recent ?? []).find((r) => r.verdict === 'DENIED')
  text($('last-refusal'), refused
    ? `Last refused request: ${refused.version ? `v${refused.version}` : 'no version'} from ${refused.client ?? 'an unknown sender'}, ${refused.reason}, ${time(refused.at)} (${ago(refused.at)}).`
    : 'No request refused in the last 60 decisions.')

  // Latency: client delivery and verifier adoption, measured vs configured.
  const lat = C.latency ?? {}
  const adopt = (V.adoptions ?? []).filter((a) => a.previous !== null && a.vault_to_adopt_s !== null).map((a) => a.vault_to_adopt_s)
  const stat = (xs) => xs.length ? { p50: [...xs].sort((a, b) => a - b)[Math.floor((xs.length - 1) / 2)], max: Math.max(...xs), n: xs.length } : { n: 0 }
  const rows = [
    ['Vault created → client Agent wrote file', `render interval ${cst.agent?.render_interval_s ?? '—'} s`, lat.vault_to_file_s],
    ['Client file written → client reloaded', `poll ${C.poll_interval_s ?? '—'} s`, lat.file_to_reload_s],
    ['Vault created → verifier adopted', `render interval ${vst.agent?.render_interval_s ?? '—'} s`, stat(adopt)],
  ]
  $('latency-rows').replaceChildren(...rows.map(([stage, conf, m]) => {
    const tr = el('tr')
    for (const cell of [stage, conf, m?.n ? secs(m.p50) : 'not measured yet', m?.n ? secs(m.max) : '—', String(m?.n ?? 0)]) tr.append(el('td', null, cell))
    return tr
  }))

  // Timeline: client rotations joined with the verifier's adoption of the same version.
  const adoptedAt = Object.fromEntries((V.adoptions ?? []).map((a) => [a.version, a]))
  const rots = C.rotations ?? []
  $('timeline-empty').hidden = rots.length > 0
  $('timeline').replaceChildren(...rots.map((r) => {
    const li = el('li')
    const head = el('p', 'rot-head')
    head.append(el('strong', null, `v${r.from} → v${r.to}`))
    if (r.missed) head.append(' ', pill('pending', `missed ${r.missed}`))
    if (r.while_stopped) head.append(' ', pill('manual', 'while the client was stopped'))
    const a = adoptedAt[r.to]
    const times = el('p', 'rot-times',
      `Vault created ${time(r.vault_created_at)} · verifier adopted ${time(a?.adopted_at)} · client reloaded ${time(r.reloaded_at)}`
      + (a?.previous_retired_at ? ` · v${a.previous} retired ${time(a.previous_retired_at)}` : a?.previous_retires_at ? ` · v${a.previous} retires ${time(a.previous_retires_at)}` : ''))
    li.append(head, times)
    return li
  }))

  // Log: both parties, merged by time.
  const log = $('log')
  const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 8
  const lines = [...(vst.log ?? []), ...(cst.log ?? [])].sort((x, y) => (x.at < y.at ? -1 : x.at > y.at ? 1 : 0)).slice(-200)
  log.replaceChildren(...lines.map((l) => el('div', `line lvl-${(l.level || '').toLowerCase()}`, `${l.at} ${String(l.level).padEnd(5)} [${l.source}] ${l.msg}`)))
  if (atBottom) log.scrollTop = log.scrollHeight
}

function setConn(state) {
  const node = $('conn'); node.dataset.state = state
  node.textContent = state === 'live' ? 'live' : state === 'polling' ? 'polling every 2 s' : 'connection lost, retrying'
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
