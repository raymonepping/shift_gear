// Fixed numeric series only: no paths, identities, payloads or user-selected labels.
export function metrics(stats, archive) {
  const values = {
    sg_audit_received_total: ['counter', stats.received], sg_audit_ring_dropped_total: ['counter', stats.dropped],
    sg_audit_malformed_total: ['counter', stats.malformed], sg_audit_connections: ['gauge', stats.connections],
    sg_audit_ring_entries: ['gauge', stats.stored], sg_audit_listener_up: ['gauge', Number(stats.listening)],
    sg_audit_archive_up: ['gauge', Number(archive.available)], sg_audit_archive_committed_total: ['counter', archive.committed],
    sg_audit_archive_failed_total: ['counter', archive.failed], sg_audit_archive_queue_dropped_total: ['counter', archive.queueDropped],
    sg_audit_archive_retained_entries: ['gauge', archive.retained], sg_audit_archive_bytes: ['gauge', archive.bytes],
    sg_audit_archive_pruned_total: ['counter', archive.pruned], sg_audit_archive_corrupt_total: ['counter', archive.corrupt],
  }
  return Object.entries(values).map(([name, [type, value]]) => `# TYPE ${name} ${type}\n${name} ${Number.isFinite(value) && value >= 0 ? value : 0}\n`).join('')
}
