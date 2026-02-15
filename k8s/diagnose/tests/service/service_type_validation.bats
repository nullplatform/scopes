#!/usr/bin/env bats
# =============================================================================
# Unit tests for diagnose/service/service_type_validation
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$PROJECT_ROOT/testing/assertions.sh"
  source "$BATS_TEST_DIRNAME/../../utils/diagnose_utils"

  export NAMESPACE="test-ns"
  export LABEL_SELECTOR="app=test"
  export NP_OUTPUT_DIR="$(mktemp -d)"
  export SCRIPT_OUTPUT_FILE="$(mktemp)"
  export SCRIPT_LOG_FILE="$(mktemp)"
  echo '{"status":"pending","evidence":{},"logs":[]}' > "$SCRIPT_OUTPUT_FILE"

  export SERVICES_FILE="$(mktemp)"
  export EVENTS_FILE="$(mktemp)"
  echo '{"items":[]}' > "$EVENTS_FILE"
}

teardown() {
  rm -rf "$NP_OUTPUT_DIR"
  rm -f "$SCRIPT_OUTPUT_FILE"
  rm -f "$SCRIPT_LOG_FILE"
  rm -f "$SERVICES_FILE"
  rm -f "$EVENTS_FILE"
}

# =============================================================================
# ClusterIP Tests
# =============================================================================
@test "service/service_type_validation: validates ClusterIP service" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "type": "ClusterIP",
      "clusterIP": "10.0.0.1"
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Type=ClusterIP"
  assert_contains "$output" "Internal service"
  assert_contains "$output" "10.0.0.1"
}

@test "service/service_type_validation: validates headless service" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "headless-svc"},
    "spec": {
      "type": "ClusterIP",
      "clusterIP": "None"
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Headless service"
}

# =============================================================================
# NodePort Tests
# =============================================================================
@test "service/service_type_validation: validates NodePort service" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {
      "type": "NodePort",
      "ports": [{"port": 80, "nodePort": 30080}]
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Type=NodePort"
  assert_contains "$output" "NodePort 30080"
}

# =============================================================================
# LoadBalancer Tests
# =============================================================================
@test "service/service_type_validation: validates LoadBalancer with IP" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"type": "LoadBalancer"},
    "status": {
      "loadBalancer": {
        "ingress": [{"ip": "1.2.3.4"}]
      }
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "LoadBalancer available"
  assert_contains "$output" "1.2.3.4"
}

@test "service/service_type_validation: validates LoadBalancer with hostname" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"type": "LoadBalancer"},
    "status": {
      "loadBalancer": {
        "ingress": [{"hostname": "my-lb.elb.amazonaws.com"}]
      }
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "LoadBalancer available"
  assert_contains "$output" "my-lb.elb.amazonaws.com"
}

@test "service/service_type_validation: warns on pending LoadBalancer" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"type": "LoadBalancer"},
    "status": {}
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Pending"
}

# =============================================================================
# ExternalName Tests
# =============================================================================
@test "service/service_type_validation: validates ExternalName service" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "external-svc"},
    "spec": {
      "type": "ExternalName",
      "externalName": "api.example.com"
    }
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "ExternalName"
  assert_contains "$output" "api.example.com"
}

# =============================================================================
# Invalid Type Tests
# =============================================================================
@test "service/service_type_validation: fails on unknown service type" {
  cat > "$SERVICES_FILE" << 'EOF'
{
  "items": [{
    "metadata": {"name": "my-svc"},
    "spec": {"type": "InvalidType"}
  }]
}
EOF

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Unknown service type"
}

# =============================================================================
# Skip Tests
# =============================================================================
@test "service/service_type_validation: skips when no services" {
  echo '{"items":[]}' > "$SERVICES_FILE"

  run bash -c "source '$BATS_TEST_DIRNAME/../../utils/diagnose_utils' && source '$BATS_TEST_DIRNAME/../../service/service_type_validation'"

  [ "$status" -eq 0 ]
  assert_contains "$output" "skipped"
}
