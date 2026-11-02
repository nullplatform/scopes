/**
 * log:read: the pods the arguments select, read concurrently and merged into one page with
 * one token. The Kubernetes API bounds a read in bytes and resumes it at a second, so each
 * pod is read with a byte budget from its cursor's second (or the window's), and the cursor
 * and the window are applied line by line (scan.ts). A page is as full as the window
 * allows: a pod cut by its budget while the page is short is read again with more room, so
 * one chatty pod among quiet ones still fills it.
 */

import type { KubeClient } from "../kube/client";
import type { Pod } from "../kube/types";
import { ActionError } from "@nullplatform/plugin";
import { LOG_CONTAINER, labelSelector, logReadArguments, type LogReadArguments } from "./arguments";
import { decodeToken, page, type Cursors, type Page } from "./page";
import { forwardLines, processLines, type PodScan } from "./scan";

/** A line's room in a read: the budget is the page's lines at this size. */
const BYTES_PER_LINE = 3072;
const MIN_READ_BYTES = 64 * 1024;
const MAX_READ_BYTES = 4 * 1024 * 1024;
/** How many times a pod cut by its budget is read again, with four times the room each, while the page is short. */
const FILL_ROUNDS = 2;
/** How many times a read that made no progress (a second that logged more than the budget) is repeated with twice the room. */
const MAX_READ_DOUBLINGS = 6;

export interface LogsPorts {
  kube: KubeClient;
  /** The namespace the scope's pods live in; undefined reads every namespace by label. */
  namespace: string | undefined;
  /** How many pods are read at once. */
  concurrency?: number;
}

/** Runs `work` over `items`, at most `limit` at a time, keeping the order. */
export async function mapConcurrently<Item, Result>(items: Item[], limit: number, work: (item: Item) => Promise<Result>): Promise<Result[]> {
  const results = new Array<Result>(items.length);
  let next = 0;
  const lanes = Array.from({ length: Math.min(limit, items.length) }, async () => {
    for (let index = next++; index < items.length; index = next++) {
      results[index] = await work(items[index]);
    }
  });
  await Promise.all(lanes);
  return results;
}

/** A pod's first budget: its share of the page in bytes, within bounds. */
const budgetOf = (limit: number, pods: number): number => Math.min(MAX_READ_BYTES, Math.max(MIN_READ_BYTES, Math.ceil(limit / pods) * BYTES_PER_LINE));

/** One pod's read: from its cursor's second, or the window's, with `budget` bytes of room. */
async function scanPod(ports: LogsPorts, pod: Pod, budget: number, cursor: string, args: LogReadArguments, signal?: AbortSignal): Promise<PodScan> {
  const sinceTime = cursor || (args.startMs === undefined ? undefined : new Date(args.startMs).toISOString());
  const options = { podName: pod.metadata.name, podId: pod.metadata.uid, filterPattern: args.filterPattern, cursor, from: cursor ? undefined : args.startMs, until: args.endMs };
  let limitBytes = budget;
  for (let doublings = 0; ; doublings++) {
    const text = await ports.kube.readLog(pod, { container: LOG_CONTAINER, sinceTime, limitBytes, signal });
    const { lines, truncated } = forwardLines(text, limitBytes);
    const scan = processLines(lines, options);
    // Ended by the window, or by the log's end before the byte limit: the pod has nothing left.
    scan.done ||= !truncated;
    if (scan.scannedUpTo !== "" || scan.done || doublings === MAX_READ_DOUBLINGS) {
      return scan;
    }
    limitBytes *= 2;
  }
}

interface PodRead {
  pod: Pod;
  budget: number;
  scan: PodScan;
}

const entriesOf = (reads: PodRead[]): number => reads.reduce((count, read) => count + read.scan.entries.length, 0);

/** Every pod read once, then the ones cut by their budget read again with more room while the page is still short. */
async function scanPods(ports: LogsPorts, pods: Pod[], cursors: Cursors, args: LogReadArguments, signal?: AbortSignal): Promise<PodScan[]> {
  const concurrency = ports.concurrency ?? 16;
  const read = async (pod: Pod, budget: number): Promise<PodRead> => ({ pod, budget, scan: await scanPod(ports, pod, budget, cursors[pod.metadata.uid] ?? "", args, signal) });
  let reads = await mapConcurrently(pods, concurrency, (pod) => read(pod, budgetOf(args.limit, pods.length)));
  for (let round = 0; round < FILL_ROUNDS && entriesOf(reads) < args.limit; round++) {
    const cut = reads.filter((candidate) => !candidate.scan.done && candidate.budget < MAX_READ_BYTES);
    if (cut.length === 0) {
      break;
    }
    const again = await mapConcurrently(cut, concurrency, (candidate) => read(candidate.pod, Math.min(candidate.budget * 4, MAX_READ_BYTES)));
    reads = reads.map((candidate) => again.find((wider) => wider.pod === candidate.pod) ?? candidate);
  }
  return reads.map((candidate) => candidate.scan);
}

/** The pods `instance_id` names, each of which must be there, else the scope's by label. */
async function selectPods(ports: LogsPorts, args: LogReadArguments, signal?: AbortSignal): Promise<Pod[]> {
  if (args.instanceIds.length === 0) {
    return ports.kube.listPods(ports.namespace, labelSelector(args), signal);
  }
  const found = await Promise.all(args.instanceIds.map((name) => ports.kube.getPod(ports.namespace, name, signal)));
  const missing = args.instanceIds.filter((name, index) => found[index] === null);
  if (missing.length > 0) {
    throw new ActionError("POD_NOT_FOUND", `pod ${missing.join(", ")} not found${ports.namespace ? ` in namespace ${ports.namespace}` : ""}`);
  }
  return found as Pod[];
}

export async function readLogs(ports: LogsPorts, raw: Record<string, unknown> | undefined, signal?: AbortSignal): Promise<Page> {
  const args = logReadArguments(raw);
  const pods = await selectPods(ports, args, signal);
  if (pods.length === 0) {
    return { results: [], next_page_token: "" };
  }
  const cursors = decodeToken(args.nextPageToken);
  const scans = await scanPods(ports, pods, cursors, args, signal);
  return page(scans, args.limit, cursors);
}
