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

// Page turns the entries collected from every pod into one page of results plus the
// token that resumes after it.
//
// The three steps are one decision, not three: the token records the newest entry kept
// per pod, and that is the cut point only because the entries are sorted ascending and
// the cut keeps the oldest ones. Cutting the newest instead would leave everything
// before the cut unreachable.
func Page(entries []types.LogEntry, limit int, previous map[string]string) ([]types.LogEntry, string) {
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].DateTime < entries[j].DateTime
	})

	if len(entries) > limit {
		entries = entries[:limit]
	}
	if len(entries) == 0 {
		entries = []types.LogEntry{}
	}

	return entries, GenerateToken(entries, previous)
}

// GenerateToken creates a pagination token from log entries.
//
// previous holds the cursors decoded from the incoming token. A pod that contributed no
// entries to this page — because it has no new lines, or because the rest of its lines
// fall outside the requested window — has to keep the cursor it already had. Dropping it
// makes determineSinceTime fall back to start_time on the next page, so the pod re-reads
// the window from the beginning and re-delivers lines the caller already saw; with more
// than one pod, pages take turns evicting each other and pagination never terminates.
//
// An empty page still produces an empty token: that is how the caller learns there are no
// more pages, so the cursors are deliberately not carried forward in that case.
func GenerateToken(logs []types.LogEntry, previous map[string]string) string {
	if len(logs) == 0 {
		return ""
	}

	tokenData := make(map[string]string, len(previous)+len(logs))
	for podID, lastRead := range previous {
		tokenData[podID] = lastRead
	}
	for _, entry := range logs {
		tokenData[entry.Pod.ID] = entry.DateTime
	}

	return encodeToken(tokenData)
}
