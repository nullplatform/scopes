#!/bin/bash
set -euo pipefail

CONTEXT_FILE="$1"
OUT_DIR="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

mkdir -p "$OUT_DIR"

log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }

source "$ROOT/k8s/utils/get_config_value"
source "$ROOT/k8s/naming/resolve_names"

CONTEXT="$(cat "$CONTEXT_FILE")"
RESOLVED_NAMES=$(np_naming_resolve)

ENRICHED_CONTEXT_DIR="$(mktemp -d)"
trap 'rm -rf "$ENRICHED_CONTEXT_DIR"' EXIT
ENRICHED_CONTEXT_FILE="$ENRICHED_CONTEXT_DIR/context.json"

echo "$CONTEXT" | jq --argjson names "$RESOLVED_NAMES" '
  . + {names: ($names | del(.additional_ports))}
  | if ($names.additional_ports | length) > 0
    then .scope.capabilities.additional_ports = $names.additional_ports
    else . end' > "$ENRICHED_CONTEXT_FILE"

render() {
	local tpl="$1"
	local module="${tpl%%/*}"
	local rest="${tpl#*/templates/}"
	local name
	name="$module-$(echo "$rest" | tr '/' '-')"
	name="${name%.tpl}"
	gomplate -c .="$ENRICHED_CONTEXT_FILE" --file "$ROOT/$tpl" --out "$OUT_DIR/$name"
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
