#!/bin/bash
set -euo pipefail

CONTEXT_FILE="$1"
OUT_DIR="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

mkdir -p "$OUT_DIR"

render() {
	local tpl="$1"
	local module="${tpl%%/*}"
	local rest="${tpl#*/templates/}"
	local name
	name="$module-$(echo "$rest" | tr '/' '-')"
	name="${name%.tpl}"
	gomplate -c .="$CONTEXT_FILE" --file "$ROOT/$tpl" --out "$OUT_DIR/$name"
	touch "$OUT_DIR/$name"
}

render k8s/deployment/templates/deployment.yaml.tpl
render k8s/deployment/templates/service.yaml.tpl
render k8s/deployment/templates/scaling.yaml.tpl
render k8s/deployment/templates/pdb.yaml.tpl
render k8s/deployment/templates/secret.yaml.tpl
render k8s/deployment/templates/secret-files.yaml.tpl
render k8s/deployment/templates/dns-endpoint.yaml.tpl
render k8s/deployment/templates/initial-ingress.yaml.tpl
render k8s/deployment/templates/blue-green-ingress.yaml.tpl
render k8s/deployment/templates/istio/service.yaml.tpl
render k8s/deployment/templates/istio/initial-httproute.yaml.tpl
render k8s/deployment/templates/istio/blue-green-httproute.yaml.tpl
render k8s/deployment/templates/aro/initial-httproute.yaml.tpl
render k8s/deployment/templates/aro/blue-green-httproute.yaml.tpl
render scheduled_task/deployment/templates/deployment.yaml.tpl
