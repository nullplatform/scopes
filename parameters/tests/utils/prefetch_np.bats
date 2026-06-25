#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/utils/prefetch_np — the parallel np-cache builder.
#
# Verifies:
#   - all expected `np` reads are fired in a single wave when possible
#   - scope-level payloads do a 2-wave dance (scope.json → then iam.json)
#   - NRN is built locally from entities/value_entities (no api call)
#   - existing NP_CACHE_DIR is honored (test/script escape hatch)
# =============================================================================

setup() {
  export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PARAMETERS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  source "$PROJECT_ROOT/testing/assertions.sh"

  export SCRIPT="$PARAMETERS_DIR/utils/prefetch_np"
  export BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"

  # `np` mock — records every invocation and returns a recognizable payload
  # per subcommand. Each record carries a stable `.slug` so build_external_id
  # works downstream too.
  export NP_LOG="$BATS_TEST_TMPDIR/np-calls.log"
  : > "$NP_LOG"
  cat > "$BIN_DIR/np" << 'EOF'
#!/bin/bash
echo "$*" >> "$NP_LOG"
sub="$1 $2"
case "$sub" in
  "provider specification") echo '{"slug":"aws-secrets-manager"}' ;;
  "provider list")          echo '{"results":[{"attributes":{"iam_role_arns":{"arns":[{"selector":"secret_manager","arn":"arn:x"}]}}}]}' ;;
  "organization read")      echo '{"slug":"acme"}' ;;
  "account read")           echo '{"slug":"prod"}' ;;
  "namespace read")         echo '{"slug":"billing"}' ;;
  "application read")       echo '{"slug":"api"}' ;;
  "scope read")             echo '{"slug":"staging","dimensions":{"environment":"production"}}' ;;
  *)                        echo '{}' ;;
esac
EOF
  chmod +x "$BIN_DIR/np"
}

teardown() {
  unset CONTEXT SPEC_ID NP_CACHE_DIR NRN
}

@test "prefetch_np: app-level payload — wave 1 fires spec + 4 entities + iam (no scope read)" {
  export CONTEXT='{
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo NRN=\$NRN
    echo CACHE=\$NP_CACHE_DIR
  "

  assert_equal "$status" "0"
  assert_contains "$output" "NRN=organization=O:account=A:namespace=N:application=AP"

  run cat "$NP_LOG"
  assert_contains "$output" "provider specification read --id spec-123 --format json"
  assert_contains "$output" "organization read --id O --format json"
  assert_contains "$output" "account read --id A --format json"
  assert_contains "$output" "namespace read --id N --format json"
  assert_contains "$output" "application read --id AP --format json"
  assert_contains "$output" "provider list --categories identity-access-control --nrn organization=O:account=A:namespace=N:application=AP --format json"
  # No scope read in app-level
  case "$output" in *"scope read"*) return 1 ;; esac
}

@test "prefetch_np: dimension-level — iam call carries --dimensions in wave 1" {
  export CONTEXT='{
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "dimensions":{"country":"argentina","site":"aws-main"},
    "provider":{"specification_id":"spec-123"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  assert_contains "$output" "--dimensions country:argentina,site:aws-main"
}

@test "prefetch_np: scope-level w/o top dims — iam deferred to wave 2 (uses scope.json dims)" {
  export CONTEXT='{
    "value_entities":{"organization":"O","account":"A","namespace":"N","application":"AP","scope":"S"},
    "provider":{"specification_id":"spec-123"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    echo NRN=\$NRN
  "

  assert_equal "$status" "0"
  assert_contains "$output" "NRN=organization=O:account=A:namespace=N:application=AP:scope=S"

  run cat "$NP_LOG"
  # Wave 1 fires scope read but NOT iam (yet)
  assert_contains "$output" "scope read --id S --format json"
  # Wave 2 fires iam with dims pulled from scope.json
  assert_contains "$output" "--dimensions environment:production"
}

@test "prefetch_np: scope-level WITH top dims — iam fires in wave 1 with top dims" {
  export CONTEXT='{
    "value_entities":{"organization":"O","account":"A","namespace":"N","application":"AP","scope":"S"},
    "dimensions":{"country":"ar"},
    "provider":{"specification_id":"spec-123"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  # iam call uses top-level dims, not scope.json dims
  assert_contains "$output" "--dimensions country:ar"
  case "$output" in *"--dimensions environment:production"*) return 1 ;; esac
}

@test "prefetch_np: pre-set NP_CACHE_DIR is honored — no np calls fired" {
  export CONTEXT='{
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123"}
  }'
  export SPEC_ID="spec-123"
  export NP_CACHE_DIR="$BATS_TEST_TMPDIR/preset-cache"
  mkdir -p "$NP_CACHE_DIR"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  [ -z "$output" ]
}

@test "prefetch_np: cache files are written and readable" {
  export CONTEXT='{
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    for f in spec organization account namespace application iam; do
      if [ -s \"\$NP_CACHE_DIR/\$f.json\" ]; then echo \"OK \$f\"; else echo \"MISS \$f\"; fi
    done
  "

  assert_equal "$status" "0"
  assert_contains "$output" "OK spec"
  assert_contains "$output" "OK organization"
  assert_contains "$output" "OK account"
  assert_contains "$output" "OK namespace"
  assert_contains "$output" "OK application"
  assert_contains "$output" "OK iam"
}
