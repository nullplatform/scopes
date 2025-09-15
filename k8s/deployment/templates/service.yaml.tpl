apiVersion: v1
kind: Service
metadata:
  name: d-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
  labels:
    name: d-{{ .scope.id }}-{{ .deployment.id }}
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
{{- $service := index .k8s_modifiers "service" }}
{{- if $service }}
  {{- $labels := index $service "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: d-{{ .scope.id }}
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '{{ .scope.capabilities.health_check.period_seconds }}'
    alb.ingress.kubernetes.io/healthcheck-path: {{ .scope.capabilities.health_check.path }}
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '{{ .scope.capabilities.health_check.timeout_seconds }}'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/success-codes: 200-299
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '3'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
{{- $global := index .k8s_modifiers "global" }}
{{- if $global }}
  {{- $annotations := index $global "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
{{- $service := index .k8s_modifiers "service" }}
{{- if $service }}
  {{- $annotations := index $service "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
spec:
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 80
  selector:
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
  type: ClusterIP
  sessionAffinity: None
  ipFamilies:
    - IPv4
  ipFamilyPolicy: SingleStack
  internalTrafficPolicy: Cluster

{{ if .scope.capabilities.additional_ports }}
{{ range .scope.capabilities.additional_ports }}
{{ if eq .type "HTTP" }}
---
apiVersion: v1
kind: Service
metadata:
  name: d-{{ $.scope.id }}-{{ $.deployment.id }}-http-{{ .port }}
  namespace: {{ $.k8s_namespace }}
  labels:
    name: d-{{ $.scope.id }}-{{ $.deployment.id }}-http-{{ .port }}
    app.kubernetes.io/part-of: {{ $.namespace.slug }}-{{ $.application.slug }}
    app.kubernetes.io/component: application
    app.kubernetes.io/instance: {{ $.scope.slug }}
    app.kubernetes.io/name: {{ $.scope.slug }}
{{- $global := index $.k8s_modifiers "global" }}
{{- if $global }}
  {{- $labels := index $global "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
{{- $service := index $.k8s_modifiers "service" }}
{{- if $service }}
  {{- $labels := index $service "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: d-{{ $.scope.id }}-http-{{ .port }}
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '{{ $.scope.capabilities.health_check.period_seconds }}'
    alb.ingress.kubernetes.io/healthcheck-path: {{ $.scope.capabilities.health_check.path }}
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '{{ $.scope.capabilities.health_check.timeout_seconds }}'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/success-codes: 200-299
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '3'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
{{- $global := index $.k8s_modifiers "global" }}
{{- if $global }}
  {{- $annotations := index $global "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
{{- $service := index $.k8s_modifiers "service" }}
{{- if $service }}
  {{- $annotations := index $service "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
spec:
  ports:
    - protocol: TCP
      port: {{ .port }}
      targetPort: {{ .port }}
  selector:
    nullplatform: "true"
    account: {{ $.account.slug }}
    account_id: "{{ $.account.id }}"
    namespace: {{ $.namespace.slug }}
    namespace_id: "{{ $.namespace.id }}"
    application: {{ $.application.slug }}
    application_id: "{{ $.application.id }}"
    scope: {{ $.scope.slug }}
    scope_id: "{{ $.scope.id }}"
    deployment_id: "{{ $.deployment.id }}"
  type: ClusterIP
  sessionAffinity: None
  ipFamilies:
    - IPv4
  ipFamilyPolicy: SingleStack
  internalTrafficPolicy: Cluster
{{ else if eq .type "GRPC" }}
---
apiVersion: v1
kind: Service
metadata:
  name: d-{{ $.scope.id }}-{{ $.deployment.id }}-grpc-{{ .port }}
  namespace: {{ $.k8s_namespace }}
  labels:
    name: d-{{ $.scope.id }}-{{ $.deployment.id }}-grpc-{{ .port }}
    app.kubernetes.io/part-of: {{ $.namespace.slug }}-{{ $.application.slug }}
    app.kubernetes.io/component: application
    app.kubernetes.io/instance: {{ $.scope.slug }}
    app.kubernetes.io/name: {{ $.scope.slug }}
{{- $global := index $.k8s_modifiers "global" }}
{{- if $global }}
  {{- $labels := index $global "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
{{- $service := index $.k8s_modifiers "service" }}
{{- if $service }}
  {{- $labels := index $service "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: d-{{ $.scope.id }}-grpc-{{ .port }}
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '{{ $.scope.capabilities.health_check.period_seconds }}'
    alb.ingress.kubernetes.io/healthcheck-path: /grpc.health.v1.Health/Check
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '{{ $.scope.capabilities.health_check.timeout_seconds }}'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/success-codes: '0'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '3'
    alb.ingress.kubernetes.io/backend-protocol-version: GRPC
    alb.ingress.kubernetes.io/load-balancer-attributes: routing.http2.enabled=true
{{- $global := index $.k8s_modifiers "global" }}
{{- if $global }}
  {{- $annotations := index $global "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
{{- $service := index $.k8s_modifiers "service" }}
{{- if $service }}
  {{- $annotations := index $service "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
spec:
  ports:
    - protocol: TCP
      port: {{ .port }}
      targetPort: {{ 50052 }}
  selector:
    nullplatform: "true"
    account: {{ $.account.slug }}
    account_id: "{{ $.account.id }}"
    namespace: {{ $.namespace.slug }}
    namespace_id: "{{ $.namespace.id }}"
    application: {{ $.application.slug }}
    application_id: "{{ $.application.id }}"
    scope: {{ $.scope.slug }}
    scope_id: "{{ $.scope.id }}"
    deployment_id: "{{ $.deployment.id }}"
  type: ClusterIP
  sessionAffinity: None
  ipFamilies:
    - IPv4
  ipFamilyPolicy: SingleStack
  internalTrafficPolicy: Cluster
{{ end }}
{{ end }}
{{ end }}