package logs

import "testing"

// A bound that is not RFC3339 compares below every timestamp, leaving the window unbounded.
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

// The Kubernetes API only bounds reads from below, so the upper bound is applied here.
func TestProcessLinesFromChannelAppliesEndTime(t *testing.T) {
	lines := []string{
		"2026-08-17T10:00:00.000000000Z inside the window",
		"2026-08-18T09:00:00.000000000Z after the window",
	}

	entries := NewProcessor().ProcessLinesFromChannel(
		linesChannel(lines...), "", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z",
	).Entries

	if len(entries) != 1 {
		t.Fatalf("expected 1 entry within the window, got %d", len(entries))
	}
	if entries[0].Message != "inside the window" {
		t.Errorf("unexpected entry retained: %q", entries[0].Message)
	}
}

// Leftovers in the channel are what distinguishes stopping from filtering to the end.
func TestProcessLinesFromChannelStopsReadingPastEndTime(t *testing.T) {
	ch := make(chan string, 10)
	ch <- "2026-08-17T10:00:00.000000000Z inside the window"
	ch <- "2026-08-18T09:00:00.000000000Z first line past the window"
	ch <- "2026-08-18T10:00:00.000000000Z should never be read"
	close(ch)

	entries := NewProcessor().ProcessLinesFromChannel(ch, "", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z").Entries

	if len(entries) != 1 {
		t.Fatalf("expected 1 entry within the window, got %d", len(entries))
	}
	if len(ch) != 1 {
		t.Errorf("expected the processor to stop at the first out-of-window line, leaving 1 unread; %d left", len(ch))
	}
}

// A filtered-out line must not be mistaken for the end of the window.
func TestProcessLinesFromChannelKeepsReadingThroughFilteredLines(t *testing.T) {
	ch := make(chan string, 10)
	ch <- "2026-08-17T10:00:00.000000000Z keep me"
	ch <- "2026-08-17T11:00:00.000000000Z drop me"
	ch <- "2026-08-17T12:00:00.000000000Z keep me too"
	close(ch)

	entries := NewProcessor().ProcessLinesFromChannel(ch, "keep", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z").Entries

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
	).Entries

	if len(entries) != 2 {
		t.Fatalf("expected both entries when no upper bound is set, got %d", len(entries))
	}
}

// The cursor has to move through lines the filter drops, or a read with no match ends the
// search where it stands.
func TestProcessLinesFromChannelScansPastFilteredLines(t *testing.T) {
	scan := NewProcessor().ProcessLinesFromChannel(linesChannel(
		"2026-08-17T10:00:00.000000000Z no match",
		"2026-08-17T10:00:01.000000000Z no match either",
	), "needle", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z")

	if len(scan.Entries) != 0 {
		t.Fatalf("expected no entries, got %d", len(scan.Entries))
	}
	if scan.ScannedUpTo != "2026-08-17T10:00:01.000000000Z" {
		t.Errorf("expected the scan to reach the last line read, got %q", scan.ScannedUpTo)
	}
	if scan.Done {
		t.Error("a read that ran out of lines is not done: only the fetcher knows if the log ended")
	}
}

func TestProcessLinesFromChannelIsDoneAtEndTime(t *testing.T) {
	scan := NewProcessor().ProcessLinesFromChannel(linesChannel(
		"2026-08-17T10:00:00.000000000Z inside",
		"2026-08-18T09:00:00.000000000Z past the window",
	), "", "pod-a", "uid-a", "", "2026-08-17T23:59:59Z")

	if !scan.Done {
		t.Error("expected the scan to be done once a line passed end_time")
	}
	if scan.ScannedUpTo != "2026-08-17T10:00:00.000000000Z" {
		t.Errorf("the line past end_time must not move the cursor, got %q", scan.ScannedUpTo)
	}
}
