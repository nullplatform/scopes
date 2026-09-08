# syntax=docker/dockerfile:1
#
# scheduled-task scope image — the scheduled_task scope. Leaner than containers:
# its steps only reach for kubectl + gomplate (bash/jq/np ship in the base).
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:1.0.0

# aws-cli: the k8s scope scripts this overlay runs on top of call `aws` (sts
# assume-role first of all, then IAM and ECR); without it every action fails at
# the assume_role step on AWS installs.
RUN apk add --no-cache aws-cli gomplate

ARG TARGETARCH
ARG KUBECTL_VERSION=1.30.4
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && kubectl version --client

COPY . /app/pkg
# The scheduled task is the k8s scope run with the scheduled_task overlay (see
# scheduled_task/specs/notification-channel.json.tpl: --service-path=k8s
# --overrides-path=scheduled_task), so the base stays k8s and the overlay goes
# in NP_OVERRIDES_PATH, like containers-datadog does.
ENV NP_PACKAGE_NAME=scheduled-task \
    NP_SERVICE_PATH=/app/pkg/k8s \
    NP_OVERRIDES_PATH=/app/pkg/scheduled_task \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint
