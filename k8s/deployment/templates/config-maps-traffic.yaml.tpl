apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config-{{ .scope.id }}-{{ .deployment.id }}
  namespace: {{ .k8s_namespace }}
  labels:
    name: nginx-config-{{ .scope.id }}-{{ .deployment.id }}
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
data:
  nginx.conf: |
    user  nginx;
    worker_processes  auto;
    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;

    events {
        worker_connections  4096;
        use epoll;
        multi_accept on;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format  main  '$remote_addr [$time_local] "$request" '
                          '$status $request_time $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for" "$quality"';

        map $status $quality {
          ~^[23]   "OK (2XX, 3XX)";
          ~^4      "DENIED (4XXs)";
          default  "ERROR (5XXs)";
        }

        access_log  /var/log/nginx/access.log  main;

        sendfile        on;
        tcp_nopush      on;
        tcp_nodelay     on;

        keepalive_timeout  65;
        keepalive_requests 1000;

        gzip on;
        gzip_vary on;
        gzip_proxied any;
        gzip_comp_level 6;
        gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

        server_tokens off;

        include /etc/nginx/conf.d/*.conf;
    }

  default.conf: |
    upstream null_app {
        keepalive 16;
        server 127.0.0.1:8080;
    }

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen 80;
        server_name _;

        proxy_connect_timeout 60s;
        proxy_send_timeout    3600s;
        proxy_read_timeout    3600s;
        send_timeout          3600s;

        proxy_busy_buffers_size 512k;
        proxy_buffers           4 512k;
        proxy_buffer_size       256k;

        client_max_body_size 75M;

        location {{ .scope.capabilities.health_check.path }} {
            access_log off;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Connection "";
            proxy_pass http://null_app;
        }

        location / {
            proxy_http_version 1.1;

            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host  $host;

            proxy_set_header Upgrade    $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Origin     $http_origin;

            proxy_set_header Authorization $http_authorization;

            proxy_buffering off;
            proxy_set_header Connection "";

            proxy_pass http://null_app;
        }
    }
