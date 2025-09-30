{{if eq .pdb_enabled "true"}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pdb-d-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
  labels:
    name: pdb-d-{{ .scope.id }}-{{ .deployment.id }}
    app.kubernetes.io/part-of: {{ .namespace.slug }}-{{ .application.slug }}
    app.kubernetes.io/component: application
    app.kubernetes.io/instance: {{ .scope.slug }}
    app.kubernetes.io/name: {{ .scope.slug }}
{{- $global := index .k8s_modifiers "global" }}
{{- if $global }}
  {{- $labels := index $global "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
{{- $pdb := index .k8s_modifiers "pdb" }}
{{- if $pdb }}
  {{- $labels := index $pdb "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
  annotations:
    nullplatform.com/managed-by: nullplatform
    nullplatform.com/account: {{ .account.slug }}
    nullplatform.com/namespace: {{ .namespace.slug }}
    nullplatform.com/application: {{ .application.slug }}
    nullplatform.com/scope: {{ .scope.slug }}
    nullplatform.com/deployment-id: "{{ .deployment.id }}"
{{- $global := index .k8s_modifiers "global" }}
{{- if $global }}
  {{- $annotations := index $global "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
{{- $pdb := index .k8s_modifiers "pdb" }}
{{- if $pdb }}
  {{- $annotations := index $pdb "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
spec:
  maxUnavailable: {{ .pdb_max_unavailable }}
  selector:
    matchLabels:
      app: d-{{ .scope.id }}-{{ .deployment.id }}
{{- end }}