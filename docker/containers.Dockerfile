# syntax=docker/dockerfile:1
#
# containers (k8s) scope image — the full Kubernetes scope on the lean gRPC
# worker bridge. The bridge dials over gRPC and runs the repo's bash entrypoint
# on each action; this image adds the cloud tooling the k8s steps call and bakes
# the whole repo in, so the package-exec channel needs no cmdline.
#
# NP_SERVICE_PATH=k8s + NP_SCOPE_ENTRYPOINT=<repo>/entrypoint mirrors the classic
# `.../scopes/entrypoint --service-path=k8s` the git-clone model used.
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:1.0.0

# apk tooling the k8s steps call. bash, jq, np, base64, curl, ca-certs ship in
# the base. aws-cli 2.x, gomplate and yq are packaged on alpine.
RUN apk add --no-cache aws-cli gomplate yq

# Pinned binaries not reliably packaged on alpine: OpenTofu, kubectl, helm.
# NOTE: review/pin these versions to what the scopes actually target.
ARG TARGETARCH
ARG TOFU_VERSION=1.10.6
ARG KUBECTL_VERSION=1.30.4
ARG HELM_VERSION=3.15.4
RUN set -eux; \
    curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin tofu; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz -C /tmp; \
    mv "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    rm -rf "/tmp/linux-${TARGETARCH}"; \
    tofu version && kubectl version --client && helm version --short

# Bake the whole repo in; the overlays (containers-azure, -datadog, -aro) are
# FROM this image and only flip NP_OVERRIDES_PATH — no re-copy needed.
COPY . /app/pkg
ENV NP_PACKAGE_NAME=containers \
    NP_SERVICE_PATH=/app/pkg/k8s \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint
