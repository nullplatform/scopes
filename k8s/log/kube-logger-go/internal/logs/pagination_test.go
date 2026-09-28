package logs

import (
	"strings"
	"testing"
	"time"

	"kube-logger-go/internal/pagination"
	"kube-logger-go/internal/types"
)

// podLogs stands in for the Kubernetes API: chronological lines, bounded from below only.
type podLogs map[string][]string

func (l podLogs) stream(t *testing.T, podUID, sinceTime string) <-chan string {
	t.Helper()

	lines := l[podUID]
	ch := make(chan string, len(lines))
	since := mustParse(t, sinceTime)

	for _, line := range lines {
		if at := mustParse(t, strings.SplitN(line, " ", 2)[0]); !at.Before(since) {
			ch <- line
		}
	}
	close(ch)

	return ch
}

func mustParse(t *testing.T, timestamp string) time.Time {
	t.Helper()

	if timestamp == "" {
		return time.Time{}
	}
	at, err := time.Parse(time.RFC3339Nano, timestamp)
	if err != nil {
		t.Fatalf("test data has a non-RFC3339 timestamp %q: %v", timestamp, err)
	}

	return at
}

// fetchPage mirrors what cmd/main.go does for one request.
func fetchPage(t *testing.T, store podLogs, podUIDs []string, cfg types.Config) ([]types.LogEntry, string) {
	t.Helper()

	cursors := pagination.DecodeToken(cfg.NextPageToken)
	processor := NewProcessor()

	var collected []types.LogEntry
	for _, podUID := range podUIDs {
		sinceTime := determineSinceTime(podUID, cursors, cfg.StartTime)
		collected = append(collected, processor.ProcessLinesFromChannel(
			store.stream(t, podUID, sinceTime),
			cfg.FilterPattern,
			"pod-"+podUID,
			podUID,
			getLastReadTime(podUID, cursors),
			cfg.EndTime,
		)...)
	}

	return pagination.Page(collected, cfg.Limit, cursors)
}

// A pod that loses its cursor restarts from start_time, and with more than one pod the
// pages take turns evicting each other and never reach the end of the window. Pod c has no
// lines in the window at all, so it never earns a cursor and is re-read on every page.
func TestPaginationDeliversEveryLineInTheWindowExactlyOnce(t *testing.T) {
	store := podLogs{
		"a": {
			"2026-08-17T10:00:01.000000000Z a first",
			"2026-08-17T10:00:03.000000000Z a second",
			"2026-08-17T10:00:05.000000000Z a third",
		},
		"b": {
			"2026-08-17T10:00:02.000000000Z b first",
			"2026-08-17T10:00:04.000000000Z b second",
		},
		"c": {
			"2026-08-18T09:00:00.000000000Z c past the window",
		},
	}
	cfg := types.Config{
		Limit:     2,
		StartTime: "2026-08-17T10:00:00Z",
		EndTime:   "2026-08-17T10:00:59Z",
	}

	delivered := map[string]int{}
	token := ""

	for page := 1; ; page++ {
		if page > 10 {
			t.Fatalf("pagination did not terminate after 10 pages, delivered: %v", delivered)
		}

		cfg.NextPageToken = token
		entries, next := fetchPage(t, store, []string{"a", "b", "c"}, cfg)

		for i, entry := range entries {
			if i > 0 && entries[i-1].DateTime > entry.DateTime {
				t.Errorf("page %d is out of order: %s before %s", page, entries[i-1].DateTime, entry.DateTime)
			}
			delivered[entry.Message]++
		}

		if next == "" {
			break
		}
		token = next
	}

	for _, message := range []string{"a first", "a second", "a third", "b first", "b second"} {
		if delivered[message] != 1 {
			t.Errorf("expected %q delivered exactly once, got %d", message, delivered[message])
		}
	}
	if delivered["c past the window"] != 0 {
		t.Errorf("a line past end_time was delivered %d times", delivered["c past the window"])
	}
}
