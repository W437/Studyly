// Reading a tool call's arguments while the model is still writing them. A function call arrives as JSON text in small
// pieces; the assistant's cards and questions are the elements of one array in it, and a note's body is one long string.
// These two readers hand each finished element, or the string so far, to the stream as soon as it exists, so the app can
// show work that is really happening (a card appears when it has been written, not after the whole call).
//
// Both are tolerant: text that does not look as expected yields nothing, and the call's complete arguments (read once
// the model has finished) are what the app acts on. They never throw.

/** The finished elements of one array property of a JSON object, as its text arrives. The elements are objects. */
export class ArrayItemStream {
  readonly #key: RegExp;
  #buffer = "";
  #at = 0;
  #state: "seek" | "between" | "object" | "closed" | "off" = "seek";
  #depth = 0;
  #inString = false;
  #escaped = false;
  #start = 0;

  constructor(key: string) {
    this.#key = new RegExp(`"${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"\\s*:\\s*\\[`);
  }

  /** The elements that this chunk completed, in order. */
  push(chunk: string): unknown[] {
    this.#buffer += chunk;
    const out: unknown[] = [];
    if (this.#state === "seek") {
      const found = this.#key.exec(this.#buffer);
      if (!found) {
        if (this.#buffer.length > 4000) this.#state = "off";
        return out;
      }
      this.#at = found.index + found[0].length;
      this.#state = "between";
    }
    const s = this.#buffer;
    while (this.#at < s.length && this.#state !== "closed" && this.#state !== "off") {
      const ch = s[this.#at];
      if (this.#state === "between") {
        if (ch === "{") {
          this.#state = "object";
          this.#depth = 1;
          this.#inString = false;
          this.#escaped = false;
          this.#start = this.#at;
        } else if (ch === "]") {
          this.#state = "closed";
        } else if (ch !== "," && ch !== " " && ch !== "\n" && ch !== "\r" && ch !== "\t") {
          this.#state = "off"; // an array of something else
        }
        this.#at++;
        continue;
      }
      // Inside an element.
      if (this.#inString) {
        if (this.#escaped) this.#escaped = false;
        else if (ch === "\\") this.#escaped = true;
        else if (ch === '"') this.#inString = false;
      } else if (ch === '"') {
        this.#inString = true;
      } else if (ch === "{" || ch === "[") {
        this.#depth++;
      } else if (ch === "}" || ch === "]") {
        this.#depth--;
        if (this.#depth === 0) {
          try {
            out.push(JSON.parse(s.slice(this.#start, this.#at + 1)));
          } catch {
            this.#state = "off";
            return out;
          }
          this.#state = "between";
        }
      }
      this.#at++;
    }
    // Text before the current position is spent; keep only what an element in progress still needs.
    if (this.#state === "between" || this.#state === "closed") {
      this.#buffer = s.slice(this.#at);
      this.#at = 0;
    } else if (this.#state === "object") {
      this.#buffer = s.slice(this.#start);
      this.#at -= this.#start;
      this.#start = 0;
    }
    return out;
  }
}

const SIMPLE_ESCAPES: Record<string, string> = {
  '"': '"',
  "\\": "\\",
  "/": "/",
  b: "\b",
  f: "\f",
  n: "\n",
  r: "\r",
  t: "\t",
};

/** The decoded text of one string property of a JSON object, as it arrives. With `first` the property must open the
 * object (the tutor's `answer`); otherwise it is looked for anywhere (a note's `body`, after its other fields). An escape
 * (or half of a surrogate pair) split across two chunks waits for its other half. */
export class StringFieldStream {
  readonly #head: RegExp;
  readonly #first: boolean;
  #buffer = "";
  #at = 0;
  #state: "seek" | "text" | "closed" | "off" = "seek";

  constructor(key: string, first = false) {
    const quoted = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    this.#first = first;
    this.#head = first ? new RegExp(`^\\s*\\{\\s*"${quoted}"\\s*:\\s*"`) : new RegExp(`"${quoted}"\\s*:\\s*"`);
  }

  push(chunk: string): string {
    this.#buffer += chunk;
    if (this.#state === "seek") {
      const head = this.#head.exec(this.#buffer);
      if (head) {
        this.#at = head.index + head[0].length;
        this.#state = "text";
      } else {
        if (this.#buffer.length >= (this.#first ? 40 : 4000)) this.#state = "off";
        return "";
      }
    }
    if (this.#state !== "text") return "";
    const s = this.#buffer;
    let out = "";
    while (this.#at < s.length) {
      const ch = s[this.#at];
      if (ch === '"') {
        this.#state = "closed";
        this.#at++;
        break;
      }
      if (ch !== "\\") {
        const unit = ch.charCodeAt(0);
        if (unit >= 0xd800 && unit <= 0xdbff && this.#at + 1 >= s.length) break;
        out += ch;
        this.#at++;
        continue;
      }
      const next = s[this.#at + 1];
      if (next === undefined) break;
      if (next !== "u") {
        const plain = SIMPLE_ESCAPES[next];
        if (plain === undefined) {
          this.#state = "off";
          break;
        }
        out += plain;
        this.#at += 2;
        continue;
      }
      if (this.#at + 6 > s.length) break;
      const code = parseInt(s.slice(this.#at + 2, this.#at + 6), 16);
      if (Number.isNaN(code)) {
        this.#state = "off";
        break;
      }
      if (code >= 0xd800 && code <= 0xdbff) {
        if (this.#at + 12 > s.length) break;
        const pair = /^\\u([dD][c-fC-F][0-9a-fA-F]{2})$/.exec(s.slice(this.#at + 6, this.#at + 12));
        if (pair) {
          out += String.fromCharCode(code, parseInt(pair[1], 16));
          this.#at += 12;
        } else {
          out += "�";
          this.#at += 6;
        }
        continue;
      }
      out += String.fromCharCode(code);
      this.#at += 6;
    }
    return out;
  }
}
