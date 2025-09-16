apiVersion: apps/v1
kind: Deployment
metadata:
  name: d-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
  labels:
    name: d-{{ .scope.id }}-{{ .deployment.id }}
    app.kubernetes.io/part-of: {{ .namespace.slug }}
spec:
{{- if eq .scope.capabilities.scaling_type "fixed" }}
  replicas: {{ .scope.capabilities.fixed_instances }}
{{- else }}
  replicas: {{ .scope.capabilities.autoscaling.min_replicas }}
{{- end }}
  selector:
    matchLabels:
      name: d-{{ .scope.id }}-{{ .deployment.id }}
  template:
    metadata:
      labels:
        name: d-{{ .scope.id }}-{{ .deployment.id }}
        app.kubernetes.io/part-of: {{ .namespace.slug }}-{{ .application.slug }}
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
      annotations:
        nullplatform.logs.cloudwatch: 'true'
        nullplatform.logs.cloudwatch.log_group_name: {{ .namespace.slug }}.{{ .application.slug }}
        nullplatform.logs.cloudwatch.log_stream_log_retention_days: '7'
        nullplatform.logs.cloudwatch.log_stream_name_pattern: >-
          type=${type};application={{ .application.id }};scope={{ .scope.id }};deploy={{ .deployment.id }};instance=${instance};container=${container}
        nullplatform.logs.cloudwatch.region: us-east-1
    spec:
      imagePullSecrets:
        - name: ecr-secret
      containers:
        - name: http
          securityContext:
            runAsUser: 0
          image: public.ecr.aws/nullplatform/k8s-traffic-manager:latest
          ports:
            - containerPort: 80
              protocol: TCP
          env:
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
              cpu: 93m
              memory: 64Mi
            requests:
              cpu: 31m
          livenessProbe:
            httpGet:
              path: {{ .scope.capabilities.health_check.path }}
              port: 80
              scheme: HTTP
            timeoutSeconds: {{ .scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ .scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ .scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 9
          readinessProbe:
            httpGet:
              path: {{ .scope.capabilities.health_check.path }}
              port: 80
              scheme: HTTP
            timeoutSeconds: {{ .scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ .scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ .scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: {{ .scope.capabilities.health_check.path }}
              port: 80
              scheme: HTTP
            timeoutSeconds: {{ .scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ .scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ .scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 90
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: Always
          
        {{ if .scope.capabilities.additional_ports }}
        {{ range .scope.capabilities.additional_ports }}
        {{ if eq .type "HTTP" }}
        - name: http-{{ .port }}
          securityContext:
            runAsUser: 0
          image: public.ecr.aws/nullplatform/k8s-traffic-manager:latest
          ports:
            - containerPort: {{ .port }}
              protocol: TCP
          env:
            - name: HEALTH_CHECK_TYPE
              value: http
            - name: GRACE_PERIOD
              value: '15'
            - name: LISTENER_PROTOCOL
              value: http
            - name: HEALTH_CHECK_PATH
              value: {{ $.scope.capabilities.health_check.path }}
            - name: LISTENER_PORT
              value: '{{ .port }}'
          resources:
            limits:
              cpu: 93m
              memory: 64Mi
            requests:
              cpu: 31m
          livenessProbe:
            httpGet:
              path: {{ $.scope.capabilities.health_check.path }}
              port: {{ .port }}
              scheme: HTTP
            timeoutSeconds: {{ $.scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ $.scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 9
          readinessProbe:
            httpGet:
              path: {{ $.scope.capabilities.health_check.path }}
              port: {{ .port }}
              scheme: HTTP
            timeoutSeconds: {{ $.scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ $.scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: {{ $.scope.capabilities.health_check.path }}
              port: {{ .port }}
              scheme: HTTP
            timeoutSeconds: {{ $.scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ $.scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ $.scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 90
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: Always
        {{ else if eq .type "GRPC" }}
        - name: grpc-{{ .port }}
          securityContext:
            runAsUser: 0
          image: public.ecr.aws/nullplatform/k8s-traffic-manager:latest
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
              cpu: 93m
              memory: 64Mi
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
          terminationMessagePolicy: File
          imagePullPolicy: Always
        {{ end }}
        {{ end }}
        {{ end }}
        
        - name: application
          envFrom:
            - secretRef:
                name: s-{{ .scope.id }}-d-{{ .deployment.id }}
          image: >-
            {{ .asset.url }}
          securityContext:
            runAsUser: 0
          ports:
            - containerPort: 8080
              protocol: TCP
            {{ if .scope.capabilities.additional_ports }}
            {{ range .scope.capabilities.additional_ports }}
            - containerPort: {{ .port }}
              protocol: TCP
            {{ end }}
            {{ end }}
          resources:
            limits:
              cpu: {{ .scope.capabilities.cpu_millicores }}m
              memory: {{ .scope.capabilities.ram_memory }}Mi
            requests:
              cpu: {{ .scope.capabilities.cpu_millicores }}m
              memory: {{ .scope.capabilities.ram_memory }}Mi
          livenessProbe:
            httpGet:
              path: {{ .scope.capabilities.health_check.path }}
              port: 8080
              scheme: HTTP
            timeoutSeconds: {{ .scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ .scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ .scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 6
          readinessProbe:
            httpGet:
              path: {{ .scope.capabilities.health_check.path }}
              port: 8080
              scheme: HTTP
            timeoutSeconds: {{ .scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ .scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ .scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: {{ .scope.capabilities.health_check.path }}
              port: 8080
              scheme: HTTP
            timeoutSeconds: {{ .scope.capabilities.health_check.timeout_seconds }}
            periodSeconds: {{ .scope.capabilities.health_check.period_seconds }}
            initialDelaySeconds: {{ .scope.capabilities.health_check.initial_delay_seconds }}
            successThreshold: 1
            failureThreshold: 90
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sleep
                  - '16'
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
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
