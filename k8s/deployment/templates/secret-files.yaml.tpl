{{- $hasFile := false -}}
{{- if .parameters.results -}}
  {{- range .parameters.results -}}
    {{- if and (eq .type "file") (gt (len .values) 0) -}}
      {{- $hasFile = true -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $hasFile -}}
apiVersion: v1
kind: Secret
immutable: true
metadata:
  name: s-{{ .scope.id }}-d-{{ .deployment.id }}-files
  namespace: {{ .k8s_namespace }}
  labels:
    nullplatform: "true"
    account: {{ .account.slug }}
    account_id: "{{ .account.id }}"
    namespace: {{ .namespace.slug }}
    namespace_id: "{{ .namespace.id }}"
    application: {{ .application.slug }}
    application_id: "{{ .application.id }}"
    scope: {{ .scope.slug }}
    scope_id: "{{ .scope.id }}"
    deployment_id: "{{ .deployment.id }}"
{{- $global := index .k8s_modifiers "global" }}
{{- if $global }}
  {{- $labels := index $global "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
{{- $secret := index .k8s_modifiers "secret" }}
{{- if $secret }}
  {{- $labels := index $secret "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
data:
{{- range .parameters.results }}
  {{- if and (eq .type "file") (gt (len .values) 0) }}
    {{- $key := .name | strings.ToLower | regexp.Replace "[^a-z0-9]+" "-" | strings.Trim "-" }}
  {{ printf "app-file-%s" $key }}: {{ index .values 0 "value" | regexp.Replace "^data:[^;]+;base64," "" }}
  {{- end }}
{{- end }}
type: Opaque
{{- end -}}
