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

// The token records the newest entry kept per pod, so the next page resumes exactly where
// this one was cut. That only holds if the cut keeps the oldest entries.
func TestPageKeepsTheOldestEntriesAndTokensTheCut(t *testing.T) {
	entries := []types.LogEntry{
		entry("2026-08-17T10:00:03Z", "a"),
		entry("2026-08-17T10:00:01Z", "a"),
		entry("2026-08-17T10:00:04Z", "b"),
		entry("2026-08-17T10:00:02Z", "b"),
	}

	page, token := Page(entries, 2, map[string]string{})

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

// A pod can contribute nothing to a page: it has no new lines, or the rest of its lines
// are past end_time. Dropping its cursor would make the next page re-read it from
// start_time and re-deliver lines the caller already saw.
func TestPageCarriesForwardPodsThatContributedNothing(t *testing.T) {
	incoming := map[string]string{
		"a": "2026-08-17T10:00:01Z",
		"b": "2026-08-17T10:00:02Z",
	}

	_, token := Page([]types.LogEntry{entry("2026-08-17T10:00:05Z", "a")}, 100, incoming)

	cursors := DecodeToken(token)
	if cursors["a"] != "2026-08-17T10:00:05Z" {
		t.Errorf("expected pod a to advance to its newest kept entry, got %q", cursors["a"])
	}
	if cursors["b"] != "2026-08-17T10:00:02Z" {
		t.Errorf("expected pod b to keep its cursor, got %q", cursors["b"])
	}
}

// An empty page is how the caller learns there are no more pages, so the cursors must not
// survive it — carrying them forward would keep pagination going forever.
func TestPageWithNoEntriesEndsPagination(t *testing.T) {
	page, token := Page(nil, 100, map[string]string{"a": "2026-08-17T10:00:01Z"})

	if page == nil {
		t.Error("expected an empty slice rather than nil, it is serialized as results")
	}
	if len(page) != 0 {
		t.Errorf("expected no entries, got %d", len(page))
	}
	if token != "" {
		t.Errorf("expected an empty token to end pagination, got %q", token)
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
