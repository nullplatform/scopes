apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .names.scope_ingress }}
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
{{- range .scope.domains }}
    - {{ .name }}
{{- end }}
  parentRefs:
{{- $gateways := coll.Slice (coll.Dict "name" .gateway_name "namespace" "gateways") }}
{{- if has . "gateways" }}
  {{- $gateways = .gateways }}
{{- end }}
{{- range $gateways }}
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: {{ .name }}
      namespace: {{ .namespace }}
{{- end }}
  rules:
    - backendRefs:
        # Blue deployment (old version)
        - group: ""
          kind: Service
          name: {{ .names.blue_service }}
          port: {{ .main_http_port }}
          weight: {{ sub 100 .deployment.strategy_data.desired_switched_traffic }}
        # Green deployment (new version)
        - group: ""
          kind: Service
          name: {{ .names.deployment }}
          port: {{ .main_http_port }}
          weight: {{ .deployment.strategy_data.desired_switched_traffic }}
      matches:
        - path:
            type: PathPrefix
            value: /{{ if and (has . "service_to_service") .service_to_service.enabled }}{{ $s2s := .service_to_service }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .names.stable_service }}
  namespace: {{ .k8s_namespace }}
{{- template "stable-metadata" (coll.Dict "root" . "modifier" "service") }}
spec:
  type: ExternalName
  externalName: {{ if has $s2s "external_name" }}{{ $s2s.external_name }}{{ else }}{{ $s2s.gateway_host }}{{ end }}
  ports:
{{- range $s2s.ports }}
{{- $port := . }}{{ $type := "http" }}{{ range $s2s.grpc_ports }}{{ if eq . $port }}{{ $type = "grpc" }}{{ end }}{{ end }}
    - name: {{ $type }}-{{ . }}
      protocol: TCP
      port: {{ . }}
{{- end }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $.names.stable_service }}-http-{{ .main_http_port }}
  namespace: {{ $.k8s_namespace }}
{{- template "stable-metadata" (coll.Dict "root" $ "modifier" "ingress") }}
spec:
  hostnames:
{{- range $s2s.hostnames }}
    - {{ . }}
{{- end }}
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: {{ $s2s.gateway_name }}
      namespace: {{ $s2s.gateway_namespace }}
      sectionName: {{ $s2s.listener_prefix }}{{ .main_http_port }}
{{- template "s2s-previous-parents" (coll.Dict "s2s" $s2s "port" .main_http_port) }}
  rules:
    - backendRefs:
        # Blue deployment (old version)
        - group: ""
          kind: Service
          name: {{ .names.blue_service }}
          port: {{ .main_http_port }}
          weight: {{ sub 100 .deployment.strategy_data.desired_switched_traffic }}
        # Green deployment (new version)
        - group: ""
          kind: Service
          name: {{ .names.deployment }}
          port: {{ .main_http_port }}
          weight: {{ .deployment.strategy_data.desired_switched_traffic }}
      matches:
        - path:
            type: PathPrefix
            value: /
{{- range (index .scope.capabilities "additional_ports") }}
{{- if and (or (eq .type "HTTP") (eq .type "GRPC")) (ne .port $.main_http_port) }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $.names.stable_service }}-{{ strings.ToLower .type }}-{{ .port }}
  namespace: {{ $.k8s_namespace }}
{{- template "stable-metadata" (coll.Dict "root" $ "modifier" "ingress") }}
spec:
  hostnames:
{{- range $s2s.hostnames }}
    - {{ . }}
{{- end }}
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: {{ $s2s.gateway_name }}
      namespace: {{ $s2s.gateway_namespace }}
      sectionName: {{ $s2s.listener_prefix }}{{ .port }}
{{- template "s2s-previous-parents" (coll.Dict "s2s" $s2s "port" .port) }}
  rules:
    - backendRefs:
{{- $blue_svc_exists := true }}
{{- if $.blue_additional_port_services }}
  {{- if not (index $.blue_additional_port_services (printf "%s-%v" (strings.ToLower .type) .port)) }}
    {{- $blue_svc_exists = false }}
  {{- end }}
{{- end }}
{{- if $blue_svc_exists }}
        # Blue deployment (old version)
        - group: ""
          kind: Service
          name: {{ .blue_service_name }}
          port: {{ .port }}
          weight: {{ sub 100 $.deployment.strategy_data.desired_switched_traffic }}
        # Green deployment (new version)
        - group: ""
          kind: Service
          name: {{ .service_name }}
          port: {{ .port }}
          weight: {{ $.deployment.strategy_data.desired_switched_traffic }}
{{- else }}
        - group: ""
          kind: Service
          name: {{ .service_name }}
          port: {{ .port }}
          weight: 100
{{- end }}
      matches:
        - path:
            type: PathPrefix
            value: /
{{- end }}
{{- end }}
{{ end }}{{ define "s2s-previous-parents" }}
{{- if and (has .s2s "previous_parents") (has .s2s.previous_parents (print .port)) }}
{{- range index .s2s.previous_parents (print .port) }}
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: {{ .name }}
      namespace: {{ .namespace }}
{{- if has . "sectionName" }}
      sectionName: {{ .sectionName }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}{{ define "stable-metadata" }}
  labels:
    nullplatform: "true"
    account: {{ .root.account.slug }}
    account_id: "{{ .root.account.id }}"
    namespace: {{ .root.namespace.slug }}
    namespace_id: "{{ .root.namespace.id }}"
    application: {{ .root.application.slug }}
    application_id: "{{ .root.application.id }}"
    scope: {{ .root.scope.slug }}
    scope_id: "{{ .root.scope.id }}"
    nullplatform.io/stable-service: "true"
{{- $global := index .root.k8s_modifiers "global" }}
{{- if $global }}
  {{- $labels := index $global "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
{{- $modifier := index .root.k8s_modifiers .modifier }}
{{- if $modifier }}
  {{- $labels := index $modifier "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
  annotations:
{{- if $global }}
  {{- $annotations := index $global "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
{{- if $modifier }}
  {{- $annotations := index $modifier "annotations" }}
  {{- if $annotations }}
{{ data.ToYAML $annotations | indent 4 }}
  {{- end }}
{{- end }}
{{- end }}