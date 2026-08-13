apiVersion: batch/v1
kind: CronJob
metadata:
  name: job-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
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
{{ data.ToYAML $labels | indent 4 }}
    {{- end }}
{{- end }}
  {{- $deployment := index .k8s_modifiers "deployment" }}
  {{- if $deployment }}
    {{- $labels := index $deployment "labels" }}
  {{- if $labels }}
{{ data.ToYAML $labels | indent 4 }}
  {{- end }}
{{- end }}
spec:
  schedule: "{{ .scope.capabilities.cron }}"
  concurrencyPolicy: {{ .scope.capabilities.concurrency_policy }}
  successfulJobsHistoryLimit: {{ .scope.capabilities.history_limit }}
  failedJobsHistoryLimit: {{ .scope.capabilities.history_limit }}
  jobTemplate:
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
    spec:
      backoffLimit: {{ .scope.capabilities.retries }}
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
{{ data.ToYAML $labels | indent 12 }}
              {{- end }}
            {{- end }}
            {{- $deployment := index .k8s_modifiers "deployment" }}
            {{- if $deployment }}
              {{- $labels := index $deployment "labels" }}
              {{- if $labels }}
{{ data.ToYAML $labels | indent 12 }}
              {{- end }}
            {{- end }}
          annotations:
            nullplatform.logs.cloudwatch: 'true'
            nullplatform.logs.cloudwatch.log_group_name: {{ .namespace.slug }}.{{ .application.slug }}
            nullplatform.logs.cloudwatch.log_stream_log_retention_days: '7'
            nullplatform.logs.cloudwatch.log_stream_name_pattern: >-
              type=${type};application={{ .application.id }};scope={{ .scope.id }};deploy={{ .deployment.id }};instance=${instance};container=${container}
            nullplatform.logs.cloudwatch.region: us-east-1
        {{- $global := index .k8s_modifiers "global" }}
            {{- if $global }}
              {{- $annotations := index $global "annotations" }}
              {{- if $annotations }}
{{ data.ToYAML $annotations | indent 12 }}
              {{- end }}
            {{- end }}
            {{- $deployment := index .k8s_modifiers "deployment" }}
            {{- if $deployment }}
              {{- $annotations := index $deployment "annotations" }}
              {{- if $annotations }}
{{ data.ToYAML $annotations | indent 12 }}
              {{- end }}
            {{- end }}
        spec:
          {{- $deployment := index .k8s_modifiers "deployment" }}
          {{- if $deployment }}
            {{- $tolerations := index $deployment "tolerations" }}
            {{- if $tolerations }}
          tolerations:
{{ data.ToYAML $tolerations | indent 10 }}
            {{- end }}
            {{- $nodeSelector := index $deployment "nodeselector" }}
            {{- if $nodeSelector }}
          nodeSelector:
{{ data.ToYAML $nodeSelector | indent 12 }}
            {{- end }}
          {{- end }}
          {{- if .pull_secrets.ENABLED }}
          imagePullSecrets:
            {{- range $secret := .pull_secrets.SECRETS }}
            - name: {{ $secret }}
            {{- end }}
          {{- end }}
          {{- if .service_account_name }}
          serviceAccountName: {{ .service_account_name }}
          {{- end }}
          containers:
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
              image: {{ .asset.url }}
              resources:
                limits:
                  cpu: {{ .scope.capabilities.cpu_millicores }}m
                  memory: {{ .scope.capabilities.ram_memory }}Mi
                requests:
                  cpu: {{ .scope.capabilities.cpu_millicores }}m
                  memory: {{ .scope.capabilities.ram_memory }}Mi
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
          restartPolicy: OnFailure
          securityContext:
            runAsUser: 0
