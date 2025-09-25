package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	defaultContainerName = "application"
	defaultLimit        = 100
	minLogsPerPod       = 10
)

type LogEntry struct {
	Message  string  `json:"message"`
	DateTime string  `json:"datetime"`
	Pod      PodInfo `json:"pod"`
}

type PodInfo struct {
	Name string `json:"name"`
	ID   string `json:"id"`
}

type Response struct {
	Results       []LogEntry `json:"results"`
	NextPageToken string     `json:"next_page_token"`
}

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

func main() {
	config := parseFlags()

	// Validate required parameters
	if config.Namespace == "" {
		fmt.Fprintf(os.Stderr, "Error: namespace is required\n")
		os.Exit(1)
	}

	// Create Kubernetes client
	clientset, err := createKubernetesClient()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create Kubernetes client: %v\n", err)
		os.Exit(1)
	}

    // Get pods directly (like the bash script)
    pods, err := getPods(clientset, config)
    if err != nil {
        fmt.Fprintf(os.Stderr, "Failed to get pods: %v\n", err)
        os.Exit(1)
    }
    // Filter pods by instanceID if provided
    if config.InstanceID != "" {
        filteredPods := make([]corev1.Pod, 0, len(pods))
        for _, pod := range pods {
            if pod.Name == config.InstanceID || string(pod.UID) == config.InstanceID {
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
	allLogs := fetchLogsConcurrently(clientset, pods, config)

	// Sort logs by datetime
	sort.Slice(allLogs, func(i, j int) bool {
		return allLogs[i].DateTime < allLogs[j].DateTime
	})

	// Limit results
	if len(allLogs) > config.Limit {
		allLogs = allLogs[:config.Limit]
	}
	if len(allLogs) == 0 {
		allLogs = []LogEntry{}
	}

	// Generate next page token
	token := generateNextPageToken(allLogs)

	response := Response{
		Results:       allLogs,
		NextPageToken: token,
	}

	output, _ := json.Marshal(response)
	fmt.Println(string(output))
}

func parseFlags() Config {
	config := Config{Limit: defaultLimit}

	// Long flags (matching your bash script exactly)
	flag.StringVar(&config.Namespace, "namespace", "", "Kubernetes namespace")
	flag.StringVar(&config.ApplicationID, "application-id", "", "Application ID")
	flag.StringVar(&config.ScopeID, "scope-id", "", "Scope ID")
	flag.StringVar(&config.DeploymentID, "deployment-id", "", "Deployment ID")
	flag.IntVar(&config.Limit, "limit", defaultLimit, "Maximum log entries")
	flag.StringVar(&config.NextPageToken, "next-page-token", "", "Pagination token")
	flag.StringVar(&config.FilterPattern, "filter", "", "Filter pattern")
	flag.StringVar(&config.StartTime, "start-time", "", "Start time (ISO format)")
	flag.StringVar(&config.InstanceID, "instance-id", "", "Instance ID")

	// Short flags
	flag.StringVar(&config.Namespace, "n", "", "Kubernetes namespace")
	flag.StringVar(&config.ApplicationID, "a", "", "Application ID")
	flag.StringVar(&config.ScopeID, "s", "", "Scope ID")
	flag.StringVar(&config.DeploymentID, "d", "", "Deployment ID")
	flag.IntVar(&config.Limit, "l", defaultLimit, "Maximum log entries")
	flag.StringVar(&config.NextPageToken, "t", "", "Pagination token")
	flag.StringVar(&config.FilterPattern, "f", "", "Filter pattern")
	flag.StringVar(&config.InstanceID, "i", "", "Instance ID")

	flag.Parse()
	return config
}

func createKubernetesClient() (*kubernetes.Clientset, error) {
	var config *rest.Config
	var err error

	// Try in-cluster config first
	if config, err = rest.InClusterConfig(); err != nil {
		// Fall back to kubeconfig
		kubeconfig := clientcmd.NewDefaultClientConfigLoadingRules().GetDefaultFilename()
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err != nil {
			return nil, err
		}
	}

	return kubernetes.NewForConfig(config)
}

func buildLabelSelector(config Config) string {
	selector := "nullplatform=true"
	if config.ApplicationID != "" {
		selector += ",application_id=" + config.ApplicationID
	}
	if config.ScopeID != "" {
		selector += ",scope_id=" + config.ScopeID
	}
	if config.DeploymentID != "" {
		selector += ",deployment_id=" + config.DeploymentID
	}
	return selector
}

func getPods(clientset *kubernetes.Clientset, config Config) ([]corev1.Pod, error) {
	ctx := context.Background()
	selector := buildLabelSelector(config)

	// Get pods directly - just like the bash script does
	podList, err := clientset.CoreV1().Pods(config.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: selector,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list pods: %v", err)
	}

	return podList.Items, nil
}

func fetchLogsConcurrently(clientset *kubernetes.Clientset, pods []corev1.Pod, config Config) []LogEntry {
	if len(pods) == 0 {
		return []LogEntry{}
	}

	// Calculate logs per pod
	podLimit := config.Limit / len(pods)
	if podLimit < minLogsPerPod {
		podLimit = minLogsPerPod
	}

	// Decode pagination token
	lastReadTimes := decodeToken(config.NextPageToken)

	allLogs := make([]LogEntry, 0, config.Limit)
	var mu sync.Mutex
	var wg sync.WaitGroup

	// Fetch logs from each pod concurrently
	for _, pod := range pods {
		wg.Add(1)
		go func(p corev1.Pod) {
			defer wg.Done()

			podUID := string(p.UID)

			// Determine since time for this pod
			sinceTime := determineSinceTime(podUID, lastReadTimes, config.StartTime)

			// Get pod logs
			logs := getPodLogs(clientset, &p, config.Namespace, sinceTime, int64(podLimit*3072))

			// Process logs
			processedLogs := processLogLines(logs, config.FilterPattern, p.Name, podUID, getLastReadTime(podUID, lastReadTimes))

			if len(processedLogs) > 0 {
				mu.Lock()
				allLogs = append(allLogs, processedLogs...)
				mu.Unlock()
			}
		}(pod)
	}

	wg.Wait()
	return allLogs
}

func getPodLogs(clientset *kubernetes.Clientset, pod *corev1.Pod, namespace, sinceTime string, limitBytes int64) string {
	ctx := context.Background()

	opts := &corev1.PodLogOptions{
		Container:  defaultContainerName,
		Timestamps: true,
		LimitBytes: &limitBytes,
	}

	// Add since time if provided
	if sinceTime != "" {
		if sinceTimeObj, err := time.Parse(time.RFC3339, sinceTime); err == nil {
			metaTime := metav1.NewTime(sinceTimeObj)
			opts.SinceTime = &metaTime
		}
	}

	req := clientset.CoreV1().Pods(namespace).GetLogs(pod.Name, opts)
	podLogs, err := req.Stream(ctx)
	if err != nil {
		return ""
	}
	defer podLogs.Close()

	var logContent strings.Builder
	scanner := bufio.NewScanner(podLogs)
	for scanner.Scan() {
		logContent.WriteString(scanner.Text())
		logContent.WriteString("\n")
	}

	return logContent.String()
}

func isValidTimestamp(timestamp string) bool {
	// Check RFC3339 format (e.g., 2025-09-04T15:24:34.944759409Z)
	_, err := time.Parse(time.RFC3339Nano, timestamp)
	if err != nil {
		_, err = time.Parse(time.RFC3339, timestamp)
	}
	return err == nil
}

func processLogLines(logs, filterPattern, podName, podUID, lastReadTime string) []LogEntry {
	if logs == "" {
		return []LogEntry{}
	}

	var entries []LogEntry
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
		if !isValidTimestamp(timestamp) {
			continue
		}

		// Duplicate detection logic (matching bash script behavior)
		if lastReadTime != "" && lastReadTime != "null" && lastReadTime != "empty" {
			// If timestamp is same or older than last read time, skip it
			if timestamp <= lastReadTime {
				continue
			}
		}

		// Apply filter if specified
		if filterPattern != "" && !strings.Contains(line, filterPattern) {
			continue
		}

		entry := LogEntry{
			Message:  message,
			DateTime: timestamp,
			Pod: PodInfo{
				Name: podName,
				ID:   podUID,
			},
		}

		entries = append(entries, entry)
	}

	return entries
}

func decodeToken(token string) map[string]string {
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

func determineSinceTime(podUID string, lastReadTimes map[string]string, startTime string) string {
	if lastTime, exists := lastReadTimes[podUID]; exists && lastTime != "" && lastTime != "null" {
		return lastTime
	}
	return startTime
}

func getLastReadTime(podUID string, lastReadTimes map[string]string) string {
	if lastTime, exists := lastReadTimes[podUID]; exists {
		return lastTime
	}
	return ""
}

func generateNextPageToken(logs []LogEntry) string {
	if len(logs) == 0 {
		return ""
	}

	tokenData := make(map[string]string)
	for _, entry := range logs {
		tokenData[entry.Pod.ID] = entry.DateTime
	}

	return encodeToken(tokenData)
}

func outputEmptyResponse() {
	response := Response{
		Results:       []LogEntry{},
		NextPageToken: "",
	}
	output, _ := json.Marshal(response)
	fmt.Println(string(output))
}
