#!/usr/bin/env bats
# =============================================================================
# Unit tests for route_kind - reads the kind from a rendered manifest
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../route_kind"
}

@test "route_kind: reads Ingress from a rendered ingress manifest" {
  cat > "$BATS_TEST_TMPDIR/ingress.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k-8-s-dev-123-internet-facing
EOF

  run route_kind "$BATS_TEST_TMPDIR/ingress.yaml"

  [ "$status" -eq 0 ]
  [ "$output" = "Ingress" ]
}

@test "route_kind: reads HTTPRoute and ignores the nested parentRef kind" {
  cat > "$BATS_TEST_TMPDIR/httproute.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: k-8-s-dev-123-internet-facing
spec:
  parentRefs:
    - kind: Gateway
      name: gateway-public
EOF

  run route_kind "$BATS_TEST_TMPDIR/httproute.yaml"

  [ "$status" -eq 0 ]
  [ "$output" = "HTTPRoute" ]
}

@test "route_kind: tolerates quoted and trailing-whitespace values" {
  printf 'apiVersion: v1\nkind: "HTTPRoute"   \n' > "$BATS_TEST_TMPDIR/quoted.yaml"

  run route_kind "$BATS_TEST_TMPDIR/quoted.yaml"

  [ "$status" -eq 0 ]
  [ "$output" = "HTTPRoute" ]
}

@test "route_kind: fails when the manifest does not exist" {
  run route_kind "$BATS_TEST_TMPDIR/missing.yaml"

  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "route_kind: fails when no argument is given" {
  run route_kind

  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "route_kind: returns empty for a manifest without a top-level kind" {
  printf 'apiVersion: v1\nmetadata:\n  name: x\n' > "$BATS_TEST_TMPDIR/nokind.yaml"

  run route_kind "$BATS_TEST_TMPDIR/nokind.yaml"

  [ -z "$output" ]
}
