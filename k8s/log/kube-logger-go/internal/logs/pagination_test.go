package logs

import (
	"context"
	"fmt"
	"io"
	"strings"
	"testing"
	"time"

	"kube-logger-go/internal/pagination"
	"kube-logger-go/internal/types"
)

// podLogs stands in for the Kubernetes API: chronological lines, bounded from below only,
// with SinceTime at second precision (metav1.Time) and the output cut at a byte limit.
type podLogs map[string][]string

func (l podLogs) reader(t *testing.T, podUID, sinceTime string) io.Reader {
	t.Helper()

	since := mustParse(t, sinceTime).Truncate(time.Second)
	var out strings.Builder
	for _, line := range l[podUID] {
		if at := mustParse(t, strings.SplitN(line, " ", 2)[0]); !at.Before(since) {
			out.WriteString(line)
			out.WriteString("\n")
		}
	}

	return strings.NewReader(out.String())
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

// fetchPage mirrors what cmd/main.go does for one request, reading at most limitBytes per pod.
func fetchPage(t *testing.T, store podLogs, podUIDs []string, cfg types.Config, limitBytes int64) ([]types.LogEntry, string) {
	t.Helper()

	cursors := pagination.DecodeToken(cfg.NextPageToken)

	var scans []types.PodScan
	for _, podUID := range podUIDs {
		sinceTime := determineSinceTime(podUID, cursors, cfg.StartTime)
		stream := func(ctx context.Context, limit int64, out chan<- string) bool {
			return forwardLines(ctx, io.LimitReader(store.reader(t, podUID, sinceTime), limit), limit, out)
		}
		scans = append(scans, scanPod(stream, limitBytes, cfg.FilterPattern, "pod-"+podUID, podUID, getLastReadTime(podUID, cursors), cfg.EndTime))
	}

	return pagination.Page(scans, cfg.Limit, cursors)
}

// paginate asks for pages until the token ends, as the dashboard does, and counts what came.
func paginate(t *testing.T, store podLogs, podUIDs []string, cfg types.Config, limitBytes int64) (map[string]int, int) {
	t.Helper()

	delivered := map[string]int{}
	token := ""
	for page := 1; ; page++ {
		if page > 50 {
			t.Fatalf("pagination did not terminate after 50 pages, delivered: %v", delivered)
		}

		cfg.NextPageToken = token
		entries, next := fetchPage(t, store, podUIDs, cfg, limitBytes)

		for i, entry := range entries {
			if i > 0 && entries[i-1].DateTime > entry.DateTime {
				t.Errorf("page %d is out of order: %s before %s", page, entries[i-1].DateTime, entry.DateTime)
			}
			delivered[entry.Message]++
		}

		if next == "" {
			return delivered, page
		}
		token = next
	}
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

	delivered, _ := paginate(t, store, []string{"a", "b", "c"}, cfg, 1<<20)

	for _, message := range []string{"a first", "a second", "a third", "b first", "b second"} {
		if delivered[message] != 1 {
			t.Errorf("expected %q delivered exactly once, got %d", message, delivered[message])
		}
	}
	if delivered["c past the window"] != 0 {
		t.Errorf("a line past end_time was delivered %d times", delivered["c past the window"])
	}
}

// The search the dashboard runs: a needle near the end of the window, behind more lines
// than one read covers. Every read before it comes back empty, and each one must still
// hand over a token, or the search reports "no logs" while the log is there.
func TestPaginationFindsAMatchBeyondTheFirstRead(t *testing.T) {
	var lines []string
	for second := 0; second < 300; second++ {
		lines = append(lines, fmt.Sprintf("2026-08-17T10:%02d:%02d.000000000Z request served", second/60, second%60))
	}
	lines = append(lines, "2026-08-17T10:05:00.500000000Z user 3bbdbe7f revoking login")
	store := podLogs{"a": lines, "b": lines[:120]}
	cfg := types.Config{
		Limit:         100,
		FilterPattern: "3bbdbe7f",
		StartTime:     "2026-08-17T10:00:00Z",
		EndTime:       "2026-08-17T10:30:00Z",
	}

	// About 20 lines per read, so pod a needs many empty pages to reach the needle.
	delivered, pages := paginate(t, store, []string{"a", "b"}, cfg, 1000)

	if delivered["user 3bbdbe7f revoking login"] != 1 {
		t.Fatalf("expected the match delivered exactly once, got %d after %d pages", delivered["user 3bbdbe7f revoking login"], pages)
	}
	if pages < 10 {
		t.Errorf("expected the byte limit to force many pages, got %d: the test is not exercising the cut", pages)
	}
}

// A cut can land in the middle of a line. That line must arrive whole on a later page, once.
func TestPaginationNeverDeliversALineCutByTheByteLimit(t *testing.T) {
	store := podLogs{"a": {
		"2026-08-17T10:00:01.000000000Z first line with some padding to cross the limit",
		"2026-08-17T10:00:02.000000000Z second line with some padding to cross the limit",
		"2026-08-17T10:00:03.000000000Z third line with some padding to cross the limit",
	}}
	cfg := types.Config{Limit: 100, StartTime: "2026-08-17T10:00:00Z", EndTime: "2026-08-17T10:00:59Z"}

	delivered, _ := paginate(t, store, []string{"a"}, cfg, 120)

	for _, message := range []string{
		"first line with some padding to cross the limit",
		"second line with some padding to cross the limit",
		"third line with some padding to cross the limit",
	} {
		if delivered[message] != 1 {
			t.Errorf("expected %q delivered whole exactly once, got %d (delivered: %v)", message, delivered[message], delivered)
		}
	}
}

// The Kubernetes API resumes at the cursor's second. When that second alone holds more than
// one read, the read must grow instead of returning the same token again.
func TestPaginationGetsPastASecondLargerThanOneRead(t *testing.T) {
	var lines []string
	for i := 0; i < 40; i++ {
		lines = append(lines, fmt.Sprintf("2026-08-17T10:00:01.%09dZ busy second line %02d", i+1, i))
	}
	lines = append(lines, "2026-08-17T10:00:02.000000000Z after the busy second")
	store := podLogs{"a": lines}
	cfg := types.Config{Limit: 10, StartTime: "2026-08-17T10:00:00Z", EndTime: "2026-08-17T10:00:59Z"}

	delivered, _ := paginate(t, store, []string{"a"}, cfg, 400)

	if len(delivered) != len(lines) {
		t.Errorf("expected all %d lines delivered, got %d", len(lines), len(delivered))
	}
	for message, times := range delivered {
		if times != 1 {
			t.Errorf("expected %q delivered once, got %d", message, times)
		}
	}
}
