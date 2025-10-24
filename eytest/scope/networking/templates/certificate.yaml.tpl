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
  gateway:
    name: {{ .gateway_name }}
    namespace: {{ .gateway_namespace }}
    listenerPort: 443
    allowedNamespaces: "All"