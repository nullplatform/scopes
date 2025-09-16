apiVersion: v1
kind: Secret
immutable: true
metadata:
  name: s-{{ .scope.id }}-d-{{ .deployment.id }}
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
{{- if .parameters.results }}
  {{- range .parameters.results }}
    {{- if and (eq .type "environment") }}
      {{- if gt (len .values) 0 }}
  {{ .variable }}: {{ index .values 0 "value" | base64.Encode }}
      {{- end }}
    {{- end }}
    {{- if and (eq .type "file") }}
      {{- if gt (len .values) 0 }}
  {{ printf "app-data-%s" (filepath.Base .destination_path) }}: {{ index .values 0 "value" | strings.TrimPrefix "data:application/json;base64," }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
  NP_ACCOUNT: {{ .account.slug | base64.Encode }}
  NP_APPLICATION: {{ .application.slug | base64.Encode }}
  NP_DEPLOYMENT_ID: {{ .deployment.id | base64.Encode }}
  {{- range $name, $value := .scope.dimensions }}
  NP_DIMENSION_{{- strings.ToUpper $name }}: {{ $value | base64.Encode }}
  {{- end }}
  NP_DOMAIN: {{ .scope.domain | base64.Encode }}
  NP_NAMESPACE: {{ .namespace.slug | base64.Encode }}
  NP_RELEASE_SEMVER: {{ .release.semver | base64.Encode }}
  NP_SCOPE: {{ .scope.slug | base64.Encode }}
  {{- if .datadog_config }}
  NP_LOGS_PROVIDER: {{ .datadog_config.np_logs_provider | base64.Encode }}
  NP_DATADOG_APIKEY: {{ .datadog_config.np_datadog_apikey | base64.Encode }}
  NP_DATADOG_LOGS_URL: {{ .datadog_config.np_datadog_logs_url | base64.Encode }}
  NP_DATADOG_SERVICE: {{ printf "%s-%s-%s-%s" .account.slug .namespace.slug .application.slug .scope.slug | base64.Encode }}
  NP_DATADOG_TAGS: {{ printf "account:%s,namespace:%s,application:%s,scope:%s,scope_id:%s,deployment_id:%s,account_id:%s,namespace_id:%s,application_id:%s" .account.slug .namespace.slug .application.slug .scope.slug .scope.id .deployment.id .account.id .namespace.id .application.id | base64.Encode }}
  {{- end }}
type: Opaque