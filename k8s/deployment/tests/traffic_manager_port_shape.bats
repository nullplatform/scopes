#!/usr/bin/env bats
# =============================================================================
# Structural tests for the main traffic-manager listener port.
#
# The nginx listener (containerPort + LISTENER_PORT), the three sidecar probes
# and every Service/Route targetPort must all resolve to the same value. When
# they drift the pod still reports Ready — kubelet probes reach the sidecar
# from the node while gateway traffic is aimed at a port nothing listens on —
# so the failure surfaces as request timeouts, far from its cause. These tests
# pin them together.
#
# Grep-based on the template sources, matching ingress_template_shape.bats.
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export TPL_DIR="$PROJECT_ROOT/k8s/deployment/templates"
  export DEPLOYMENT="$TPL_DIR/deployment.yaml.tpl"
  export SERVICE="$TPL_DIR/service.yaml.tpl"
  export ISTIO_SERVICE="$TPL_DIR/istio/service.yaml.tpl"
  export ARO_INITIAL="$TPL_DIR/aro/initial-httproute.yaml.tpl"
  export ARO_BLUE_GREEN="$TPL_DIR/aro/blue-green-httproute.yaml.tpl"
}

@test "deployment: main sidecar containerPort uses main_traffic_manager_port" {
  grep -qF 'containerPort: {{ .main_traffic_manager_port }}' "$DEPLOYMENT"
}

@test "deployment: main sidecar receives LISTENER_PORT" {
  # The traffic-manager image reads LISTENER_PORT in start.sh; without it the
  # image falls back to its own default of 80.
  run grep -A1 -F 'name: LISTENER_PORT' "$DEPLOYMENT"
  [ "$status" -eq 0 ]
  assert_contains "$output" "{{ .main_traffic_manager_port }}"
}

@test "deployment: all three main-sidecar TCP probes use main_traffic_manager_port" {
  count=$(grep -cF '"traffic_port" .main_traffic_manager_port' "$DEPLOYMENT")
  [ "$count" -eq 3 ]
}

@test "deployment: all three main-sidecar HTTP probes use main_traffic_manager_port" {
  count=$(grep -cF '"port" .main_traffic_manager_port' "$DEPLOYMENT")
  [ "$count" -eq 3 ]
}

@test "deployment: application container probes still use main_http_port" {
  # Guards against a careless find-and-replace sweeping the app container too.
  count=$(grep -cF '"port" .main_http_port' "$DEPLOYMENT")
  [ "$count" -eq 6 ]
}

@test "deployment: no hardcoded containerPort 80 remains" {
  ! grep -qE 'containerPort: 80[[:space:]]*$' "$DEPLOYMENT"
}

@test "deployment: no hardcoded probe port 80 remains" {
  ! grep -qF '"port" 80' "$DEPLOYMENT"
  ! grep -qF '"traffic_port" 80' "$DEPLOYMENT"
}

@test "all four service/route templates target main_traffic_manager_port" {
  for f in "$SERVICE" "$ISTIO_SERVICE" "$ARO_INITIAL" "$ARO_BLUE_GREEN"; do
    grep -qF 'targetPort: {{ .main_traffic_manager_port }}' "$f" \
      || { echo "missing templated targetPort in $f"; return 1; }
  done
}

@test "no service/route template hardcodes targetPort 80" {
  for f in "$SERVICE" "$ISTIO_SERVICE" "$ARO_INITIAL" "$ARO_BLUE_GREEN"; do
    if grep -qE 'targetPort: 80[[:space:]]*$' "$f"; then
      echo "hardcoded targetPort 80 still present in $f"
      return 1
    fi
  done
}

@test "additional_ports sidecars keep their own traffic_manager_port" {
  # The per-additional-port sidecar port is a different field and must not
  # have been swept into main_traffic_manager_port.
  grep -qF 'containerPort: {{ .traffic_manager_port }}' "$DEPLOYMENT"
}
