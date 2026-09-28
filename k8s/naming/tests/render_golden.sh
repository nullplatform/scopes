#!/bin/bash
set -eo pipefail

CONTEXT_FILE="$1"
OUT_DIR="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

mkdir -p "$OUT_DIR"

log() { if [ "$1" = "error" ]; then echo "$2" >&2; else echo "$2"; fi; }

kubectl() {
	local verb="${1:-}" kind="${2:-}"
	case "$verb $kind" in
		"get namespace")
			return 0
			;;
		"get configmap")
			return 1
			;;
		"get service")
			if [[ "$*" == *"deployment_id=789011"* ]]; then
				cat <<'JSON'
{"items":[
  {"metadata":{"name":"d-123456-789011"},"spec":{"ports":[{"port":8080}]}},
  {"metadata":{"name":"d-123456-789011-grpc-9090"},"spec":{"ports":[{"port":9090}]}}
]}
JSON
			else
				echo '{"items":[]}'
			fi
			return 0
			;;
		"get deployment")
			if [[ "$*" == *"deployment_id=789011"* ]]; then
				echo '{"items":[{"metadata":{"name":"d-123456-789011"}}]}'
			else
				echo '{"items":[]}'
			fi
			return 0
			;;
		*)
			return 0
			;;
	esac
}

export SERVICE_PATH="$ROOT/k8s"
export SERVICE_ACTION="start-blue-green"
export DNS_TYPE="external_dns"
export CONTAINER_MEMORY_IN_MEMORY=64
export CONTAINER_CPU_IN_MILLICORES=93
export PULL_SECRETS=""
export NP_OUTPUT_DIR="$(mktemp -d)"
export CONTEXT="$(cat "$CONTEXT_FILE")"

trap 'rm -rf "$NP_OUTPUT_DIR"' EXIT

source "$ROOT/k8s/utils/get_config_value"
source "$ROOT/k8s/deployment/build_context" > /dev/null

ENRICHED_CONTEXT_DIR="$(mktemp -d)"
trap 'rm -rf "$NP_OUTPUT_DIR" "$ENRICHED_CONTEXT_DIR"' EXIT

ENRICHED_CONTEXT_FILE="$ENRICHED_CONTEXT_DIR/context.json"
echo "$CONTEXT" > "$ENRICHED_CONTEXT_FILE"

DEPLOYMENT_CONTEXT_FILE="$ENRICHED_CONTEXT_DIR/context-deployment.json"
echo "$CONTEXT" | jq --arg replicas "$REPLICAS" '. + {replicas: $replicas}' > "$DEPLOYMENT_CONTEXT_FILE"

render() {
	local tpl="$1"
	local ctx="${2:-$ENRICHED_CONTEXT_FILE}"
	local module="${tpl%%/*}"
	local rest="${tpl#*/templates/}"
	local name
	name="$module-$(echo "$rest" | tr '/' '-')"
	name="${name%.tpl}"
	gomplate -c .="$ctx" --file "$ROOT/$tpl" --out "$OUT_DIR/$name"
	touch "$OUT_DIR/$name"
}

render k8s/deployment/templates/deployment.yaml.tpl "$DEPLOYMENT_CONTEXT_FILE"
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
render scheduled_task/deployment/templates/deployment.yaml.tpl "$DEPLOYMENT_CONTEXT_FILE"
