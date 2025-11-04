apiVersion: networking.istio.io/v1beta1
kind: VirtualService
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
  hosts:
    - {{ .scope.domain }}
{{- range .scope.domains }}
    - {{ .name }}
{{- end }}
  gateways:
    - {{ .gateway_name }}
  http:
    - match:
        - uri:
            prefix: "/"
      route:
        # Blue deployment (old version)
        - destination:
            host: d-{{ .scope.id }}-{{ .blue_deployment_id }}
            port:
              number: 8080
          weight: {{ sub 100 .deployment.strategy_data.desired_switched_traffic }}
        # Green deployment (new version)
        - destination:
            host: d-{{ .scope.id }}-{{ .deployment.id }}
            port:
              number: 8080
          weight: {{ .deployment.strategy_data.desired_switched_traffic }}