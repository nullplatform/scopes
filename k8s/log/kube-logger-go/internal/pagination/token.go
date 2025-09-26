package pagination

import (
	"encoding/base64"
	"encoding/json"

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

// GenerateToken creates a pagination token from log entries
func GenerateToken(logs []types.LogEntry) string {
	if len(logs) == 0 {
		return ""
	}

	tokenData := make(map[string]string)
	for _, entry := range logs {
		tokenData[entry.Pod.ID] = entry.DateTime
	}

	return encodeToken(tokenData)
}