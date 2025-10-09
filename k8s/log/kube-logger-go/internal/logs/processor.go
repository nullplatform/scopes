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

// ProcessLinesFromChannel processes log lines received from a channel and returns structured log entries
func (p *Processor) ProcessLinesFromChannel(logCh <-chan string, filterPattern, podName, podUID, lastReadTime string) []types.LogEntry {
    var entries []types.LogEntry

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
	// Check RFC3339 format (e.g., 2025-09-04T15:24:34.944759409Z)
	_, err := time.Parse(time.RFC3339Nano, timestamp)
	if err != nil {
		_, err = time.Parse(time.RFC3339, timestamp)
	}
	return err == nil
}