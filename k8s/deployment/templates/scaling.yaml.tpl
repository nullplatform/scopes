{{if or (eq .scope.capabilities.scaling_type "autoscaling") (eq .scope.capabilities.scaling_type "auto")}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-d-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
  labels:
    name: d-{{ .scope.id }}-{{ .deployment.id }}
    app.kubernetes.io/part-of: {{ .namespace.slug }}
    account: {{ .account.slug }}
    account_id: "{{ .account.id }}"
    namespace: {{ .namespace.slug }}
    namespace_id: "{{ .namespace.id }}"
    application: {{ .application.slug }}
    application_id: "{{ .application.id }}"
    scope: {{ .scope.slug }}
    scope_id: "{{ .scope.id }}"
    deployment_id: "{{ .deployment.id }}"
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
    {{- if and (has .scope.capabilities.autoscaling "target_memory_enabled") (eq .scope.capabilities.autoscaling.target_memory_enabled true) }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .scope.capabilities.autoscaling.target_memory_utilization }}
    {{- end }}
{{- end }}