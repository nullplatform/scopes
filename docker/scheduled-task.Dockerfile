# syntax=docker/dockerfile:1
#
# scheduled-task scope image — the scheduled_task scope. Leaner than containers:
# its steps only reach for kubectl + gomplate (bash/jq/np ship in the base).
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:2.0.1

# aws-cli: the k8s scope scripts this overlay runs on top of call `aws` (sts
# assume-role first of all, then IAM and ECR); without it every action fails at
# the assume_role step on AWS installs.
RUN apk add --no-cache aws-cli gomplate

ARG TARGETARCH
ARG KUBECTL_VERSION=1.30.4
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && kubectl version --client

# Bake the scope in. --chown so the files belong to the uid this image runs
# as: `np` chmods the action script in place at runtime, and a root-owned tree
# would be read-only for the non-root user.
COPY --chown=10001:10001 . /app/pkg
# The scheduled task is the k8s scope run with the scheduled_task overlay (see
# scheduled_task/specs/notification-channel.json.tpl: --service-path=k8s
# --overrides-path=scheduled_task), so the base stays k8s and the overlay goes
# in NP_OVERRIDES_PATH, like containers-datadog does.
ENV NP_PACKAGE_NAME=scheduled-task \
    NP_SERVICE_PATH=/app/pkg/k8s \
    NP_OVERRIDES_PATH=/app/pkg/scheduled_task \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint

# Hand HOME to the runtime user. The RUN steps above ran as root with HOME
# already set to /home/app by the base, so tools invoked at build time left
# root-owned config and cache dirs there (tofu: ~/.terraform.d, helm: ~/.cache
# and ~/.config) that the non-root user could not write to at runtime.
RUN chown -R 10001:10001 /home/app

# Drop root for the runtime. Everything above installs as root, as usual; the
# base (worker-bridge 2.0.0+) ships the app user, np on PATH and a writable
# HOME, and leaves the switch to each image. Numeric on purpose: k8s
# admission with runAsNonRoot resolves USER to a numeric id to prove it
# isn't root, and a name doesn't satisfy that check.
USER 10001:10001
