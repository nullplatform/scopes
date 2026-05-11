apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: k8s-{{ .application.slug | strings.Trunc 20 | strings.TrimSuffix "-" }}-{{ .scope.slug | strings.Trunc 20 | strings.TrimSuffix "-" }}-{{ .scope.id }}-dns
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
    dns/zone-type: {{ .dns_zone_type | default "public" }}
spec:
  endpoints:
  - dnsName: {{ .scope.domain }}
    recordTTL: 60
    recordType: {{ .record_type }}
    targets:
    - "{{ .gateway_ip }}"
