# Always create the default HTTP Ingress for port 8080
apiVersion: networking.k8s.io/v1
kind: Ingress
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
  annotations:
    alb.ingress.kubernetes.io/actions.bg-deployment: '{"type":"fixed-response","fixedResponseConfig":{"contentType":"application/json","statusCode":"503","messageBody":"{\"status\":503}"}}'
    alb.ingress.kubernetes.io/actions.response-404: '{"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"404","messageBody":"404 scope not found or has not been deployed yet"}}'
    alb.ingress.kubernetes.io/group.name: k8s-nullplatform-{{ .ingress_visibility }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/load-balancer-name: k8s-nullplatform-{{ .ingress_visibility }}
    alb.ingress.kubernetes.io/scheme: {{ .ingress_visibility }}
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/target-node-labels: account={{ .account.slug }},namespace={{ .namespace.slug }},application={{ .application.slug }},account_id={{ .account.id }},namespace_id={{ .namespace.id }},application_id={{ .application.id }},scope={{ .scope.slug }},scope_id={{ .scope.id }},nullplatform=true
    alb.ingress.kubernetes.io/target-type: ip
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
                name: d-{{ .scope.id }}-{{ .deployment.id }}-http
                port:
                  number: 8080

{{ if .scope.capabilities.additional_ports }}
{{ range .scope.capabilities.additional_ports }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k-8-s-{{ $.scope.slug }}-{{ $.scope.id }}-{{ if eq .type "HTTP" }}http{{ else }}grpc{{ end }}-{{ .port }}-{{ $.ingress_visibility }}
  namespace: {{ $.k8s_namespace }}
  labels:
    nullplatform: "true"
    account: {{ $.account.slug }}
    account_id: "{{ $.account.id }}"
    namespace: {{ $.namespace.slug }}
    namespace_id: "{{ $.namespace.id }}"
    application: {{ $.application.slug }}
    application_id: "{{ $.application.id }}"
    scope: {{ $.scope.slug }}
    scope_id: "{{ $.scope.id }}"
  annotations:
    alb.ingress.kubernetes.io/actions.bg-deployment: '{"type":"fixed-response","fixedResponseConfig":{"contentType":"application/json","statusCode":"503","messageBody":"{\"status\":503}"}}'
    alb.ingress.kubernetes.io/actions.response-404: '{"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"404","messageBody":"404 scope not found or has not been deployed yet"}}'
    alb.ingress.kubernetes.io/group.name: k8s-nullplatform-{{ $.ingress_visibility }}
    alb.ingress.kubernetes.io/load-balancer-name: k8s-nullplatform-{{ $.ingress_visibility }}
    alb.ingress.kubernetes.io/scheme: {{ $.ingress_visibility }}
    alb.ingress.kubernetes.io/target-node-labels: account={{ $.account.slug }},namespace={{ $.namespace.slug }},application={{ $.application.slug }},account_id={{ $.account.id }},namespace_id={{ $.namespace.id }},application_id={{ $.application.id }},scope={{ $.scope.slug }},scope_id={{ $.scope.id }},nullplatform=true
    alb.ingress.kubernetes.io/target-type: ip
    {{ if eq .type "HTTP" }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    {{ else if eq .type "GRPC" }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":{{ .port }}}]'
    alb.ingress.kubernetes.io/backend-protocol-version: GRPC
    alb.ingress.kubernetes.io/load-balancer-attributes: routing.http2.enabled=true
    {{ end }}
spec:
  ingressClassName: alb
  rules:
    - host: {{ $.scope.domain }}
      http:
        paths:
          {{ if eq .type "HTTP" }}
          - path: /{{ .port }}
            pathType: Prefix
            backend:
              service:
                name: d-{{ $.scope.id }}-{{ $.deployment.id }}-http-{{ .port }}
                port:
                  number: {{ .port }}
          {{ else if eq .type "GRPC" }}
          - path: /
            pathType: Prefix
            backend:
              service:
                name: d-{{ $.scope.id }}-{{ $.deployment.id }}-grpc-{{ .port }}
                port:
                  number: {{ .port }}
          {{ end }}
{{ end }}
{{ end }}