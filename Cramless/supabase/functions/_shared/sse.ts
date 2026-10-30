// Server-sent events for the tutor: each event is `event: <name>`, one `data: <JSON>` line and a blank line; a
// `: ping` comment goes out after 10 seconds of silence so proxies keep the connection open. The events are the
// normalized ones in the contract: start {model}, delta {text}, citation {sourceId, label, quote}, done {model},
// error {code, message}.

export type TutorEventName = "start" | "delta" | "citation" | "done" | "error";

/** Every event the relay streams: the tutor's, the assistant's tool events and web research's search events. */
export type EventName = TutorEventName | "tool_start" | "tool_item" | "tool_text" | "tool_call" | "search";

export interface TutorEventData {
  text?: string;
  model?: string;
  sourceId?: string;
  label?: string;
  quote?: string;
  code?: string;
  message?: string;
}

/** One event, exactly as the app's parser reads it. */
export function formatEvent(event: string, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

export const PING = ": ping\n\n";

/** A writable event stream wrapped in a Response. Writes after the client left are dropped; `onCancel` handlers
 * run when it leaves, so upstream work can stop. */
export class EventStream {
  readonly response: Response;
  #controller: ReadableStreamDefaultController<Uint8Array> | null = null;
  #encoder = new TextEncoder();
  #closed = false;
  #timer: ReturnType<typeof setTimeout> | undefined;
  #cancelHandlers: (() => void)[] = [];
  readonly #pingIntervalMs: number;

  constructor(pingIntervalMs = 10_000) {
    this.#pingIntervalMs = pingIntervalMs;
    const stream = new ReadableStream<Uint8Array>({
      start: (controller) => {
        this.#controller = controller;
      },
      cancel: () => {
        this.#closed = true;
        this.#clearTimer();
        for (const handler of this.#cancelHandlers) handler();
      },
    });
    this.response = new Response(stream, {
      status: 200,
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Accel-Buffering": "no",
      },
    });
    this.#arm();
  }

  get closed(): boolean {
    return this.#closed;
  }

  onCancel(handler: () => void): void {
    this.#cancelHandlers.push(handler);
  }

  send(event: EventName, data: object): void {
    this.#write(formatEvent(event, data));
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.#clearTimer();
    try {
      this.#controller?.close();
    } catch {
      // already closed by the client
    }
  }

  #write(text: string): void {
    if (this.#closed) return;
    try {
      this.#controller?.enqueue(this.#encoder.encode(text));
    } catch {
      this.#closed = true;
      this.#clearTimer();
      return;
    }
    this.#arm();
  }

  #arm(): void {
    this.#clearTimer();
    if (this.#closed) return;
    this.#timer = setTimeout(() => this.#write(PING), this.#pingIntervalMs);
  }

  #clearTimer(): void {
    if (this.#timer !== undefined) clearTimeout(this.#timer);
    this.#timer = undefined;
  }
}

export interface SseMessage {
  event: string | null;
  data: string;
}

/** Parses an SSE byte stream (comments skipped, multi-line data joined). Used by the tests and the mock server. */
export async function* parseSse(body: ReadableStream<Uint8Array>): AsyncGenerator<SseMessage> {
  const reader = body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  let event: string | null = null;
  let data: string[] = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += value;
      let newline: number;
      while ((newline = buffer.search(/\r\n|\n|\r/)) >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + (buffer.startsWith("\r\n", newline) ? 2 : 1));
        if (line === "") {
          if (data.length > 0) yield { event, data: data.join("\n") };
          event = null;
          data = [];
          continue;
        }
        if (line.startsWith(":")) continue;
        const colon = line.indexOf(":");
        const field = colon >= 0 ? line.slice(0, colon) : line;
        let val = colon >= 0 ? line.slice(colon + 1) : "";
        if (val.startsWith(" ")) val = val.slice(1);
        if (field === "event") event = val;
        else if (field === "data") data.push(val);
      }
    }
    if (data.length > 0) yield { event, data: data.join("\n") };
  } finally {
    reader.releaseLock();
  }
}
