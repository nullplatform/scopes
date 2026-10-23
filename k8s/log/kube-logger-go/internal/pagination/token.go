package pagination

import (
	"encoding/base64"
	"encoding/json"
	"sort"

	"kube-logger-go/internal/types"
)

// DecodeToken decodes a base64 pagination token into a map
func DecodeToken(token string) map[string]string {
	if token == "" {
		return make(map[string]string)
	}

	decoded, err := base64.StdEncoding.DecodeString(token)
	if err != nil {
		return make(map[string]string)
	}

	var result map[string]string
	if err := json.Unmarshal(decoded, &result); err != nil {
		return make(map[string]string)
	}

	return result
}

// encodeToken encodes a map into a base64 pagination token
func encodeToken(data map[string]string) string {
	if len(data) == 0 {
		return ""
	}

	jsonData, err := json.Marshal(data)
	if err != nil {
		return ""
	}

	return base64.StdEncoding.EncodeToString(jsonData)
}

// Page merges the pod scans, orders their entries, cuts them to the limit and returns the
// token that resumes after what this page covered. A pod whose entries the cut dropped
// resumes after its newest kept entry; any other pod resumes after the last line it read,
// matched or not, so a filter that rejects a whole read still moves the search forward.
// The token is empty only when no pod has anything left to read in the window, so an empty
// page can still carry one: the caller asks again.
func Page(scans []types.PodScan, limit int, previous map[string]string) ([]types.LogEntry, string) {
	entries := []types.LogEntry{}
	for _, scan := range scans {
		entries = append(entries, scan.Entries...)
	}

	sort.SliceStable(entries, func(i, j int) bool {
		return entries[i].DateTime < entries[j].DateTime
	})
	if len(entries) > limit {
		entries = entries[:limit]
	}

	// Entries are in time order, so the last one kept per pod is its newest.
	keptPerPod := make(map[string]int, len(scans))
	newestKept := make(map[string]string, len(scans))
	for _, entry := range entries {
		keptPerPod[entry.Pod.ID]++
		newestKept[entry.Pod.ID] = entry.DateTime
	}

	cursors := make(map[string]string, len(previous)+len(scans))
	for podID, lastRead := range previous {
		cursors[podID] = lastRead
	}

	more := false
	for _, scan := range scans {
		if keptPerPod[scan.PodID] < len(scan.Entries) {
			more = true
			if newest, ok := newestKept[scan.PodID]; ok {
				cursors[scan.PodID] = newest
			}
			continue
		}
		if scan.ScannedUpTo != "" {
			cursors[scan.PodID] = scan.ScannedUpTo
		}
		if !scan.Done {
			more = true
		}
	}

	if !more {
		return entries, ""
	}
	return entries, encodeToken(cursors)
}
