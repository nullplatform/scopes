package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"

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

	// Create Kubernetes client
	clientset, err := kubernetes.NewClient()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create Kubernetes client: %v\n", err)
		os.Exit(1)
	}

	// Get pods
	pods, err := kubernetes.GetPods(clientset, cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to get pods: %v\n", err)
		os.Exit(1)
	}

	// Filter pods by instanceID if provided
	if cfg.InstanceID != "" {
		filteredPods := make([]corev1.Pod, 0, len(pods))
		for _, pod := range pods {
			if pod.Name == cfg.InstanceID || string(pod.UID) == cfg.InstanceID {
				filteredPods = append(filteredPods, pod)
			}
		}
		pods = filteredPods
	}

	if len(pods) == 0 {
		outputEmptyResponse()
		return
	}

	// Get logs concurrently from all pods
	fetcher := logs.NewFetcher(clientset)
	allLogs := fetcher.FetchConcurrently(pods, cfg)

	// Sort logs by datetime
	sort.Slice(allLogs, func(i, j int) bool {
		return allLogs[i].DateTime < allLogs[j].DateTime
	})

	// Limit results
	if len(allLogs) > cfg.Limit {
		allLogs = allLogs[:cfg.Limit]
	}
	if len(allLogs) == 0 {
		allLogs = []types.LogEntry{}
	}

	// Generate next page token
	token := pagination.GenerateToken(allLogs)

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