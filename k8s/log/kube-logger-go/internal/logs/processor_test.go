package logs

import "testing"

// A bound that is not RFC3339 compares below every log timestamp, so nothing ever
// exceeds it and the window silently reverts to unbounded. Callers reject one up
// front rather than let the query answer a wider range than was asked for.
func TestValidTimestamp(t *testing.T) {
	valid := []string{
		"2026-08-17T23:59:59Z",
		"2026-08-17T10:00:00.000000000Z",
		"2026-08-17T10:00:00+02:00",
	}
	for _, timestamp := range valid {
		if !ValidTimestamp(timestamp) {
			t.Errorf("expected %q to be accepted", timestamp)
		}
	}

	invalid := []string{"", "garbage", "1786924800000", "2026-08-17", "17/08/2026"}
	for _, timestamp := range invalid {
		if ValidTimestamp(timestamp) {
			t.Errorf("expected %q to be rejected", timestamp)
		}
	}
}

func linesChannel(lines ...string) <-chan string {
	ch := make(chan string, len(lines))
	for _, line := range lines {
		ch <- line
	}
	close(ch)
	return ch
}

// The Kubernetes API only bounds log reads from below (SinceTime), so without an
// upper bound a query for a past window returns whatever the live pods hold — the
// newest lines — which reads to the user as "the filter behaves as if it were today".
func TestProcessLinesFromChannelAppliesEndTime(t *testing.T) {
	lines := []string{
		"2026-08-17T10:00:00.000000000Z inside the window",
		"2026-08-18T09:00:00.000000000Z after the window",
	}

	entries := NewProcessor().ProcessLinesFromChannel(
		linesChannel(lines...), "", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z",
	)

	if len(entries) != 1 {
		t.Fatalf("expected 1 entry within the window, got %d", len(entries))
	}
	if entries[0].Message != "inside the window" {
		t.Errorf("unexpected entry retained: %q", entries[0].Message)
	}
}

// The stream is chronological, so the processor stops at the first line past the
// window rather than reading to the end and discarding. Leftovers in the channel
// are the observable difference: draining it would mean the bound only filtered.
func TestProcessLinesFromChannelStopsReadingPastEndTime(t *testing.T) {
	ch := make(chan string, 10)
	ch <- "2026-08-17T10:00:00.000000000Z inside the window"
	ch <- "2026-08-18T09:00:00.000000000Z first line past the window"
	ch <- "2026-08-18T10:00:00.000000000Z should never be read"
	close(ch)

	entries := NewProcessor().ProcessLinesFromChannel(ch, "", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z")

	if len(entries) != 1 {
		t.Fatalf("expected 1 entry within the window, got %d", len(entries))
	}
	if len(ch) != 1 {
		t.Errorf("expected the processor to stop at the first out-of-window line, leaving 1 unread; %d left", len(ch))
	}
}

// Ordering holds within a container's stream, but a filtered-out line must not be
// mistaken for the end of the window.
func TestProcessLinesFromChannelKeepsReadingThroughFilteredLines(t *testing.T) {
	ch := make(chan string, 10)
	ch <- "2026-08-17T10:00:00.000000000Z keep me"
	ch <- "2026-08-17T11:00:00.000000000Z drop me"
	ch <- "2026-08-17T12:00:00.000000000Z keep me too"
	close(ch)

	entries := NewProcessor().ProcessLinesFromChannel(ch, "keep", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z")

	if len(entries) != 2 {
		t.Fatalf("expected both matching entries, got %d", len(entries))
	}
}

func TestProcessLinesFromChannelWithoutEndTimeKeepsEverything(t *testing.T) {
	lines := []string{
		"2026-08-17T10:00:00.000000000Z first",
		"2026-08-18T09:00:00.000000000Z second",
	}

	entries := NewProcessor().ProcessLinesFromChannel(
		linesChannel(lines...), "", "pod-a", "uid-a", "", "",
	)

	if len(entries) != 2 {
		t.Fatalf("expected both entries when no upper bound is set, got %d", len(entries))
	}
}
