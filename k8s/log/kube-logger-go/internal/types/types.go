package types

const (
	DefaultContainerName = "application"
	DefaultLimit        = 100
	MinLogsPerPod       = 10
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

// Response is the final output structure
type Response struct {
	Results       []LogEntry `json:"results"`
	NextPageToken string     `json:"next_page_token"`
}

// Config holds all command line configuration
type Config struct {
	Namespace      string
	ApplicationID  string
	ScopeID        string
	DeploymentID   string
	Limit          int
	NextPageToken  string
	FilterPattern  string
	StartTime      string
	InstanceID     string
}