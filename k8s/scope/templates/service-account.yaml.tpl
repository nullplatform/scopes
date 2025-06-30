apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .service_account_name }}
  namespace: {{ .k8s_namespace }}
  annotations:
    eks.amazonaws.com/role-arn: {{ .role_arn }}
  labels:
    nullplatform: "true"
    account: {{ .account.slug }}
    account_id: "{{ .account.id }}"
    application: {{ .application.slug }}
    application_id: "{{ .application.id }}"
    namespace: {{ .namespace.slug }}
    namespace_id: "{{ .namespace.id }}"
    scope: {{ .scope.slug }}
    scope_id: "{{ .scope.id }}"
{{- $global := index .k8s_modifiers "global" }}
{{- if $global }}
  {{- $labels := index $global "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
{{- $service_account := index .k8s_modifiers "service_account" }}
{{- if $service_account }}
  {{- $labels := index $service_account "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
automountServiceAccountToken: true