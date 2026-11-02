/**
 * The page and its token. The token is the base64 of a JSON map from pod UID to the RFC3339
 * timestamp that pod resumes after. It is empty only when every pod has nothing left in the
 * window, so an empty page can carry one. A page is bounded in lines and in bytes: the
 * platform refuses a command's answer above about half a megabyte, and a page it refuses is
 * a page the console never gets, so the cut falls where the bytes run out as well.
 */

import { timestampKey, type LogEntry, type PodScan } from "./scan";

/** The most bytes of entries a page carries, as the JSON the answer serializes them to. */
export const MAX_PAGE_BYTES = 320 * 1024;

/** An entry's share of the page's JSON, its separator included. */
const bytesOf = (entry: LogEntry): number => Buffer.byteLength(JSON.stringify(entry)) + 1;

/** The oldest entries that fit the page: at most `limit`, within `MAX_PAGE_BYTES`, and always the first, so a line bigger than a page never stalls the cursor. */
export function fit(sorted: LogEntry[], limit: number): LogEntry[] {
  let bytes = 0;
  let count = 0;
  for (const entry of sorted) {
    bytes += bytesOf(entry);
    if (count === limit || (count > 0 && bytes > MAX_PAGE_BYTES)) {
      break;
    }
    count++;
  }
  return sorted.slice(0, count);
}

export type Cursors = Record<string, string>;

/** The cursors a token carries; an unreadable token is no cursors at all. */
export function decodeToken(token: string | undefined): Cursors {
  if (!token) {
    return {};
  }
  try {
    const parsed: unknown = JSON.parse(Buffer.from(token, "base64").toString("utf8"));
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {};
    }
    return Object.fromEntries(Object.entries(parsed).filter(([, value]) => typeof value === "string")) as Cursors;
  } catch {
    return {};
  }
}

export function encodeToken(cursors: Cursors): string {
  return Object.keys(cursors).length === 0 ? "" : Buffer.from(JSON.stringify(cursors)).toString("base64");
}

export interface Page {
  results: LogEntry[];
  next_page_token: string;
}

/**
 * Merges the pods' scans, orders their entries, cuts them to what a page holds, and builds
 * the token that resumes after what this page covered. A pod whose entries the cut dropped
 * resumes after its newest kept entry; any other pod resumes after the last line it read,
 * matched or not, so a filter that rejects a whole read still moves the search forward.
 */
export function page(scans: PodScan[], limit: number, previous: Cursors): Page {
  const all = scans.flatMap((scan) => scan.entries);
  const sorted = all.map((entry, index) => ({ entry, index, key: timestampKey(entry.datetime) })).sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : a.index - b.index)).map(({ entry }) => entry);
  const entries = fit(sorted, limit);

  const keptPerPod = new Map<string, number>();
  const newestKept = new Map<string, string>();
  for (const entry of entries) {
    keptPerPod.set(entry.pod.id, (keptPerPod.get(entry.pod.id) ?? 0) + 1);
    newestKept.set(entry.pod.id, entry.datetime);
  }

  const cursors: Cursors = { ...previous };
  let more = false;
  for (const scan of scans) {
    if ((keptPerPod.get(scan.podId) ?? 0) < scan.entries.length) {
      more = true;
      const newest = newestKept.get(scan.podId);
      if (newest !== undefined) {
        cursors[scan.podId] = newest;
      }
      continue;
    }
    if (scan.scannedUpTo !== "") {
      cursors[scan.podId] = scan.scannedUpTo;
    }
    if (!scan.done) {
      more = true;
    }
  }
  return { results: entries, next_page_token: more ? encodeToken(cursors) : "" };
}
