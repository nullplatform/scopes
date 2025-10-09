package logs

import (
	"bufio"
	"context"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"

	"kube-logger-go/internal/pagination"
	"kube-logger-go/internal/types"
)

// Fetcher handles log fetching operations
type Fetcher struct {
	clientset *kubernetes.Clientset
}

// NewFetcher creates a new log fetcher instance
func NewFetcher(clientset *kubernetes.Clientset) *Fetcher {
	return &Fetcher{
		clientset: clientset,
	}
}

// FetchConcurrently fetches logs from multiple pods concurrently
func (f *Fetcher) FetchConcurrently(pods []corev1.Pod, config types.Config) []types.LogEntry {
	if len(pods) == 0 {
		return []types.LogEntry{}
	}

	// Calculate logs per pod
	podLimit := config.Limit / len(pods)
	if podLimit < types.MinLogsPerPod {
		podLimit = types.MinLogsPerPod
	}

	// Decode pagination token
	lastReadTimes := pagination.DecodeToken(config.NextPageToken)

	allLogs := make([]types.LogEntry, 0, config.Limit)
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
            logCh := make(chan string, 100)
            go func() {
                defer close(logCh)
                f.streamPodLogs(&p, config.Namespace, sinceTime, int64(podLimit*3072), logCh)
            }()

            processor := NewProcessor()
            processedLogs := processor.ProcessLinesFromChannel(logCh, config.FilterPattern, p.Name, podUID, getLastReadTime(podUID, lastReadTimes))

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

// getPodLogs retrieves logs from a specific pod
func (f *Fetcher) getPodLogs(pod *corev1.Pod, namespace, sinceTime string, limitBytes int64) string {
	ctx := context.Background()

	opts := &corev1.PodLogOptions{
		Container:  types.DefaultContainerName,
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

	req := f.clientset.CoreV1().Pods(namespace).GetLogs(pod.Name, opts)
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

func (f *Fetcher) streamPodLogs(pod *corev1.Pod, namespace, sinceTime string, limitBytes int64, logCh chan<- string) {
    ctx := context.Background()
    opts := &corev1.PodLogOptions{
        Container:  types.DefaultContainerName,
        Timestamps: true,
        LimitBytes: &limitBytes,
    }
    if sinceTime != "" {
        if sinceTimeObj, err := time.Parse(time.RFC3339, sinceTime); err == nil {
            metaTime := metav1.NewTime(sinceTimeObj)
            opts.SinceTime = &metaTime
        }
    }
    req := f.clientset.CoreV1().Pods(namespace).GetLogs(pod.Name, opts)
    podLogs, err := req.Stream(ctx)
    if err != nil {
        return
    }
    defer podLogs.Close()

    scanner := bufio.NewScanner(podLogs)
    for scanner.Scan() {
        logCh <- scanner.Text()
    }
}

// determineSinceTime determines the appropriate since time for a pod
func determineSinceTime(podUID string, lastReadTimes map[string]string, startTime string) string {
	if lastTime, exists := lastReadTimes[podUID]; exists && lastTime != "" && lastTime != "null" {
		return lastTime
	}
	return startTime
}

// getLastReadTime retrieves the last read time for a specific pod
func getLastReadTime(podUID string, lastReadTimes map[string]string) string {
	if lastTime, exists := lastReadTimes[podUID]; exists {
		return lastTime
	}
	return ""
}