package logs

import (
	"bufio"
	"context"
	"io"
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

// FetchConcurrently reads every pod concurrently and returns one scan per pod.
func (f *Fetcher) FetchConcurrently(pods []corev1.Pod, config types.Config) []types.PodScan {
	if len(pods) == 0 {
		return []types.PodScan{}
	}

	// Calculate logs per pod
	podLimit := config.Limit / len(pods)
	if podLimit < types.MinLogsPerPod {
		podLimit = types.MinLogsPerPod
	}

	// Decode pagination token
	lastReadTimes := pagination.DecodeToken(config.NextPageToken)

	scans := make([]types.PodScan, 0, len(pods))
	var mu sync.Mutex
	var wg sync.WaitGroup

	// Fetch logs from each pod concurrently
	for _, pod := range pods {
		wg.Add(1)
		go func(p corev1.Pod) {
			defer wg.Done()

			podUID := string(p.UID)
			sinceTime := determineSinceTime(podUID, lastReadTimes, config.StartTime)
			stream := func(ctx context.Context, limitBytes int64, out chan<- string) bool {
				return f.streamPodLogs(ctx, &p, config.Namespace, sinceTime, limitBytes, out)
			}

			scan := scanPod(stream, int64(podLimit*3072), config.FilterPattern, p.Name, podUID, getLastReadTime(podUID, lastReadTimes), config.EndTime)

			mu.Lock()
			scans = append(scans, scan)
			mu.Unlock()
		}(pod)
	}

	wg.Wait()
	return scans
}

// maxReadDoublings bounds how many times scanPod doubles a read that made no progress.
const maxReadDoublings = 6

// scanPod runs one pod's read. stream feeds its lines, up to limitBytes, and reports whether
// it stopped at the limit; the processor applies the cursor, end_time and the filter. The
// Kubernetes API resumes at the cursor's second, not at the cursor, so a second that logged
// more than the limit fills a read with lines already delivered. Such a read is repeated with
// twice the room: returning it would hand back the same token for ever.
func scanPod(stream func(ctx context.Context, limitBytes int64, out chan<- string) (truncated bool), limitBytes int64, filterPattern, podName, podUID, lastReadTime, endTime string) types.PodScan {
	for doublings := 0; ; doublings++ {
		scan, truncated := readPod(stream, limitBytes, filterPattern, podName, podUID, lastReadTime, endTime)
		madeProgress := scan.ScannedUpTo != "" || scan.Done || !truncated
		if madeProgress || doublings == maxReadDoublings {
			return scan
		}
		limitBytes *= 2
	}
}

// readPod is one read of one pod. The pod is done when the read reached end_time or its log
// ended before the byte limit.
func readPod(stream func(ctx context.Context, limitBytes int64, out chan<- string) (truncated bool), limitBytes int64, filterPattern, podName, podUID, lastReadTime, endTime string) (types.PodScan, bool) {
	// Cancelling releases the producer when the processor stops at the end of the window.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	logCh := make(chan string, 100)
	truncatedCh := make(chan bool, 1)
	go func() {
		defer close(logCh)
		truncatedCh <- stream(ctx, limitBytes, logCh)
	}()

	scan := NewProcessor().ProcessLinesFromChannel(logCh, filterPattern, podName, podUID, lastReadTime, endTime)
	if scan.Done {
		return scan, false
	}

	// The channel closed, so the producer already reported how it ended.
	truncated := <-truncatedCh
	scan.Done = !truncated
	return scan, truncated
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

// streamPodLogs streams a pod's log from sinceTime, up to limitBytes, and reports whether
// the read stopped at the byte limit.
func (f *Fetcher) streamPodLogs(ctx context.Context, pod *corev1.Pod, namespace, sinceTime string, limitBytes int64, logCh chan<- string) bool {
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
		return false
	}
	defer podLogs.Close()

	return forwardLines(ctx, podLogs, limitBytes, logCh)
}

// forwardLines sends each line of r to out, without its line break, and reports whether r
// ended at the byte limit. Kubernetes cuts the log at the limit wherever it falls, so a last
// line with no line break is held back: the next page reads it whole, from a cursor that
// stops before it. It is sent anyway when it is all the read got, or a line longer than the
// limit would stop the cursor for good.
func forwardLines(ctx context.Context, r io.Reader, limitBytes int64, out chan<- string) bool {
	reader := bufio.NewReader(r)
	var read int64
	sent := false

	for {
		line, err := reader.ReadString('\n')
		read += int64(len(line))
		truncated := read >= limitBytes

		if err != nil {
			if line != "" && (!truncated || !sent) {
				send(ctx, out, strings.TrimRight(line, "\r\n"))
			}
			return truncated
		}

		if !send(ctx, out, strings.TrimRight(line, "\r\n")) {
			return truncated
		}
		sent = true
	}
}

func send(ctx context.Context, out chan<- string, line string) bool {
	select {
	case out <- line:
		return true
	case <-ctx.Done():
		return false
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
