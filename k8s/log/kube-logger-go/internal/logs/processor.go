package logs

import (
	"bufio"
	"strings"
	"time"

	"kube-logger-go/internal/types"
)

// Processor handles log processing operations
type Processor struct{}

// NewProcessor creates a new log processor instance
func NewProcessor() *Processor {
	return &Processor{}
}

// ProcessLinesFromChannel reads one pod's lines from a channel and returns what the read
// covered. endTime is applied here because the Kubernetes API only accepts a lower bound
// (SinceTime). ScannedUpTo advances through every line inside the window, also the ones the
// filter rejects, so the next page resumes after them instead of reading them again.
func (p *Processor) ProcessLinesFromChannel(logCh <-chan string, filterPattern, podName, podUID, lastReadTime, endTime string) types.PodScan {
	scan := types.PodScan{PodID: podUID, Entries: []types.LogEntry{}}

	var terms []string
	if filterPattern != "" {
		terms = strings.Fields(filterPattern)
	}

	for line := range logCh {
		if line == "" {
			continue
		}

		parts := strings.SplitN(line, " ", 2)
		if len(parts) < 2 {
			continue
		}

		timestamp := parts[0]
		message := parts[1]

		if !p.isValidTimestamp(timestamp) {
			continue
		}

		if lastReadTime != "" && lastReadTime != "null" && lastReadTime != "empty" {
			if timestamp <= lastReadTime {
				continue
			}
		}

		// The stream is chronological, so the first line past the window ends it.
		if endTime != "" && timestamp > endTime {
			scan.Done = true
			break
		}

		scan.ScannedUpTo = timestamp

		if len(terms) > 0 {
			matches := true
			for _, term := range terms {
				if !strings.Contains(line, term) {
					matches = false
					break
				}
			}
			if !matches {
				continue
			}
		}

		scan.Entries = append(scan.Entries, types.LogEntry{
			Message:  message,
			DateTime: timestamp,
			Pod: types.PodInfo{
				Name: podName,
				ID:   podUID,
			},
		})
	}

	return scan
}

// ProcessLines processes raw log content and returns structured log entries
func (p *Processor) ProcessLines(logs, filterPattern, podName, podUID, lastReadTime string) []types.LogEntry {
	if logs == "" {
		return []types.LogEntry{}
	}

	var entries []types.LogEntry
	scanner := bufio.NewScanner(strings.NewReader(logs))

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		// Extract timestamp and message
		parts := strings.SplitN(line, " ", 2)
		if len(parts) < 2 {
			continue
		}

		timestamp := parts[0]
		message := parts[1]

		// Validate timestamp format - skip lines with invalid timestamps
		if !p.isValidTimestamp(timestamp) {
			continue
		}

		// Duplicate detection logic (matching bash script behavior)
		if lastReadTime != "" && lastReadTime != "null" && lastReadTime != "empty" {
			// If timestamp is same or older than last read time, skip it
			if timestamp <= lastReadTime {
				continue
			}
		}

		// Apply filter if specified (all terms in filterPattern must be present)
		if filterPattern != "" {
			terms := strings.Fields(filterPattern)
			matches := true
			for _, term := range terms {
				if !strings.Contains(line, term) {
					matches = false
					break
				}
			}
			if !matches {
				continue
			}
		}

		entry := types.LogEntry{
			Message:  message,
			DateTime: timestamp,
			Pod: types.PodInfo{
				Name: podName,
				ID:   podUID,
			},
		}

		entries = append(entries, entry)
	}

	return entries
}

// isValidTimestamp checks if a timestamp string is in a valid format
func (p *Processor) isValidTimestamp(timestamp string) bool {
	return ValidTimestamp(timestamp)
}

// ValidTimestamp reports whether a string is an RFC3339 timestamp.
func ValidTimestamp(timestamp string) bool {
	// Check RFC3339 format (e.g., 2025-09-04T15:24:34.944759409Z)
	_, err := time.Parse(time.RFC3339Nano, timestamp)
	if err != nil {
		_, err = time.Parse(time.RFC3339, timestamp)
	}
	return err == nil
}
