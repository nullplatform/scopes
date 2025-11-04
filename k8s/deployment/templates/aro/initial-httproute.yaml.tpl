apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: k-8-s-{{ .scope.slug }}-{{ .scope.id }}-{{ .ingress_visibility }}
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
    type: {{ .ingress_visibility }}
{{- $global := index .k8s_modifiers "global" }}
{{- if $global }}
  {{- $labels := index $global "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
{{- $ingress := index .k8s_modifiers "ingress" }}
{{- if $ingress }}
  {{- $labels := index $ingress "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
  annotations:
{{- $global := index .k8s_modifiers "global" }}
{{- if $global }}
  {{- $annotations := index $global "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
{{- $ingress := index .k8s_modifiers "ingress" }}
{{- if $ingress }}
  {{- $annotations := index $ingress "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
spec:
  host: {{ .scope.domain }}
  port:
    targetPort: 80
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: edge
  wildcardPolicy: None
  to:
    kind: Service
    name: d-{{ .scope.id }}-{{ .deployment.id }}