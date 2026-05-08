#!/usr/bin/env bats
# =============================================================================
# Structural tests for the ingress templates.
# Verifies the listen-ports annotation shape per port type without rendering
# templates. Catches regressions like accidentally restoring a hardcoded
# [{"HTTP":80},{"HTTPS":443}] for HTTP additional ports (which would re-shadow
# the main ingress on the same listener).
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  export INITIAL="$PROJECT_ROOT/k8s/deployment/templates/initial-ingress.yaml.tpl"
  export BLUE_GREEN="$PROJECT_ROOT/k8s/deployment/templates/blue-green-ingress.yaml.tpl"
}

# -----------------------------------------------------------------------------
# Main ingress (the top-level ingress, NOT inside additional_ports loop)
# -----------------------------------------------------------------------------

@test "initial-ingress: main ingress listens on HTTP:80 + HTTPS:443" {
  # First listen-ports occurrence in the file is the main ingress.
  first_listen=$(grep -m 1 "listen-ports" "$INITIAL")
  [[ "$first_listen" == *'[{"HTTP":80},{"HTTPS":443}]'* ]]
}

@test "blue-green-ingress: main ingress listens on HTTP:80 + HTTPS:443 with ssl-redirect" {
  first_listen=$(grep -m 1 "listen-ports" "$BLUE_GREEN")
  [[ "$first_listen" == *'[{"HTTP":80},{"HTTPS":443}]'* ]]
  # ssl-redirect is on the main ingress (only HTTP+HTTPS listeners use it).
  grep -q 'ssl-redirect: "443"' "$BLUE_GREEN"
}

# -----------------------------------------------------------------------------
# Additional ports — both HTTP and GRPC use HTTPS on their own port
# (CLIEN-739: HTTP additional ports moved from sharing listener 443 to
#  opening their own HTTPS listener at .port, matching the GRPC pattern.)
# -----------------------------------------------------------------------------

@test "initial-ingress: HTTP additional port branch uses per-port HTTPS listener" {
  # Inside the additional_ports loop, the HTTP branch must use [{"HTTPS":{{ .port }}}].
  # The string '[{"HTTPS":{{ .port }}}]' must appear in the file. The string
  # '"HTTP":80' must NOT appear inside the additional_ports range — only on
  # the main ingress (which is outside the range).
  grep -F '[{"HTTPS":{{ .port }}}]' "$INITIAL" | head -1 >/dev/null
  # Sanity: there should be exactly two occurrences of [{"HTTPS":{{ .port }}}]
  # (one for HTTP branch, one for GRPC branch).
  count=$(grep -cF '[{"HTTPS":{{ .port }}}]' "$INITIAL")
  [ "$count" -eq 2 ]
  # Sanity: there should be exactly one occurrence of [{"HTTP":80},{"HTTPS":443}]
  # (the main ingress only — additional ports must not use it).
  shared_count=$(grep -cF '[{"HTTP":80},{"HTTPS":443}]' "$INITIAL")
  [ "$shared_count" -eq 1 ]
}

@test "initial-ingress: GRPC additional port uses backend-protocol-version GRPC" {
  grep -q 'backend-protocol-version: GRPC' "$INITIAL"
}

@test "blue-green-ingress: HTTP additional port branch uses per-port HTTPS listener" {
  count=$(grep -cF '[{"HTTPS":{{ .port }}}]' "$BLUE_GREEN")
  [ "$count" -eq 2 ]
  shared_count=$(grep -cF '[{"HTTP":80},{"HTTPS":443}]' "$BLUE_GREEN")
  [ "$shared_count" -eq 1 ]
}

@test "blue-green-ingress: ssl-redirect only present on main ingress (one occurrence)" {
  # ssl-redirect: "443" only makes sense when the listener has both HTTP and HTTPS,
  # which is the main ingress. Additional HTTP ports use HTTPS-only listeners,
  # so they must not carry ssl-redirect.
  count=$(grep -cF 'ssl-redirect: "443"' "$BLUE_GREEN")
  [ "$count" -eq 1 ]
}

@test "blue-green-ingress: GRPC additional port uses backend-protocol-version GRPC" {
  grep -q 'backend-protocol-version: GRPC' "$BLUE_GREEN"
}
