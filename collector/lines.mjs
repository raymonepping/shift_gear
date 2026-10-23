// Bound complete AND fragmented records before JSON parsing. Discard an
// oversize record through its next newline, never parse its trailing fragment.
export function lineDecoder(onLine, onOversize, maxBytes = 1024 * 1024) {
  let buffered = ''
  let discarding = false
  return (chunk) => {
    const parts = chunk.split('\n')
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i]
      if (!discarding) {
        if (Buffer.byteLength(buffered) + Buffer.byteLength(part) > maxBytes) {
          buffered = ''
          discarding = true
          onOversize()
        } else buffered += part
      }
      if (i < parts.length - 1) {
        if (!discarding && buffered.trim()) onLine(buffered)
        buffered = ''
        discarding = false
      }
    }
  }
}
