apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k-8-s-{{ .scope.slug }}-{{ .scope.id }}-{{ .ingress_visibility }}
  namespace: {{ .k8s_namespace }}
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
{{- $ingress := index .k8s_modifiers "ingress" }}
{{- if $ingress }}
  {{- $labels := index $ingress "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
  annotations:
    alb.ingress.kubernetes.io/actions.response-404: >-
      {"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"404","messageBody":"404
        scope not found or has not been deployed yet"}}
    alb.ingress.kubernetes.io/group.name: {{ .alb_name }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/load-balancer-name: {{ .alb_name }}
    alb.ingress.kubernetes.io/scheme: {{ .ingress_visibility }}
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/target-type: ip
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
  ingressClassName: alb
  rules:
    - host: {{ .scope.domain }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: response-404
                port:
                  name: use-annotation