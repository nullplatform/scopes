package kubernetes

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"

	"kube-logger-go/internal/types"
)

// NewClient creates and returns a Kubernetes clientset
func NewClient() (*kubernetes.Clientset, error) {
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

// buildLabelSelector builds a label selector string based on the config
func buildLabelSelector(config types.Config) string {
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

// GetPods retrieves pods based on the configuration
func GetPods(clientset *kubernetes.Clientset, config types.Config) ([]corev1.Pod, error) {
	ctx := context.Background()
	selector := buildLabelSelector(config)

	podList, err := clientset.CoreV1().Pods(config.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: selector,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list pods: %v", err)
	}

	return podList.Items, nil
}