apiVersion: pki.ey.com/v1alpha1
kind: Certificate
metadata:
  name: cert-{{ .scope_id }}
  namespace: {{ .namespace }}
spec:
  dnsNames:
    - "{{ .certificate_name }}"
  environment: "{{ .environment }}"
  deploymentId: "{{ .scope_id }}"
  domainName: "{{ .domain_name }}"
  issuerRef:
    name: ey-fabric-issuer
  dnsConfig:
    createDNS: true
    ipAddress: "172.16.0.15"
    recordType: "A"
    view: "internal"
  gateway:
    type: "istio"
    name: "private-gateway-new"
    namespace: "gateways"
    listenerPort: 443
    allowedNamespaces: "All"
