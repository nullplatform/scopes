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
			lastReadTime := getLastReadTime(podUID, lastReadTimes)
			limitBytes := int64(podLimit * 3072)

			// Previous-container logs (the crashed instance) are only pulled
			// on the first page for this pod. Once a pagination cursor exists
			// for the pod, prior-instance lines either fall before the cursor
			// or were already returned, so re-fetching them every page would
			// waste bandwidth on lines the processor would discard anyway.
			logCh := make(chan string, 200)
			go func() {
				defer close(logCh)
				if lastReadTime == "" && hasPreviousInstance(&p) {
					f.streamPodLogs(&p, config.Namespace, sinceTime, limitBytes, true, logCh)
				}
				f.streamPodLogs(&p, config.Namespace, sinceTime, limitBytes, false, logCh)
			}()

			processor := NewProcessor()
			processedLogs := processor.ProcessLinesFromChannel(logCh, config.FilterPattern, p.Name, podUID, lastReadTime)

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

func (f *Fetcher) streamPodLogs(pod *corev1.Pod, namespace, sinceTime string, limitBytes int64, previous bool, logCh chan<- string) {
	ctx := context.Background()
	opts := &corev1.PodLogOptions{
		Container:  types.DefaultContainerName,
		Timestamps: true,
		LimitBytes: &limitBytes,
		Previous:   previous,
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
		// Expected when previous=true and no prior container instance exists
		// (e.g. fresh pod that has never restarted). Swallow silently — the
		// live-log fetch on the next call still runs.
		return
	}
	defer podLogs.Close()

	scanner := bufio.NewScanner(podLogs)
	for scanner.Scan() {
		logCh <- scanner.Text()
	}
}

// hasPreviousInstance reports whether the pod's application container has a
// recoverable previous instance (i.e. it has restarted at least once or has a
// terminated last state). The kubelet retains exactly one prior instance per
// container, so this is the gate for whether `Previous: true` will yield data.
func hasPreviousInstance(pod *corev1.Pod) bool {
	for _, cs := range pod.Status.ContainerStatuses {
		if cs.Name != types.DefaultContainerName {
			continue
		}
		if cs.RestartCount > 0 {
			return true
		}
		if cs.LastTerminationState.Terminated != nil {
			return true
		}
	}
	return false
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
