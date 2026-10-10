// Ammachi cites journeys inline as [[journey:ID]]. This splitter strips the
// markers out of a streamed text and reports each cited ID, coping with
// markers that arrive split across chunks.

// The marker plus the whitespace in front of it, so `Clouds [[journey:x]], by`
// reads `Clouds, by` once the marker is gone.
const MARKER = /\s*\[{1,2}\s*journey\s*:\s*([A-Za-z0-9_-]+)\s*\]{1,2}/;

export class CitationSplitter {
  constructor() {
    this.buffer = '';
  }

  // Returns [{type:'text', text} | {type:'cite', id}] ready to emit.
  push(chunk) {
    this.buffer += chunk;
    return this.#drain(false);
  }

  flush() {
    return this.#drain(true);
  }

  #drain(final) {
    const out = [];
    for (;;) {
      const m = MARKER.exec(this.buffer);
      if (m) {
        const end = m.index + m[0].length;
        // "[[journey:x]" at the very end may still be waiting for its second "]".
        if (!final && end === this.buffer.length && m[0].trimStart().startsWith('[[') && !m[0].endsWith(']]')) {
          if (m.index > 0) out.push({ type: 'text', text: this.buffer.slice(0, m.index) });
          this.buffer = this.buffer.slice(m.index);
          return out;
        }
        if (m.index > 0) out.push({ type: 'text', text: this.buffer.slice(0, m.index) });
        out.push({ type: 'cite', id: m[1] });
        this.buffer = this.buffer.slice(end);
        continue;
      }
      if (final) {
        if (this.buffer) out.push({ type: 'text', text: this.buffer });
        this.buffer = '';
        return out;
      }
      // Hold back a trailing "[" or "[[..." that could still become a marker,
      // and any whitespace before it (a marker would swallow that too).
      let open = this.buffer.lastIndexOf('[');
      while (open > 0 && this.buffer[open - 1] === '[') open--;
      let safe = open >= 0 && this.buffer.length - open < 48 ? open : this.buffer.length;
      while (safe > 0 && /\s/.test(this.buffer[safe - 1])) safe--;
      if (safe > 0) out.push({ type: 'text', text: this.buffer.slice(0, safe) });
      this.buffer = this.buffer.slice(safe);
      return out;
    }
  }
}

// Splits spoken text into sentence-sized pieces for TTS as it streams in.
export class SentenceChunker {
  constructor(minLength = 24) {
    this.buffer = '';
    this.minLength = minLength;
  }

  push(text) {
    this.buffer += text;
    const out = [];
    const re = /[.!?।\n]+["'”’)]*\s+/g;
    let last = 0;
    let m;
    while ((m = re.exec(this.buffer))) {
      const end = m.index + m[0].length;
      if (end - last >= this.minLength) {
        out.push(this.buffer.slice(last, end).trim());
        last = end;
      }
    }
    this.buffer = this.buffer.slice(last);
    return out.filter(Boolean);
  }

  flush() {
    const rest = this.buffer.trim();
    this.buffer = '';
    return rest ? [rest] : [];
  }
}

export function speakable(text) {
  return text.replace(/[*_#`>]/g, '').replace(/\s+/g, ' ').trim();
}
