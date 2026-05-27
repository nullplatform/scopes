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
    alb.ingress.kubernetes.io/group.name: {{ .alb_name }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/load-balancer-name: {{ .alb_name }}
    alb.ingress.kubernetes.io/scheme: {{ .ingress_visibility }}
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/tags: nullplatform:managed-by=autocreate,nullplatform:visibility={{ .ingress_visibility }},nullplatform:created-by-scope-id={{ .scope.id }}
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /__nullplatform_autocreate_placeholder
            pathType: Prefix
            backend:
              service:
                name: nullplatform-autocreate-placeholder
                port:
                  number: 80
