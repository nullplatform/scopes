{{- if eq .scope.capabilities.scaling_type "auto" }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-d-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: d-{{ .scope.id }}-{{ .deployment.id }}
  minReplicas: {{ .scope.capabilities.autoscaling.min_replicas }}
  maxReplicas: {{ .scope.capabilities.autoscaling.max_replicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .scope.capabilities.autoscaling.target_cpu_utilization }}
{{- end }}