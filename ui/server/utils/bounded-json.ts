import https from 'node:https'

/** Absolute deadline and byte limit, including slow streaming responses. No redirects. */
export function boundedJson(url: string, ca: Buffer, token?: string): Promise<{ status: number; json: unknown }> {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { ca, headers: token ? { Authorization: `Bearer ${token}` } : {} }, (res) => {
      const chunks: Buffer[] = []
      let size = 0
      res.on('data', (chunk: Buffer) => {
        size += chunk.length
        if (size > 65536) { req.destroy(new Error('response limit')); return }
        chunks.push(chunk)
      })
      res.on('error', reject)
      res.on('end', () => {
        try { resolve({ status: res.statusCode ?? 0, json: JSON.parse(Buffer.concat(chunks).toString()) }) }
        catch { resolve({ status: res.statusCode ?? 0, json: null }) }
      })
    })
    const deadline = setTimeout(() => req.destroy(new Error('deadline')), 3000)
    req.on('close', () => clearTimeout(deadline))
    req.on('error', reject)
  })
}
