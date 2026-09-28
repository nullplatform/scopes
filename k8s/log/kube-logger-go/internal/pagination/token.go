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

// Page orders the entries, cuts them to the limit and returns the token that resumes after
// the cut. The token records the newest entry kept per pod, so the cut keeps the oldest.
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

// GenerateToken creates a pagination token from log entries. previous keeps the cursor of a
// pod that contributed nothing to this page, so the next page resumes it instead of reading
// it again from start_time. An empty page returns an empty token, which ends pagination.
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
