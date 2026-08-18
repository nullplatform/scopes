package main

import (
	"encoding/json"
	"fmt"
	"os"

	corev1 "k8s.io/api/core/v1"

	"kube-logger-go/internal/config"
	"kube-logger-go/internal/kubernetes"
	"kube-logger-go/internal/logs"
	"kube-logger-go/internal/pagination"
	"kube-logger-go/internal/types"
)

func main() {
	cfg := config.ParseFlags()

	// Validate required parameters
	if cfg.Namespace == "" {
		fmt.Fprintf(os.Stderr, "Error: namespace is required\n")
		os.Exit(1)
	}

	// Window bounds are compared against log timestamps as strings, so a
	// malformed one would be ignored rather than rejected, and the query would
	// quietly answer a wider range than the caller asked for.
	for flagName, bound := range map[string]string{"start-time": cfg.StartTime, "end-time": cfg.EndTime} {
		if bound != "" && !logs.ValidTimestamp(bound) {
			fmt.Fprintf(os.Stderr, "Error: %s must be RFC3339, e.g. 2026-08-17T23:59:59Z (got %q)\n", flagName, bound)
			os.Exit(1)
		}
	}

	// Create Kubernetes client
	clientset, err := kubernetes.NewClient()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create Kubernetes client: %v\n", err)
		os.Exit(1)
	}

	// Get all pods or a specific pod
	var pods []corev1.Pod
    if cfg.InstanceID != "" {
    	pod, err := kubernetes.GetPod(clientset, cfg.Namespace, cfg.InstanceID)
    	if err != nil {
    		fmt.Fprintf(os.Stderr, "Failed to get pod: %v\n", err)
    		os.Exit(1)
    	}
    	if pod != nil {
    		pods = []corev1.Pod{*pod}
    	} else {
    		pods = []corev1.Pod{}
    	}
    } else {
    	var err error
    	pods, err = kubernetes.GetPods(clientset, cfg)
    	if err != nil {
    		fmt.Fprintf(os.Stderr, "Failed to get pods: %v\n", err)
    		os.Exit(1)
    	}
    }

	if len(pods) == 0 {
		outputEmptyResponse()
		return
	}

	// Get logs concurrently from all pods
	fetcher := logs.NewFetcher(clientset)
	allLogs := fetcher.FetchConcurrently(pods, cfg)

	// Order the entries, cut them to the limit and record where the cut landed. The
	// incoming cursors go in so that a pod which contributed nothing to this page keeps
	// the one it already had instead of restarting from start_time.
	allLogs, token := pagination.Page(allLogs, cfg.Limit, pagination.DecodeToken(cfg.NextPageToken))

	response := types.Response{
		Results:       allLogs,
		NextPageToken: token,
	}

	output, _ := json.Marshal(response)
	fmt.Println(string(output))
}

func outputEmptyResponse() {
	response := types.Response{
		Results:       []types.LogEntry{},
		NextPageToken: "",
	}
	output, _ := json.Marshal(response)
	fmt.Println(string(output))
}