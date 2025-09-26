apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: k-8-s-{{ .scope.slug }}-{{ .scope.id }}-dns
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
spec:
  endpoints:
  - dnsName: {{ .scope.domain }}
    recordTTL: 60
    recordType: A
    targets:
    - "{{ .gateway_ip }}"
