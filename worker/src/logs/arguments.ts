/**
 * What log:read is asked, as the telemetry API sends it: the ids that select the pods, the
 * page (its limit and token), the filter and the window. The window's bounds arrive as
 * epoch milliseconds and keep that precision: the Kubernetes API resumes a read at a
 * second, so the reader applies the bounds itself, line by line (scan.ts). The page is
 * sized by the window: a long range pages in big steps whatever limit the caller sends.
 */

import { ActionError } from "@nullplatform/plugin";

export const DEFAULT_LIMIT = 500;
export const LOG_CONTAINER = "application";

/** The lines a page holds for a window of up to so many minutes: the console's own tiers. */
export const PAGE_BY_WINDOW: ReadonlyArray<{ upToMinutes: number; lines: number }> = [
  { upToMinutes: 15, lines: 100 },
  { upToMinutes: 60, lines: 200 },
  { upToMinutes: 360, lines: 400 },
  { upToMinutes: 1440, lines: 700 },
  { upToMinutes: Infinity, lines: 1000 },
];

/**
 * The page a request gets: the caller's limit, or the window's tier when that is bigger.
 * The window runs from the start to the end or to now, whichever is first, so a live
 * tail's poll (a start a moment ago) takes the smallest tier, not the day's, and a day's
 * range pages by 700 however small a limit the caller sends. No start is no window: the
 * limit as given.
 */
export function pageSizeOf(limit: number, startMs: number | undefined, endMs: number | undefined, now: number): number {
  if (startMs === undefined) {
    return limit;
  }
  const minutes = (Math.min(endMs ?? now, now) - startMs) / 60_000;
  const tier = PAGE_BY_WINDOW.find((candidate) => minutes <= candidate.upToMinutes) ?? PAGE_BY_WINDOW[PAGE_BY_WINDOW.length - 1];
  return Math.max(limit, tier.lines);
}

export interface LogReadArguments {
  applicationId: string;
  scopeId: string;
  deploymentId: string;
  /** The pods `instance_id` names, comma-separated; none selects the scope's pods by label. */
  instanceIds: string[];
  /** The lines a page holds: the limit sent, or the window's tier when that is bigger (`pageSizeOf`). */
  limit: number;
  nextPageToken: string;
  filterPattern: string;
  /** The window, epoch milliseconds, both bounds inclusive; undefined when open. */
  startMs?: number;
  endMs?: number;
}

type Raw = Record<string, unknown>;

/** The first element of an array argument, else the value as text; null and undefined are "". */
export function text(value: unknown): string {
  const one = Array.isArray(value) ? value[0] : value;
  return one === null || one === undefined ? "" : String(one);
}

/** Epoch milliseconds as the platform sends them; anything else is refused. */
export function epochMs(value: string): number {
  if (!/^\d+$/.test(value)) {
    throw new ActionError("INVALID_TIME", `timestamp '${value}' is not epoch milliseconds`);
  }
  return Number(value);
}

export function logReadArguments(raw: Raw | undefined, now = Date.now()): LogReadArguments {
  const args = raw ?? {};
  const applicationId = text(args.application_id);
  if (applicationId === "") {
    throw new ActionError("MISSING_APPLICATION_ID", "Missing required parameters: APPLICATION_ID");
  }
  const limitText = text(args.limit);
  const limit = limitText === "" ? DEFAULT_LIMIT : Number(limitText);
  if (!Number.isInteger(limit) || limit <= 0) {
    throw new ActionError("INVALID_LIMIT", `limit '${limitText}' is not a positive integer`);
  }
  const start = text(args.start_time);
  const end = text(args.end_time);
  const startMs = start === "" ? undefined : epochMs(start);
  const endMs = end === "" ? undefined : epochMs(end);
  return {
    applicationId,
    scopeId: text(args.scope_id),
    deploymentId: text(args.deployment_id) || text(args.deploy_id),
    instanceIds: text(args.instance_id).split(",").map((name) => name.trim()).filter(Boolean),
    limit: pageSizeOf(limit, startMs, endMs, now),
    nextPageToken: text(args.next_page_token),
    filterPattern: text(args.filter_pattern),
    startMs,
    endMs,
  };
}

/** The label selector every nullplatform pod carries, narrowed by the ids given. */
export function labelSelector(ids: { applicationId?: string; scopeId?: string; deploymentId?: string }): string {
  const parts = ["nullplatform=true"];
  if (ids.applicationId) {
    parts.push(`application_id=${ids.applicationId}`);
  }
  if (ids.scopeId) {
    parts.push(`scope_id=${ids.scopeId}`);
  }
  if (ids.deploymentId) {
    parts.push(`deployment_id=${ids.deploymentId}`);
  }
  return parts.join(",");
}
