# syntax=docker/dockerfile:1
#
# scheduled-task scope image — the scheduled_task scope. Leaner than containers:
# its steps only reach for kubectl + gomplate (bash/jq/np ship in the base).
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:1.0.0

RUN apk add --no-cache gomplate

ARG TARGETARCH
ARG KUBECTL_VERSION=1.30.4
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && kubectl version --client

COPY . /app/pkg
ENV NP_PACKAGE_NAME=scheduled-task \
    NP_SERVICE_PATH=/app/pkg/scheduled_task \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint
