apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
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
  hostnames:
    - {{ .scope.domain }}
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: {{ .gateway_name }}
      namespace: gateways
  rules:
    - backendRefs:
        # Blue deployment (old version)
        - group: ""
          kind: Service
          name: d-{{ .scope.id }}-{{ .blue_deployment_id }}
          port: 8080
          weight: {{ sub 100 .deployment.strategy_data.desired_switched_traffic }}
        # Green deployment (new version)
        - group: ""
          kind: Service
          name: d-{{ .scope.id }}-{{ .deployment.id }}
          port: 8080
          weight: {{ .deployment.strategy_data.desired_switched_traffic }}
      matches:
        - path:
            type: PathPrefix
            value: /