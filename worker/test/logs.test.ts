import { describe, expect, test } from "bun:test";
import { inMemoryKube } from "../src/kube/in-memory";
import { epochMs, labelSelector, logReadArguments, pageSizeOf } from "../src/logs/arguments";
import { decodeToken, encodeToken, fit, MAX_PAGE_BYTES, page } from "../src/logs/page";
import { readLogs } from "../src/logs/read";
import { forwardLines, millisecondOf, processLines, timestampKey, validTimestamp } from "../src/logs/scan";
import { lines, pod, sampleLogs, samplePods } from "./sample";

const T0 = Date.parse("2026-10-20T12:00:00.000Z");
/** A kubelet line at `ms` with `nanos` more nanoseconds. */
const stamped = (ms: number, nanos: number, message: string): string => `${new Date(ms).toISOString().replace("Z", String(nanos).padStart(6, "0") + "Z")} ${message}`;

describe("timestamps", () => {
  test("RFC3339 with or without a fraction is valid, anything else is not", () => {
    expect(validTimestamp("2026-10-20T12:00:00Z")).toBe(true);
    expect(validTimestamp("2026-10-20T12:00:00.123456789Z")).toBe(true);
    expect(validTimestamp("2026-10-20T12:00:00+02:00")).toBe(true);
    expect(validTimestamp("12:00:00 something")).toBe(false);
    expect(validTimestamp("2026-13-45T12:00:00Z")).toBe(false);
  });

  test("the kubelet's trimmed fractions order correctly", () => {
    // As raw strings "…00.5Z" > "…00.123Z" is right but "…00Z" > "…00.1Z" is wrong; the key fixes both.
    expect(timestampKey("2026-10-20T12:00:00.5Z") > timestampKey("2026-10-20T12:00:00.123456789Z")).toBe(true);
    expect(timestampKey("2026-10-20T12:00:00Z") < timestampKey("2026-10-20T12:00:00.1Z")).toBe(true);
    expect(timestampKey("2026-10-20T14:00:00+02:00")).toBe("2026-10-20T12:00:00.000000000Z");
  });

  test("a timestamp's millisecond keeps the nanoseconds out and the offset in", () => {
    expect(millisecondOf("2026-10-20T12:00:00.123456789Z")).toBe(T0 + 123);
    expect(millisecondOf("2026-10-20T14:00:00.5+02:00")).toBe(T0 + 500);
  });
});

describe("forwardLines", () => {
  test("a read cut at the limit holds back its partial last line", () => {
    const { lines: out, truncated } = forwardLines("2026-10-20T12:00:00Z one\n2026-10-20T12:00:01Z tw", 44);
    expect(truncated).toBe(true);
    expect(out).toEqual(["2026-10-20T12:00:00Z one"]);
  });

  test("a partial last line is sent when it is all the read got", () => {
    const { lines: out, truncated } = forwardLines("2026-10-20T12:00:00Z a very long line cut", 20);
    expect(truncated).toBe(true);
    expect(out).toEqual(["2026-10-20T12:00:00Z a very long line cut"]);
  });

  test("a read under the limit keeps every line, with or without a final line break", () => {
    expect(forwardLines("2026-10-20T12:00:00Z one\n2026-10-20T12:00:01Z two", 10_000)).toEqual({ lines: ["2026-10-20T12:00:00Z one", "2026-10-20T12:00:01Z two"], truncated: false });
    expect(forwardLines("", 10)).toEqual({ lines: [], truncated: false });
  });
});

describe("processLines", () => {
  const base = { podName: "p", podId: "u" };
  const input = ["2026-10-20T12:00:00Z zero", "garbage without a stamp", "2026-10-20T12:00:01Z one error", "2026-10-20T12:00:02Z two", "2026-10-20T12:00:03Z three error"];

  test("drops lines at or before the cursor and stops at the first line past the window", () => {
    const scan = processLines(input, { ...base, cursor: "2026-10-20T12:00:00Z", until: T0 + 2000 });
    expect(scan.entries.map((entry) => entry.message)).toEqual(["one error", "two"]);
    expect(scan.scannedUpTo).toBe("2026-10-20T12:00:02Z");
    expect(scan.done).toBe(true);
  });

  test("the window's bounds are milliseconds, both inclusive, whatever the nanoseconds", () => {
    const burst = [stamped(T0 + 999, 999999, "before"), stamped(T0 + 1000, 0, "first"), stamped(T0 + 1000, 999999, "last"), stamped(T0 + 1001, 0, "after")];
    const scan = processLines(burst, { ...base, from: T0 + 1000, until: T0 + 1000 });
    expect(scan.entries.map((entry) => entry.message)).toEqual(["first", "last"]);
    expect(scan.done).toBe(true);
  });

  test("every filter term must appear, and rejected lines still move the scan forward", () => {
    const scan = processLines(input, { ...base, filterPattern: "error one" });
    expect(scan.entries.map((entry) => entry.message)).toEqual(["one error"]);
    expect(scan.scannedUpTo).toBe("2026-10-20T12:00:03Z");
    expect(scan.done).toBe(false);
  });
});

describe("page", () => {
  const entry = (podId: string, datetime: string) => ({ message: datetime, datetime, pod: { name: podId, id: podId } });

  test("the token round-trips and an unreadable one is no cursors", () => {
    expect(decodeToken(encodeToken({ a: "2026-10-20T12:00:00Z" }))).toEqual({ a: "2026-10-20T12:00:00Z" });
    expect(encodeToken({})).toBe("");
    expect(decodeToken("not base64 json")).toEqual({});
    expect(decodeToken(Buffer.from("[1,2]").toString("base64"))).toEqual({});
  });

  test("a cut pod resumes at its newest kept entry, a whole pod at what it scanned, and a done page has no token", () => {
    const a = { podId: "a", entries: [entry("a", "2026-10-20T12:00:00Z"), entry("a", "2026-10-20T12:00:02Z"), entry("a", "2026-10-20T12:00:04Z")], scannedUpTo: "2026-10-20T12:00:04Z", done: true };
    const b = { podId: "b", entries: [entry("b", "2026-10-20T12:00:01Z")], scannedUpTo: "2026-10-20T12:00:09Z", done: true };
    const first = page([a, b], 2, {});
    expect(first.results.map((e) => e.datetime)).toEqual(["2026-10-20T12:00:00Z", "2026-10-20T12:00:01Z"]);
    expect(decodeToken(first.next_page_token)).toEqual({ a: "2026-10-20T12:00:00Z", b: "2026-10-20T12:00:09Z" });
    const last = page([{ ...a, entries: a.entries.slice(1) }, { ...b, entries: [] }], 10, decodeToken(first.next_page_token));
    expect(last.results).toHaveLength(2);
    expect(last.next_page_token).toBe("");
  });

  test("a page stops where its bytes run out, and a line bigger than a page still goes alone", () => {
    const big = (index: number) => ({ message: "x".repeat(100 * 1024), datetime: `2026-10-20T12:00:0${index}Z`, pod: { name: "a", id: "a" } });
    const four = [big(0), big(1), big(2), big(3)];
    expect(fit(four, 10)).toHaveLength(3);
    expect(Buffer.byteLength(JSON.stringify(fit(four, 10)))).toBeLessThanOrEqual(MAX_PAGE_BYTES);
    const huge = { ...big(0), message: "y".repeat(MAX_PAGE_BYTES * 2) };
    expect(fit([huge, big(1)], 10)).toEqual([huge]);
    // The byte cut is a cut like any other: the pod resumes at its newest kept entry.
    const result = page([{ podId: "a", entries: four, scannedUpTo: "2026-10-20T12:00:03Z", done: true }], 10, {});
    expect(result.results).toHaveLength(3);
    expect(decodeToken(result.next_page_token)).toEqual({ a: "2026-10-20T12:00:02Z" });
  });

  test("a filter that rejects a whole read still carries a token while the pod is not done", () => {
    const result = page([{ podId: "a", entries: [], scannedUpTo: "2026-10-20T12:00:05Z", done: false }], 10, {});
    expect(result.results).toEqual([]);
    expect(decodeToken(result.next_page_token)).toEqual({ a: "2026-10-20T12:00:05Z" });
  });
});

describe("arguments", () => {
  test("epoch milliseconds keep their precision, anything else is refused", () => {
    expect(epochMs("1792497600999")).toBe(T0 + 999);
    expect(() => epochMs("2026-10-20")).toThrow(expect.objectContaining({ code: "INVALID_TIME" }));
  });

  test("the application is required, the limit defaults to 500, deploy_id stands in for deployment_id, instances are a list", () => {
    expect(() => logReadArguments({})).toThrow(expect.objectContaining({ code: "MISSING_APPLICATION_ID" }));
    const args = logReadArguments({ application_id: "4", scope_id: "5", deploy_id: "6", start_time: 1792497600000, instance_id: "d-6-a, d-6-b" }, T0 + 60_000);
    expect(args).toMatchObject({ applicationId: "4", scopeId: "5", deploymentId: "6", limit: 500, startMs: T0, endMs: undefined, instanceIds: ["d-6-a", "d-6-b"] });
    expect(labelSelector(args)).toBe("nullplatform=true,application_id=4,scope_id=5,deployment_id=6");
  });

  test("the page is the window's tier when that beats the limit, and the limit otherwise", () => {
    const minutes = (count: number) => count * 60_000;
    // A day's range pages by 700 however small the limit sent; a limit above the tier stays.
    expect(pageSizeOf(100, T0, T0 + minutes(1439), T0 + minutes(2000))).toBe(700);
    expect(pageSizeOf(1000, T0, T0 + minutes(1439), T0 + minutes(2000))).toBe(1000);
    expect(pageSizeOf(100, T0, T0 + minutes(10_000), T0 + minutes(10_000))).toBe(1000);
    // The window ends at now when the end is ahead of it: a live tail's poll, a moment ago to the end of the day, takes the smallest tier.
    expect(pageSizeOf(60, T0 + minutes(1000) - 1, T0 + minutes(1439), T0 + minutes(1000))).toBe(100);
    expect(pageSizeOf(60, T0, undefined, T0 + minutes(100))).toBe(400);
    // No start is no window.
    expect(pageSizeOf(60, undefined, T0 + minutes(1439), T0 + minutes(2000))).toBe(60);
    const args = logReadArguments({ application_id: "4", limit: 100, start_time: T0, end_time: T0 + minutes(720) }, T0 + minutes(720));
    expect(args.limit).toBe(700);
  });
});

describe("readLogs", () => {
  const raw = { application_id: "4", scope_id: "5", deploy_id: "6", limit: 10 };
  const labels = { nullplatform: "true", application_id: "4", scope_id: "5", deployment_id: "6" };
  const labelled = (name: string) => pod(name, `uid-${name}`, { metadata: { name, uid: `uid-${name}`, namespace: "nullplatform", labels } });

  /** Pages through the whole window as the console scrolls: the token, and the start at the newest line seen + 1 ms. */
  async function scroll(kube: ReturnType<typeof inMemoryKube>, extra: Record<string, unknown>): Promise<{ pages: number[]; seen: string[] }> {
    const pages: number[] = [];
    const seen: string[] = [];
    let token = "";
    let newest = 0;
    do {
      const result = await readLogs({ kube, namespace: undefined }, { ...raw, ...extra, ...(newest ? { start_time: newest + 1 } : {}), ...(token ? { next_page_token: token } : {}) });
      pages.push(result.results.length);
      seen.push(...result.results.map((entry) => `${entry.pod.name}:${entry.message}`));
      newest = Math.max(newest, ...result.results.map((entry) => millisecondOf(entry.datetime)));
      token = result.next_page_token;
    } while (token !== "" && pages.length < 200);
    return { pages, seen };
  }

  test("merges every pod's lines in time order and pages through all of them exactly once", async () => {
    const kube = inMemoryKube({ pods: samplePods(), logs: sampleLogs() });
    const { seen } = await scroll(kube, {});
    expect(seen).toHaveLength(30);
    expect(new Set(seen).size).toBe(30);
    const first = await readLogs({ kube, namespace: undefined }, raw);
    expect(first.results.map((e) => e.datetime)).toEqual([...first.results.map((e) => e.datetime)].sort());
    expect(first.results).toHaveLength(10);
  });

  test("a second that logged more than one read's bytes still makes progress", async () => {
    // 40 long lines in the same second: the first read is cut inside the second, and the next page resumes at that second.
    const same = Array.from({ length: 40 }, (unused, index) => `2026-10-20T12:00:00.${String(index).padStart(9, "0")}Z line ${index} ${"x".repeat(3000)}`);
    const kube = inMemoryKube({ pods: [pod("d-6-a", "uid-a")], logs: { "d-6-a": same } });
    const { seen } = await scroll(kube, {});
    expect(seen.map((line) => line.split(" ")[1])).toEqual(same.map((unused, index) => String(index)));
  });

  test("a page is as full as the window allows, not as its quietest pod", async () => {
    // Ten pods, one of them chatty with 500-byte lines, the rest silent: its share of the page's bytes alone would fill 61 of 100.
    const pods = Array.from({ length: 10 }, (unused, index) => labelled(`p${index}`));
    const chatty = Array.from({ length: 1200 }, (unused, index) => stamped(T0 + index * 50, 0, `line ${index} ${"x".repeat(460)}`));
    const kube = inMemoryKube({ pods, logs: { p0: chatty } });
    const { pages, seen } = await scroll(kube, { limit: 100, end_time: T0 + 60_000 });
    expect(pages).toEqual(Array.from({ length: 12 }, () => 100));
    expect(new Set(seen).size).toBe(1200);
  });

  test("a poll from the newest line + 1 ms returns nothing already delivered, and every line after it", async () => {
    // The console polls a live tail with start_time = the newest line seen + 1 ms; the API resumes at that second.
    const burst = Array.from({ length: 100 }, (unused, index) => stamped(T0 + 500, index, `burst ${index}`));
    const later = [stamped(T0 + 502, 0, "late 0"), stamped(T0 + 1200, 0, "late 1")];
    const kube = inMemoryKube({ pods: [labelled("a")], logs: { a: [...burst, ...later] } });
    const first = await scroll(kube, { limit: 60, end_time: T0 + 501 });
    expect(first.pages).toEqual([60, 40]);
    const poll = await readLogs({ kube, namespace: undefined }, { ...raw, limit: 60, start_time: T0 + 501 });
    expect(poll.results.map((entry) => entry.message)).toEqual(["late 0", "late 1"]);
    expect(poll.next_page_token).toBe("");
  });

  test("instances read their pods by name, a missing one is a named error, and no pods is an empty page", async () => {
    const kube = inMemoryKube({ pods: samplePods(), logs: sampleLogs() });
    const one = await readLogs({ kube, namespace: "nullplatform" }, { ...raw, instance_id: "d-6-b" });
    expect(one.results.every((entry) => entry.pod.name === "d-6-b")).toBe(true);
    expect(one.results).toHaveLength(5);
    const both = await readLogs({ kube, namespace: "nullplatform" }, { ...raw, limit: 100, instance_id: "d-6-a,d-6-b" });
    expect(both.results).toHaveLength(30);
    await expect(readLogs({ kube, namespace: "nullplatform" }, { ...raw, instance_id: "d-6-a,nope" })).rejects.toMatchObject({ code: "POD_NOT_FOUND", message: "pod nope not found in namespace nullplatform" });
    expect(await readLogs({ kube, namespace: "elsewhere" }, raw)).toEqual({ results: [], next_page_token: "" });
  });

  test("the window honors start and end, as epoch milliseconds", async () => {
    const kube = inMemoryKube({ pods: [pod("d-6-a", "uid-a")], logs: { "d-6-a": lines("2026-10-20T12:00:00.000Z", 10, "a") } });
    const result = await readLogs({ kube, namespace: undefined }, { ...raw, start_time: T0 + 3000, end_time: T0 + 5000 });
    expect(result.results.map((e) => e.message)).toEqual(["a 3", "a 4", "a 5"]);
    expect(result.next_page_token).toBe("");
  });
});
