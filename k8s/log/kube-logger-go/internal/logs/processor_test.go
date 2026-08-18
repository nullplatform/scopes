package logs

import "testing"

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
