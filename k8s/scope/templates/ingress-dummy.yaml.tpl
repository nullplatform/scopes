apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nullplatform-autocreate-{{ .alb_name }}
  namespace: {{ .k8s_namespace }}
  labels:
    nullplatform: "true"
    nullplatform-autocreate: "true"
    alb_name: {{ .alb_name }}
  annotations:
    alb.ingress.kubernetes.io/actions.response-404: '{"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"404","messageBody":"404 scope not found or has not been deployed yet"}}'
    alb.ingress.kubernetes.io/group.name: {{ .alb_name }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/load-balancer-name: {{ .alb_name }}
    alb.ingress.kubernetes.io/scheme: {{ .ingress_visibility }}
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - host: {{ .dummy_host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: response-404
                port:
                  name: use-annotation
