package types

const (
	DefaultContainerName = "application"
	DefaultLimit         = 100
	MinLogsPerPod        = 10
)

// LogEntry represents a single log entry
type LogEntry struct {
	Message  string  `json:"message"`
	DateTime string  `json:"datetime"`
	Pod      PodInfo `json:"pod"`
}

// PodInfo contains pod identification information
type PodInfo struct {
	Name string `json:"name"`
	ID   string `json:"id"`
}

// PodScan is what one request read from one pod: the entries that matched, how far the
// read got through the window, and whether the pod has anything left to read in it.
type PodScan struct {
	PodID   string
	Entries []LogEntry
	// ScannedUpTo is the timestamp of the last line read inside the window, whether the
	// filter kept it or not. Empty when no line passed the cursor.
	ScannedUpTo string
	// Done means the read reached end_time or the end of the pod's log, rather than
	// stopping at the byte limit.
	Done bool
}

// Response is the final output structure
type Response struct {
	Results       []LogEntry `json:"results"`
	NextPageToken string     `json:"next_page_token"`
}

// Config holds all command line configuration
type Config struct {
	Namespace     string
	ApplicationID string
	ScopeID       string
	DeploymentID  string
	Limit         int
	NextPageToken string
	FilterPattern string
	StartTime     string
	EndTime       string
	InstanceID    string
}
