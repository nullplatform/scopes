{{- define "probe.http" }}
            httpGet:
              path: {{ .healthCheck.path }}
              port: {{ .port }}
              scheme: HTTP
{{- end }}
{{- define "probe.tcp" }}
            exec:
              command:
                - /bin/sh
                - '-c'
                - nc -z localhost {{ .app_port }} && nc -z localhost {{ .traffic_port }}
{{- end }}
{{- define "probe.app_tcp" }}
            tcpSocket:
              port: {{ .port }}
{{- end }}
{{- define "probe.base" }}
            timeoutSeconds: {{ .healthCheck.timeout_seconds }}
            periodSeconds: {{ .healthCheck.period_seconds }}
            initialDelaySeconds: {{ .healthCheck.initial_delay_seconds }}
            successThreshold: 1
{{- end }}

apiVersion: apps/v1
kind: Deployment
metadata:
  name: d-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
  labels:
    name: d-{{ .scope.id }}-{{ .deployment.id }}
    app.kubernetes.io/part-of: {{ .namespace.slug }}
    account: {{ .account.slug }}
    account_id: "{{ .account.id }}"
    namespace: {{ .namespace.slug }}
    namespace_id: "{{ .namespace.id }}"
    application: {{ .application.slug }}
    application_id: "{{ .application.id }}"
    scope: {{ .scope.slug }}
    scope_id: "{{ .scope.id }}"
    deployment_id: "{{ .deployment.id }}"
spec:
  replicas: {{ .replicas }}
  selector:
    matchLabels:
      name: d-{{ .scope.id }}-{{ .deployment.id }}
  template:
    metadata:
      labels:
        name: d-{{ .scope.id }}-{{ .deployment.id }}
        app.kubernetes.io/part-of: {{ .component }}
        nullplatform: "true"
        account: "{{ .account.slug }}"
        account_id: "{{ .account.id }}"
        namespace: "{{ .namespace.slug }}"
        namespace_id: "{{ .namespace.id }}"
        application: "{{ .application.slug }}"
        application_id: "{{ .application.id }}"
        scope: "{{ .scope.slug }}"
        scope_id: "{{ .scope.id }}"
        deployment_id: "{{ .deployment.id }}"
    {{- $global := index .k8s_modifiers "global" }}
    {{- if $global }}
      {{- $labels := index $global "labels" }}
      {{- if $labels }}
{{ data.ToYAML $labels | indent 8 }}
      {{- end }}
    {{- end }}
    {{- $deployment := index .k8s_modifiers "deployment" }}
    {{- if $deployment }}
      {{- $labels := index $deployment "labels" }}
      {{- if $labels }}
{{ data.ToYAML $labels | indent 8 }}
      {{- end }}
    {{- end }}
      annotations:
        nullplatform.logs.cloudwatch: 'true'
        nullplatform.logs.cloudwatch.log_group_name: {{ .namespace.slug }}.{{ .application.slug }}
        nullplatform.logs.cloudwatch.log_stream_log_retention_days: '7'
        nullplatform.logs.cloudwatch.log_stream_name_pattern: >-
          type=${type};application={{ .application.id }};scope={{ .scope.id }};deploy={{ .deployment.id }};instance=${instance};container=${container}
        nullplatform.logs.cloudwatch.region: {{ .region }}
    {{- $global := index .k8s_modifiers "global" }}
    {{- if $global }}
      {{- $annotations := index $global "annotations" }}
      {{- if $annotations }}
{{ data.ToYAML $annotations | indent 8 }}
      {{- end }}
    {{- end }}
    {{- $deployment := index .k8s_modifiers "deployment" }}
    {{- if $deployment }}
      {{- $annotations := index $deployment "annotations" }}
      {{- if $annotations }}
{{ data.ToYAML $annotations | indent 8 }}
      {{- end }}
    {{- end }}
    spec:
      {{- if .pull_secrets.ENABLED }}
      imagePullSecrets:
        {{- range $secret := .pull_secrets.SECRETS }}
            - name: {{ $secret }}
        {{- end }}
      {{- end }}
      {{- if .service_account_name }}
      serviceAccountName: {{ .service_account_name }}
      {{- end }}
      {{- $deployment := index .k8s_modifiers "deployment" }}
        {{- if $deployment }}
        {{- $tolerations := index $deployment "tolerations" }}
        {{- if $tolerations }}
      tolerations:
{{ data.ToYAML $tolerations | indent 8 }}
      {{- end }}
      {{- $nodeSelector := index $deployment "nodeselector" }}
      {{- if $nodeSelector }}
      nodeSelector:
{{ data.ToYAML $nodeSelector | indent 8 }}
      {{- end }}
      {{- end }}
      containers:
        - name: http
          securityContext:
            runAsUser: 0
          image: {{ .traffic_image }}
          {{- if .traffic_manager_config_map }}
          volumeMounts:
              - name: nginx-config
                mountPath: /etc/nginx/nginx.conf
                subPath: nginx.conf
              - name: nginx-config
                mountPath: /etc/nginx/conf.d/default.conf
                subPath: default.conf
          {{- end }}
          ports:
            - containerPort: 80
              protocol: TCP
          env:
            - name: UPSTREAM_PORT
              value: '{{ .main_http_port }}'
            - name: HEALTH_CHECK_TYPE
              value: http
            - name: GRACE_PERIOD
              value: '15'
            - name: LISTENER_PROTOCOL
              value: http
            - name: HEALTH_CHECK_PATH
              value: {{ .scope.capabilities.health_check.path }}
          resources:
            limits:
              cpu: {{ .container_cpu_in_millicores }}m
              memory: {{ .container_memory_in_memory }}Mi
            requests:
              cpu: 31m
          livenessProbe:
            {{- if and (has .scope.capabilities.health_check "type") (eq .scope.capabilities.health_check.type "TCP") }}
            {{- template "probe.tcp" dict "healthCheck" .scope.capabilities.health_check "traffic_port" 80 "app_port" .main_http_port }}
            {{- else }}
            {{- template "probe.http" dict "healthCheck" .scope.capabilities.health_check "port" 80 }}
            {{- end }}
            {{- template "probe.base" dict "healthCheck" .scope.capabilities.health_check }}
            failureThreshold: 9
          readinessProbe:
            {{- if and (has .scope.capabilities.health_check "type") (eq .scope.capabilities.health_check.type "TCP") }}
            {{- template "probe.tcp" dict "healthCheck" .scope.capabilities.health_check "traffic_port" 80 "app_port" .main_http_port }}
            {{- else }}
            {{- template "probe.http" dict "healthCheck" .scope.capabilities.health_check "port" 80 }}
            {{- end }}
            {{- template "probe.base" dict "healthCheck" .scope.capabilities.health_check }}
            failureThreshold: 3
          startupProbe:
            {{- if and (has .scope.capabilities.health_check "type") (eq .scope.capabilities.health_check.type "TCP") }}
            {{- template "probe.tcp" dict "healthCheck" .scope.capabilities.health_check "traffic_port" 80 "app_port" .main_http_port }}
            {{- else }}
            {{- template "probe.http" dict "healthCheck" .scope.capabilities.health_check "port" 80 }}
            {{- end }}
            {{- template "probe.base" dict "healthCheck" .scope.capabilities.health_check }}
            failureThreshold: 90
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: FallbackToLogsOnError
          imagePullPolicy: Always

        {{ if .scope.capabilities.additional_ports }}
        {{ range .scope.capabilities.additional_ports }}
        {{ if eq .type "GRPC" }}
        - name: grpc-{{ .port }}
          securityContext:
            runAsUser: 0
          image: {{ $.traffic_image }}
          ports:
            - containerPort: {{ .port }}
              protocol: TCP
          env:
            - name: HEALTH_CHECK_TYPE
              value: grpc
            - name: GRACE_PERIOD
              value: '15'
            - name: LISTENER_PROTOCOL
              value: grpc
            - name: LISTENER_PORT
              value: '{{ .port }}'
          resources:
            limits:
              cpu: {{ $.container_cpu_in_millicores }}m
              memory: {{ $.container_memory_in_memory }}Mi
            requests:
              cpu: 31m
          livenessProbe:
            grpc:
              port: {{ .port }}
            timeoutSeconds: 5
            periodSeconds: 10
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 9
          readinessProbe:
            grpc:
              port: {{ .port }}
            timeoutSeconds: 5
            periodSeconds: 10
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 3
          startupProbe:
            grpc:
              port: {{ .port }}
            timeoutSeconds: 5
            periodSeconds: 10
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 90
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: FallbackToLogsOnError
          imagePullPolicy: Always
        {{ else if eq .type "HTTP" }}
        - name: http-{{ .port }}
          securityContext:
            runAsUser: 0
          image: {{ $.traffic_image }}
          ports:
            - containerPort: {{ .traffic_manager_port }}
              protocol: TCP
          env:
            - name: UPSTREAM_PORT
              value: '{{ .port }}'
            - name: HEALTH_CHECK_TYPE
              value: http
            - name: GRACE_PERIOD
              value: '15'
            - name: LISTENER_PROTOCOL
              value: http
            - name: LISTENER_PORT
              value: '{{ .traffic_manager_port }}'
            - name: HEALTH_CHECK_PATH
              value: {{ $.scope.capabilities.health_check.path }}
          resources:
            limits:
              cpu: {{ $.container_cpu_in_millicores }}m
              memory: {{ $.container_memory_in_memory }}Mi
            requests:
              cpu: 31m
          livenessProbe:
            httpGet:
              path: {{ $.scope.capabilities.health_check.path }}
              port: {{ .traffic_manager_port }}
            timeoutSeconds: 5
            periodSeconds: 10
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 9
          readinessProbe:
            httpGet:
              path: {{ $.scope.capabilities.health_check.path }}
              port: {{ .traffic_manager_port }}
            timeoutSeconds: 5
            periodSeconds: 10
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: {{ $.scope.capabilities.health_check.path }}
              port: {{ .traffic_manager_port }}
            timeoutSeconds: 5
            periodSeconds: 10
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 90
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: Always
        {{ end }}
        {{ end }}
        {{ end }}
        - name: application
          envFrom:
            - secretRef:
                name: s-{{ .scope.id }}-d-{{ .deployment.id }}
    {{- if .parameters.results }}
          env:
      {{- range .parameters.results }}
        {{- if and (eq .type "file") (gt (len .values) 0) }}
          {{- $key := .name | strings.ToLower | regexp.Replace "[^a-z0-9]+" "-" | strings.Trim "-" }}
            - name: {{ printf "app-data-%s" $key }}
              value: {{ .destination_path | quote }}
        {{- end }}
      {{- end }}
    {{- end }}
          image: >-
            {{ .asset.url }}
          securityContext:
            runAsUser: 0
          ports:
            - containerPort: {{ .main_http_port }}
              protocol: TCP
            {{ if .scope.capabilities.additional_ports }}
            {{ range .scope.capabilities.additional_ports }}
            {{ if eq .type "HTTP" }}
            - containerPort: {{ .port }}
              protocol: TCP
            {{ end }}
            {{ end }}
            {{ end }}
          resources:
            limits:
              cpu: {{ .scope.capabilities.cpu_millicores_limit }}m
              memory: {{ .scope.capabilities.ram_memory_limit }}Mi
            requests:
              cpu: {{ .scope.capabilities.cpu_millicores }}m
              memory: {{ .scope.capabilities.ram_memory }}Mi
          livenessProbe:
            {{- if and (has .scope.capabilities.health_check "type") (eq .scope.capabilities.health_check.type "TCP") }}
            {{- template "probe.app_tcp" dict "port" .main_http_port }}
            {{- else }}
            {{- template "probe.http" dict "healthCheck" .scope.capabilities.health_check "port" .main_http_port }}
            {{- end }}
            {{- template "probe.base" dict "healthCheck" .scope.capabilities.health_check }}
            failureThreshold: 6
          readinessProbe:
            {{- if and (has .scope.capabilities.health_check "type") (eq .scope.capabilities.health_check.type "TCP") }}
            {{- template "probe.app_tcp" dict "port" .main_http_port }}
            {{- else }}
            {{- template "probe.http" dict "healthCheck" .scope.capabilities.health_check "port" .main_http_port }}
            {{- end }}
            {{- template "probe.base" dict "healthCheck" .scope.capabilities.health_check }}
            failureThreshold: 3
          startupProbe:
           {{- if and (has .scope.capabilities.health_check "type") (eq .scope.capabilities.health_check.type "TCP") }}
           {{- template "probe.app_tcp" dict "port" .main_http_port }}
           {{- else }}
           {{- template "probe.http" dict "healthCheck" .scope.capabilities.health_check "port" .main_http_port }}
           {{- end }}
           {{- template "probe.base" dict "healthCheck" .scope.capabilities.health_check }}
            failureThreshold: 90
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sleep
                  - '16'
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: FallbackToLogsOnError
          imagePullPolicy: IfNotPresent
          volumeMounts:
    {{- if .parameters.results }}
      {{- range .parameters.results }}
        {{- if and (eq .type "file") }}
          {{- if gt (len .values) 0 }}
            {{- $key := .name | strings.ToLower | regexp.Replace "[^a-z0-9]+" "-" | strings.Trim "-" }}
            - name: {{ printf "file-%s" $key }}
              mountPath: {{ .destination_path | quote }}
              subPath: {{ filepath.Base .destination_path | quote }}
              readOnly: true
          {{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
      volumes:
      {{- if .traffic_manager_config_map }}
      - name: nginx-config
        configMap:
          name: {{ .traffic_manager_config_map }}
      {{- end }}
{{- if .parameters.results }}
  {{- range .parameters.results }}
    {{- if and (eq .type "file") }}
      {{- if gt (len .values) 0 }}
        {{- $key := .name | strings.ToLower | regexp.Replace "[^a-z0-9]+" "-" | strings.Trim "-" }}
      - name: {{ printf "file-%s" $key }}
        secret:
          secretName: s-{{ $.scope.id }}-d-{{ $.deployment.id }}-files
          items:
          - key: {{ printf "app-file-%s" $key }}
            path: {{ filepath.Base .destination_path | quote }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      schedulerName: default-scheduler
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              name: d-{{ .scope.id }}-{{ .deployment.id }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
