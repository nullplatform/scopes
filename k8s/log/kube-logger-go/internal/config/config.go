package config

import (
	"flag"

	"kube-logger-go/internal/types"
)

// ParseFlags parses command line flags and returns a Config
func ParseFlags() types.Config {
	config := types.Config{Limit: types.DefaultLimit}

	// Long flags
	flag.StringVar(&config.Namespace, "namespace", "", "Kubernetes namespace")
	flag.StringVar(&config.ApplicationID, "application-id", "", "Application ID")
	flag.StringVar(&config.ScopeID, "scope-id", "", "Scope ID")
	flag.StringVar(&config.DeploymentID, "deployment-id", "", "Deployment ID")
	flag.IntVar(&config.Limit, "limit", types.DefaultLimit, "Maximum log entries")
	flag.StringVar(&config.NextPageToken, "next-page-token", "", "Pagination token")
	flag.StringVar(&config.FilterPattern, "filter", "", "Filter pattern")
	flag.StringVar(&config.StartTime, "start-time", "", "Start time (ISO format)")
	flag.StringVar(&config.InstanceID, "instance-id", "", "Instance ID")

	// Short flags
	flag.StringVar(&config.Namespace, "n", "", "Kubernetes namespace")
	flag.StringVar(&config.ApplicationID, "a", "", "Application ID")
	flag.StringVar(&config.ScopeID, "s", "", "Scope ID")
	flag.StringVar(&config.DeploymentID, "d", "", "Deployment ID")
	flag.IntVar(&config.Limit, "l", types.DefaultLimit, "Maximum log entries")
	flag.StringVar(&config.NextPageToken, "t", "", "Pagination token")
	flag.StringVar(&config.FilterPattern, "f", "", "Filter pattern")
	flag.StringVar(&config.InstanceID, "i", "", "Instance ID")

	flag.Parse()
	return config
}