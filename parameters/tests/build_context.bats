#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/build_context — provider resolution + sourcing
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/build_context"
  export TEST_PROVIDER_DIR="$PARAMETERS_DIR/providers/test_provider"

  # Sensible CONTEXT default (a secret payload). Individual tests can override.
  export CONTEXT='{"external_id":"ext-123","parameter_id":42,"value":"my-val","parameter_name":"DB_PASS","encoding":"plain","secret":true}'
}

teardown() {
  rm -rf "$TEST_PROVIDER_DIR"
  unset PARAMETER_KIND ACTIVE_PROVIDER PROVIDER_DIR PARAMETERS_ROOT
  unset SECRET_PROVIDER PARAMETER_PROVIDER
  unset EXTERNAL_ID PARAMETER_ID PARAMETER_VALUE PARAMETER_NAME PARAMETER_ENCODING
  unset PROVIDER_CONFIG
}

@test "build_context: extracts notification fields and exports them" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"

  run bash -c "source $SCRIPT && echo EID=\$EXTERNAL_ID PID=\$PARAMETER_ID VAL=\$PARAMETER_VALUE NAME=\$PARAMETER_NAME ENC=\$PARAMETER_ENCODING"

  assert_equal "$status" "0"
  assert_contains "$output" "EID=ext-123"
  assert_contains "$output" "PID=42"
  assert_contains "$output" "VAL=my-val"
  assert_contains "$output" "NAME=DB_PASS"
  assert_contains "$output" "ENC=plain"
}

@test "build_context: secret kind selects SECRET_PROVIDER" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"

  run bash -c "source $SCRIPT && echo PROV=\$ACTIVE_PROVIDER KIND=\$PARAMETER_KIND"

  assert_equal "$status" "0"
  assert_contains "$output" "PROV=test_provider"
  assert_contains "$output" "KIND=secret"
}

@test "build_context: parameter kind selects PARAMETER_PROVIDER" {
  export CONTEXT='{"external_id":"e","secret":false}'
  export PARAMETER_KIND="parameter"
  export PARAMETER_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"

  run bash -c "source $SCRIPT && echo PROV=\$ACTIVE_PROVIDER KIND=\$PARAMETER_KIND"

  assert_equal "$status" "0"
  assert_contains "$output" "PROV=test_provider"
  assert_contains "$output" "KIND=parameter"
}

@test "build_context: derives PARAMETER_KIND from CONTEXT.secret when unset" {
  unset PARAMETER_KIND
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"

  run bash -c "source $SCRIPT && echo KIND=\$PARAMETER_KIND"

  assert_equal "$status" "0"
  assert_contains "$output" "KIND=secret"
}

@test "build_context: derives parameter kind when CONTEXT.secret is false" {
  export CONTEXT='{"external_id":"e","secret":false}'
  unset PARAMETER_KIND
  export PARAMETER_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"

  run bash -c "source $SCRIPT && echo KIND=\$PARAMETER_KIND PROV=\$ACTIVE_PROVIDER"

  assert_equal "$status" "0"
  assert_contains "$output" "KIND=parameter"
  assert_contains "$output" "PROV=test_provider"
}

@test "build_context: fails with troubleshooting when SECRET_PROVIDER is unset" {
  export PARAMETER_KIND="secret"
  unset SECRET_PROVIDER

  run bash -c "source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ No provider configured for kind 'secret'"
  assert_contains "$output" "SECRET_PROVIDER env var is not set"
  assert_contains "$output" "🔧 How to fix:"
}

@test "build_context: fails with troubleshooting when PARAMETER_PROVIDER is unset" {
  export PARAMETER_KIND="parameter"
  unset PARAMETER_PROVIDER

  run bash -c "source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ No provider configured for kind 'parameter'"
  assert_contains "$output" "PARAMETER_PROVIDER env var is not set"
}

@test "build_context: fails when provider directory doesn't exist" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="nonexistent_provider"

  run bash -c "source $SCRIPT"

  [ "$status" -ne 0 ]
  assert_contains "$output" "❌ Provider implementation not found: 'nonexistent_provider'"
  assert_contains "$output" "🔧 How to fix:"
}

@test "build_context: sources provider fetch_configuration when present" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"
  echo 'export FETCH_RAN="yes"' > "$TEST_PROVIDER_DIR/fetch_configuration"

  run bash -c "source $SCRIPT && echo FETCH=\$FETCH_RAN"

  assert_equal "$status" "0"
  assert_contains "$output" "FETCH=yes"
}

@test "build_context: sources provider setup when present" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"
  echo 'export SETUP_RAN="yes"' > "$TEST_PROVIDER_DIR/setup"

  run bash -c "source $SCRIPT && echo SETUP=\$SETUP_RAN"

  assert_equal "$status" "0"
  assert_contains "$output" "SETUP=yes"
}

@test "build_context: sources fetch_configuration before setup" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"
  echo 'export ORDER="${ORDER:-}fetch,"' > "$TEST_PROVIDER_DIR/fetch_configuration"
  echo 'export ORDER="${ORDER:-}setup"' > "$TEST_PROVIDER_DIR/setup"

  run bash -c "source $SCRIPT && echo ORDER=\$ORDER"

  assert_equal "$status" "0"
  assert_contains "$output" "ORDER=fetch,setup"
}

@test "build_context: succeeds when provider has no fetch_configuration or setup" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"

  run bash -c "source $SCRIPT && echo PROV=\$ACTIVE_PROVIDER"

  assert_equal "$status" "0"
  assert_contains "$output" "PROV=test_provider"
}

@test "build_context: exports PROVIDER_DIR and PARAMETERS_ROOT" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  mkdir -p "$TEST_PROVIDER_DIR"

  run bash -c "source $SCRIPT && echo PD=\$PROVIDER_DIR ROOT=\$PARAMETERS_ROOT"

  assert_equal "$status" "0"
  assert_contains "$output" "PD=$PARAMETERS_DIR/providers/test_provider"
  assert_contains "$output" "ROOT=$PARAMETERS_DIR"
}

@test "build_context: provider setup can read get_config_value with --provider" {
  export PARAMETER_KIND="secret"
  export SECRET_PROVIDER="test_provider"
  export PROVIDER_CONFIG='{"address":"https://example.com"}'
  mkdir -p "$TEST_PROVIDER_DIR"
  cat > "$TEST_PROVIDER_DIR/setup" << 'EOF'
ADDR=$(get_config_value --provider '.address')
export RESOLVED_ADDR="$ADDR"
EOF

  run bash -c "source $SCRIPT && echo ADDR=\$RESOLVED_ADDR"

  assert_equal "$status" "0"
  assert_contains "$output" "ADDR=https://example.com"
}
