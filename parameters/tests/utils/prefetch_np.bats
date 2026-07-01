#!/usr/bin/env bats
# =============================================================================
# Unit tests for parameters/utils/prefetch_np — the parallel np-cache builder.
#
# Verifies:
#   - action-aware: store fetches entity slugs; retrieve/delete skip them
#   - slug-from-payload skips the `np provider specification read` call
#   - dimensions come from .value_dimensions / .dimensions / (none) — no
#     scope read needed just for dims
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
  # per subcommand.
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
  "scope read")             echo '{"slug":"staging"}' ;;
  *)                        echo '{}' ;;
esac
EOF
  chmod +x "$BIN_DIR/np"
}

teardown() {
  unset CONTEXT SPEC_ID NP_CACHE_DIR NRN
}

# ---- Action-aware: store fires entity reads, retrieve/delete don't --------

@test "prefetch_np: store action — fires 4 entity reads + iam" {
  export CONTEXT='{
    "action":"parameter:store",
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  assert_contains "$output" "organization read --id O"
  assert_contains "$output" "account read --id A"
  assert_contains "$output" "namespace read --id N"
  assert_contains "$output" "application read --id AP"
  assert_contains "$output" "provider list --categories identity-access-control"
  # slug is in payload — no spec read
  case "$output" in *"provider specification read"*) return 1 ;; esac
}

@test "prefetch_np: retrieve action — skips entity reads, only iam fires" {
  export CONTEXT='{
    "action":"parameter:retrieve",
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  assert_contains "$output" "provider list --categories identity-access-control"
  # No entity reads at all
  case "$output" in *"organization read"*) return 1 ;; esac
  case "$output" in *"account read"*) return 1 ;; esac
  case "$output" in *"namespace read"*) return 1 ;; esac
  case "$output" in *"application read"*) return 1 ;; esac
  case "$output" in *"scope read"*) return 1 ;; esac
}

@test "prefetch_np: delete action — skips entity reads, only iam fires" {
  export CONTEXT='{
    "action":"parameter:delete",
    "value_entities":{"organization":"O","account":"A","namespace":"N","application":"AP","scope":"S"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  assert_contains "$output" "provider list --categories identity-access-control"
  case "$output" in *"organization read"*) return 1 ;; esac
  case "$output" in *"scope read"*) return 1 ;; esac
}

# ---- Slug from payload skips the spec call --------------------------------

@test "prefetch_np: specification_slug in payload skips `np provider specification read`" {
  export CONTEXT='{
    "action":"parameter:retrieve",
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  run cat "$NP_LOG"
  case "$output" in *"provider specification read"*) return 1 ;; esac
}

# ---- Dimensions resolution: from .value_dimensions / .dimensions ----------

@test "prefetch_np: value_dimensions (scope-level) is passed to iam call in wave 1" {
  export CONTEXT='{
    "action":"parameter:retrieve",
    "value_entities":{"organization":"O","account":"A","namespace":"N","application":"AP","scope":"S"},
    "value_dimensions":{"country":"uruguay","environment":"development"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  assert_contains "$output" "--dimensions country:uruguay,environment:development"
  # No scope read needed since dimensions came from payload
  case "$output" in *"scope read"*) return 1 ;; esac
}

@test "prefetch_np: top-level dimensions (dim-level) is passed to iam call" {
  export CONTEXT='{
    "action":"parameter:retrieve",
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "dimensions":{"country":"argentina","site":"aws-main"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  run cat "$NP_LOG"
  assert_contains "$output" "--dimensions country:argentina,site:aws-main"
}

# ---- Store + scope-level still fetches scope (for the slug) ---------------

@test "prefetch_np: store + scope-level fires scope read (for slug in build_external_id)" {
  export CONTEXT='{
    "action":"parameter:store",
    "value_entities":{"organization":"O","account":"A","namespace":"N","application":"AP","scope":"S"},
    "value_dimensions":{"environment":"production"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
  "

  assert_equal "$status" "0"
  run cat "$NP_LOG"
  assert_contains "$output" "scope read --id S"
  # iam still fires with dims from value_dimensions (no wave 2)
  assert_contains "$output" "--dimensions environment:production"
}

# ---- Escape hatch + cache file presence -----------------------------------

@test "prefetch_np: pre-set NP_CACHE_DIR is honored — no np calls fired" {
  export CONTEXT='{
    "action":"parameter:retrieve",
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
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

@test "prefetch_np: store action writes the cache files it needs" {
  export CONTEXT='{
    "action":"parameter:store",
    "entities":{"organization":"O","account":"A","namespace":"N","application":"AP"},
    "provider":{"specification_id":"spec-123","specification_slug":"aws-secrets-manager"}
  }'
  export SPEC_ID="spec-123"

  run bash -c "
    export PATH=$BIN_DIR:\$PATH
    source $PARAMETERS_DIR/utils/log
    source $SCRIPT
    for f in organization account namespace application iam; do
      if [ -s \"\$NP_CACHE_DIR/\$f.json\" ]; then echo \"OK \$f\"; else echo \"MISS \$f\"; fi
    done
    # spec.json should NOT exist when slug is in payload
    if [ -s \"\$NP_CACHE_DIR/spec.json\" ]; then echo \"UNEXPECTED spec\"; else echo \"OK no-spec\"; fi
  "

  assert_equal "$status" "0"
  assert_contains "$output" "OK organization"
  assert_contains "$output" "OK account"
  assert_contains "$output" "OK namespace"
  assert_contains "$output" "OK application"
  assert_contains "$output" "OK iam"
  assert_contains "$output" "OK no-spec"
}
