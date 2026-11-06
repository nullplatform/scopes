package pagination

import (
	"testing"

	"kube-logger-go/internal/types"
)

func entry(timestamp, podID string) types.LogEntry {
	return types.LogEntry{
		Message:  "line at " + timestamp,
		DateTime: timestamp,
		Pod:      types.PodInfo{Name: "pod-" + podID, ID: podID},
	}
}

func scan(podID string, done bool, scannedUpTo string, entries ...types.LogEntry) types.PodScan {
	return types.PodScan{PodID: podID, Entries: entries, ScannedUpTo: scannedUpTo, Done: done}
}

// The token resumes where the cut landed, which only holds if the cut keeps the oldest.
func TestPageKeepsTheOldestEntriesAndTokensTheCut(t *testing.T) {
	scans := []types.PodScan{
		scan("a", true, "2026-08-17T10:00:03Z", entry("2026-08-17T10:00:03Z", "a"), entry("2026-08-17T10:00:01Z", "a")),
		scan("b", true, "2026-08-17T10:00:04Z", entry("2026-08-17T10:00:04Z", "b"), entry("2026-08-17T10:00:02Z", "b")),
	}

	page, token := Page(scans, 2, map[string]string{})

	if len(page) != 2 {
		t.Fatalf("expected the page to be cut to the limit, got %d entries", len(page))
	}
	if page[0].DateTime != "2026-08-17T10:00:01Z" || page[1].DateTime != "2026-08-17T10:00:02Z" {
		t.Errorf("expected the two oldest entries, got %s and %s", page[0].DateTime, page[1].DateTime)
	}

	cursors := DecodeToken(token)
	if cursors["a"] != "2026-08-17T10:00:01Z" || cursors["b"] != "2026-08-17T10:00:02Z" {
		t.Errorf("token does not point at the cut: %v", cursors)
	}
}

// Dropping the cursor of a pod that contributed nothing makes the next page re-read it.
func TestPageCarriesForwardPodsThatContributedNothing(t *testing.T) {
	incoming := map[string]string{
		"a": "2026-08-17T10:00:01Z",
		"b": "2026-08-17T10:00:02Z",
	}

	_, token := Page([]types.PodScan{
		scan("a", false, "2026-08-17T10:00:05Z", entry("2026-08-17T10:00:05Z", "a")),
	}, 100, incoming)

	cursors := DecodeToken(token)
	if cursors["a"] != "2026-08-17T10:00:05Z" {
		t.Errorf("expected pod a to advance to the last line it read, got %q", cursors["a"])
	}
	if cursors["b"] != "2026-08-17T10:00:02Z" {
		t.Errorf("expected pod b to keep its cursor, got %q", cursors["b"])
	}
}

// A read the filter rejected entirely is not the end of the window: the page is empty, but
// the token moves past what was read so the caller can ask for the rest.
func TestPageWithNoEntriesKeepsGoingWhileAPodHasMoreToRead(t *testing.T) {
	page, token := Page([]types.PodScan{
		scan("a", false, "2026-08-17T10:00:09Z"),
		scan("b", true, "2026-08-17T10:00:04Z"),
	}, 100, map[string]string{"a": "2026-08-17T10:00:01Z"})

	if page == nil || len(page) != 0 {
		t.Fatalf("expected an empty, non-nil page, got %v", page)
	}

	cursors := DecodeToken(token)
	if cursors["a"] != "2026-08-17T10:00:09Z" {
		t.Errorf("expected pod a to resume after the lines it read, got %q", cursors["a"])
	}
	if cursors["b"] != "2026-08-17T10:00:04Z" {
		t.Errorf("expected pod b to keep the cursor of its finished read, got %q", cursors["b"])
	}
}

// The token ends pagination only when every pod read to the end of the window.
func TestPageEndsPaginationWhenEveryPodIsDone(t *testing.T) {
	page, token := Page([]types.PodScan{
		scan("a", true, "2026-08-17T10:00:09Z"),
		scan("b", true, ""),
	}, 100, map[string]string{"a": "2026-08-17T10:00:01Z"})

	if page == nil {
		t.Error("expected an empty slice rather than nil, it is serialized as results")
	}
	if token != "" {
		t.Errorf("expected an empty token to end pagination, got %q", token)
	}
}

// A pod whose entries the cut dropped must resume at the cut, even if it read further.
func TestPageResumesACutPodAtItsNewestKeptEntry(t *testing.T) {
	_, token := Page([]types.PodScan{
		scan("a", true, "2026-08-17T10:00:09Z",
			entry("2026-08-17T10:00:01Z", "a"),
			entry("2026-08-17T10:00:02Z", "a"),
			entry("2026-08-17T10:00:03Z", "a")),
	}, 2, map[string]string{})

	cursors := DecodeToken(token)
	if cursors["a"] != "2026-08-17T10:00:02Z" {
		t.Errorf("expected pod a to resume after its newest kept entry, got %q", cursors["a"])
	}
}

func TestTokenRoundTrip(t *testing.T) {
	cursors := map[string]string{"a": "2026-08-17T10:00:01Z", "b": "2026-08-17T10:00:02.5Z"}

	decoded := DecodeToken(encodeToken(cursors))

	for podID, want := range cursors {
		if decoded[podID] != want {
			t.Errorf("pod %s: expected %q, got %q", podID, want, decoded[podID])
		}
	}
}

func TestDecodeTokenToleratesGarbage(t *testing.T) {
	for _, token := range []string{"", "not base64!", "bm90IGpzb24="} {
		if cursors := DecodeToken(token); len(cursors) != 0 {
			t.Errorf("token %q: expected no cursors, got %v", token, cursors)
		}
	}
}
