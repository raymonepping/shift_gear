// Bounded metadata retention. No raw Vault record or authentication object enters disk.
import { mkdir, readdir, readFile, open, unlink, lstat } from 'node:fs/promises'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'

const NAME = /^segment-(\d{13})-(\d{8})-[a-f0-9-]{36}\.ndjson$/
const clean = (value, max = 2048) => typeof value === 'string' ? value.replace(/[\r\n\t]/g, ' ').slice(0, max) : null
export function retainedRow(row, now = Date.now()) {
  return { schemaVersion: '1', id: clean(row.id, 96), retainedAt: new Date(now).toISOString(),
    time: clean(row.time, 64), type: clean(row.type, 32), operation: clean(row.operation, 32),
    namespace: clean(row.namespace, 256), path: clean(row.path), hasError: !!row.error }
}
function valid(row) {
  return row?.schemaVersion === '1' && typeof row.id === 'string' && typeof row.retainedAt === 'string'
    && Number.isFinite(Date.parse(row.retainedAt)) && typeof row.hasError === 'boolean'
}
export class MetadataArchive {
  constructor(directory, { maxBytes = 64 * 1024 * 1024, retentionMs = 7 * 86400000,
    segmentBytes = 256 * 1024, queueBytes = 1024 * 1024, clock = Date.now } = {}) {
    if (!Number.isSafeInteger(maxBytes) || maxBytes < 4096 || !Number.isSafeInteger(retentionMs) || retentionMs <= 0
      || !Number.isSafeInteger(segmentBytes) || segmentBytes < 1024 || segmentBytes > maxBytes) throw new Error('invalid archive bounds')
    Object.assign(this, { directory, maxBytes, retentionMs, segmentBytes, queueBytes, clock })
    this.ordinal = 0; this.queue = []; this.queuedBytes = 0; this.files = []; this.active = null; this.worker = null; this.closed = false
    this.info = { enabled: !!directory, available: false, committed: 0, failed: 0, queueDropped: 0, corrupt: 0,
      pruned: 0, bytes: 0, retained: 0, oldestAt: null, lastCommittedAt: null,
      maxBytes, retentionSeconds: retentionMs / 1000 }
  }
  async init() {
    if (!this.directory) return
    try {
      await mkdir(this.directory, { recursive: true, mode: 0o700 })
      if (!(await lstat(this.directory)).isDirectory() || (await lstat(this.directory)).isSymbolicLink()) throw new Error('archive directory refused')
      this.files = []
      for (const name of (await readdir(this.directory)).filter(name => NAME.test(name)).sort()) {
        this.ordinal = Math.max(this.ordinal, Number(NAME.exec(name)[2]))
        const path = join(this.directory, name); const stat = await lstat(path)
        if (!stat.isFile() || stat.isSymbolicLink() || stat.size > this.segmentBytes + 4096) throw new Error('archive file refused')
        const rows = (await readFile(path, 'utf8')).split('\n').filter(Boolean)
        let count = 0
        for (const line of rows) { try { if (!valid(JSON.parse(line))) throw new Error(); count++ } catch { this.info.corrupt++ } }
        this.files.push({ name, at: Number(NAME.exec(name)[1]), bytes: stat.size, count })
      }
      await this.prune()
      this.info.available = true
    } catch { this.info.available = false; this.info.failed++ }
  }
  status() { return { ...this.info, queued: this.queue.length } }
  refreshSize() {
    this.info.bytes = this.files.reduce((n, file) => n + file.bytes, 0)
    this.info.retained = this.files.reduce((n, file) => n + file.count, 0)
    this.info.oldestAt = this.files.length ? new Date(this.files[0].at).toISOString() : null
  }
  async prune(reserve = 0) {
    this.refreshSize()
    while (this.files.length && (this.clock() - this.files[0].at >= this.retentionMs || this.info.bytes + reserve > this.maxBytes)) {
      const file = this.files[0]
      if (this.active?.name === file.name) { await this.active.handle.close(); this.active = null }
      await unlink(join(this.directory, file.name))
      this.files.shift(); this.info.pruned += file.count; this.refreshSize()
    }
  }
  append(row) {
    if (!this.directory || this.closed) return false
    const line = JSON.stringify(retainedRow(row, this.clock())) + '\n'; const bytes = Buffer.byteLength(line)
    if (bytes > Math.min(4096, this.segmentBytes) || this.queuedBytes + bytes > this.queueBytes || this.queue.length >= 1024) { this.info.queueDropped++; return false }
    this.queue.push({ line, bytes }); this.queuedBytes += bytes
    if (!this.worker) this.worker = this.pump().finally(() => { this.worker = null })
    return true
  }
  async pump() {
    while (this.queue.length) {
      const batch = []; let bytes = 0
      while (this.queue.length && batch.length < 16 && bytes + this.queue[0].bytes <= this.segmentBytes) {
        const row = this.queue.shift(); batch.push(row); bytes += row.bytes
      }
      this.queuedBytes -= bytes
      try {
        if (!this.info.available) { await this.init(); if (!this.info.available) throw new Error('archive unavailable') }
        await this.prune(bytes)
        if (!this.active || this.active.bytes + bytes > this.segmentBytes) {
          if (this.active) await this.active.handle.close()
          const name = `segment-${this.clock()}-${String(++this.ordinal).padStart(8, '0')}-${randomUUID()}.ndjson`
          const handle = await open(join(this.directory, name), 'wx', 0o600)
          const file = { name, at: this.clock(), bytes: 0, count: 0 }
          this.files.push(file); this.active = { ...file, handle, file }
        }
        await this.active.handle.writeFile(batch.map(row => row.line).join(''))
        await this.active.handle.sync()
        this.active.bytes += bytes; this.active.file.bytes += bytes; this.active.file.count += batch.length
        this.info.committed += batch.length; this.info.lastCommittedAt = new Date(this.clock()).toISOString()
        this.info.available = true; this.refreshSize()
      } catch {
        this.info.available = false; this.info.failed += batch.length
        if (this.active) { await this.active.handle.close().catch(() => {}); this.active = null }
      }
    }
  }
  async newest(limit = 200) {
    await this.worker
    const rows = []
    for (const file of [...this.files].reverse().filter(file => this.clock() - file.at < this.retentionMs)) {
      const committedBytes = file.bytes
      const stat = await lstat(join(this.directory, file.name))
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > this.segmentBytes + 4096) throw new Error('archive file refused')
      const lines = (await readFile(join(this.directory, file.name))).subarray(0, committedBytes).toString('utf8').split('\n').filter(Boolean).reverse()
      for (const line of lines) {
        try { const row = JSON.parse(line); if (valid(row)) rows.push(retainedRowFromDisk(row)) } catch { /* partial/corrupt records are not observations */ }
        if (rows.length >= limit) return rows.slice(0, limit)
      }
    }
    return rows
  }
  maintain() {
    if (this.worker || this.closed || !this.directory) return
    this.worker = this.prune().catch(() => { this.info.available = false; this.info.failed++ }).finally(() => {
      this.worker = null
      if (this.queue.length) this.worker = this.pump().finally(() => { this.worker = null })
    })
  }
  async close() { this.closed = true; await this.worker; if (this.active) { await this.active.handle.sync(); await this.active.handle.close(); this.active = null } }
}
// Fixed projection also applies when reading retained data after a restart.
function retainedRowFromDisk(row) {
  return { ...retainedRow({ ...row, error: row.hasError }, Date.parse(row.retainedAt)) }
}
