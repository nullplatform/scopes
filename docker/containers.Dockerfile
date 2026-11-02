# syntax=docker/dockerfile:1
#
# containers (k8s) scope image: the scope's own worker over the whole repo. The
# worker (worker/, TypeScript on bun, compiled to one binary) answers the
# telemetry actions on the cluster itself and runs the repo's bash entrypoint
# for every other action, as the worker-bridge did; this image replaces the
# bridge as the base the overlays (containers-datadog) build on, and adds the
# cloud tooling the k8s steps call.
#
# NP_SERVICE_PATH=k8s + NP_SCOPE_ENTRYPOINT=<repo>/entrypoint mirrors the classic
# `.../scopes/entrypoint --service-path=k8s` the git-clone model used.

# ── stage 1: compile the worker ────────────────────────────────────────────
# The build stage runs on the builder's own architecture and cross-compiles:
# bun targets any platform, so a multi-arch buildx emulates nothing here.
FROM --platform=$BUILDPLATFORM oven/bun:1-alpine AS build
ARG TARGETARCH
WORKDIR /w
COPY worker/package.json worker/bun.lock ./
RUN bun install --frozen-lockfile --production
COPY worker/src ./src
# bun names amd64 "x64".
RUN arch=$([ "${TARGETARCH:-amd64}" = "amd64" ] && echo x64 || echo "$TARGETARCH") \
    && bun build --compile --target="bun-linux-${arch}-musl" src/index.ts --outfile /out/worker

# ── stage 2: the runtime, with the tooling the k8s steps call ──────────────
FROM alpine:3.24
# bun's musl binary links libstdc++/libgcc; bash runs the entrypoints; jq, curl
# and ca-certs drive the steps; aws-cli, gomplate and yq are packaged on alpine.
# `apk upgrade` first: the alpine tag lags its package repo, so the base layer's
# own packages can ship with already-fixed CVEs.
RUN apk upgrade --no-cache \
    && apk add --no-cache libstdc++ libgcc bash jq curl ca-certificates openssl aws-cli gomplate yq

# The np CLI the steps call. The installer drops it under $HOME/.local/bin, which
# only root reaches; move it onto the default PATH.
RUN curl -sSL https://cli.nullplatform.com/install.sh | sh \
    && mv /root/.local/bin/np /usr/local/bin/np \
    && rm -rf /root/.local

# Pinned binaries not reliably packaged on alpine: OpenTofu, kubectl, helm.
# NOTE: review/pin these versions to what the scopes actually target.
ARG TARGETARCH
ARG TOFU_VERSION=1.12.6
ARG KUBECTL_VERSION=1.30.4
ARG HELM_VERSION=3.22.0
RUN set -eux; \
    curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin tofu; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz -C /tmp; \
    mv "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    rm -rf "/tmp/linux-${TARGETARCH}"; \
    tofu version && kubectl version --client && helm version --short

COPY --from=build /out/worker /usr/local/bin/worker

# Bake the whole repo in; the overlays (containers-datadog, the azure ones) are
# FROM this image and only flip NP_OVERRIDES_PATH — no re-copy needed.
COPY . /app/pkg
ENV NP_PACKAGE_NAME=containers \
    NP_SERVICE_PATH=/app/pkg/k8s \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint \
    NP_AGENT_PLUGIN=np-agent-v1

EXPOSE 50051
ENTRYPOINT ["worker"]
