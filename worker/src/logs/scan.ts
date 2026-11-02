/**
 * One pod's read, line by line. The Kubernetes log API takes only a lower bound at second
 * precision (sinceTime) and a byte limit, so the cursor, the window and the filter are
 * applied here, and a read cut at the byte limit holds back its partial last line for the
 * next page.
 */

export interface LogEntry {
  message: string;
  datetime: string;
  pod: { name: string; id: string };
}

/** What one request read from one pod: what matched, how far it got, whether it is done. */
export interface PodScan {
  podId: string;
  entries: LogEntry[];
  /** The newest line read inside the window, kept by the filter or not; "" when none passed the cursor. */
  scannedUpTo: string;
  /** The read reached the end of the window or of the pod's log, not the byte limit. */
  done: boolean;
}

const RFC3339 = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/;

/** Whether `value` is an RFC3339 timestamp, with or without fractional seconds. */
export function validTimestamp(value: string): boolean {
  return RFC3339.test(value) && !Number.isNaN(Date.parse(value));
}

/**
 * A key that orders timestamps correctly as strings. The kubelet trims trailing zeros of
 * the fraction, so "…:00.5Z" and "…:00.123456789Z" compare wrongly as raw strings; here
 * the fraction is padded to nine digits and an offset is folded into UTC.
 */
export function timestampKey(value: string): string {
  const match = RFC3339.exec(value);
  if (!match) {
    return value;
  }
  const [, base, fraction = ".", zone] = match;
  const nanos = (fraction.slice(1) + "000000000").slice(0, 9);
  if (zone === "Z") {
    return `${base}.${nanos}Z`;
  }
  // An offset: the second-precision part moves to UTC, the nanos ride along unchanged.
  const utc = new Date(`${base}${zone}`).toISOString().slice(0, 19);
  return `${utc}.${nanos}Z`;
}

/** Whether `a` is at or before `b`, by timestamp. */
export const notAfter = (a: string, b: string): boolean => timestampKey(a) <= timestampKey(b);

/** The millisecond a timestamp falls in, as epoch milliseconds: its first three fraction digits, in UTC. */
export const millisecondOf = (value: string): number => Date.parse(`${timestampKey(value).slice(0, 23)}Z`);

export interface ScanOptions {
  podName: string;
  podId: string;
  /** Whitespace-separated terms; every term must appear in the whole line, case-sensitive. */
  filterPattern?: string;
  /** The cursor: lines at or before it are already delivered. */
  cursor?: string;
  /** The window, epoch milliseconds, both inclusive: a line before `from` is skipped, the first line past `until` ends the read. */
  from?: number;
  until?: number;
}

/**
 * The lines of a log read, as the Kubernetes API returned it cut at `limitBytes`. A last
 * line without its line break is held back when the read was cut, so the next page reads it
 * whole; it is sent anyway when it is all the read got, since a line longer than the limit
 * would otherwise stop the cursor for good. Returns the lines and whether the read was cut.
 */
export function forwardLines(text: string, limitBytes: number): { lines: string[]; truncated: boolean } {
  const truncated = Buffer.byteLength(text) >= limitBytes;
  if (text === "") {
    return { lines: [], truncated };
  }
  const pieces = text.split("\n");
  const last = pieces.pop() ?? "";
  const lines = pieces.map((line) => line.replace(/\r$/, ""));
  if (last !== "" && (!truncated || lines.length === 0)) {
    lines.push(last.replace(/\r$/, ""));
  }
  return { lines, truncated };
}

/** Applies the cursor, the window and the filter to one pod's lines. */
export function processLines(lines: Iterable<string>, options: ScanOptions): PodScan {
  const scan: PodScan = { podId: options.podId, entries: [], scannedUpTo: "", done: false };
  const terms = options.filterPattern ? options.filterPattern.split(/\s+/).filter(Boolean) : [];

  for (const line of lines) {
    const space = line.indexOf(" ");
    if (space < 0) {
      continue;
    }
    const timestamp = line.slice(0, space);
    const message = line.slice(space + 1);
    if (!validTimestamp(timestamp)) {
      continue;
    }
    if (options.cursor && notAfter(timestamp, options.cursor)) {
      continue;
    }
    const millisecond = millisecondOf(timestamp);
    if (options.from !== undefined && millisecond < options.from) {
      continue;
    }
    // The stream is chronological, so the first line past the window ends it.
    if (options.until !== undefined && millisecond > options.until) {
      scan.done = true;
      break;
    }
    scan.scannedUpTo = timestamp;
    if (terms.length > 0 && !terms.every((term) => line.includes(term))) {
      continue;
    }
    scan.entries.push({ message, datetime: timestamp, pod: { name: options.podName, id: options.podId } });
  }
  return scan;
}
