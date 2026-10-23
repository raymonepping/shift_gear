export function rotationValue(current: Record<string, unknown>, secret: string, id: string, username: string, now: string) {
  return { ...current, session_secret: secret, rotation_id: id, rotated_at: now, rotated_by: username }
}

export function validOperationId(id: unknown): id is string {
  return typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
}
