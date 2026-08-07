#!/usr/bin/env bats
# =============================================================================
# Unit tests for the tracing hooks in k8s/logging
#
# (Lives under utils/tests because the runner discovers k8s/<module>/tests;
# the file under test is k8s/logging.)
#
# The contract under test: with the platform's trace context present, every
# `log error` and every uncaught failure lands ON the workflow step as a
# tracing.error facet, waits report progress — and with anything missing, the
# behavior is byte-identical to plain logging.
# =============================================================================

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"

	export LOGGING="$PROJECT_ROOT/k8s/logging"

	# A traced environment, as the np CLI provides it: NP_TRACE points at the
	# step this fragment runs inside; the state dir is per-test; the endpoint is
	# unroutable so nothing ever leaves the machine and flushes fail fast.
	export NP_TRACE="1|trace-9|scope-provision-42~apply-manifests@0.0"
	export NP_API_KEY="test-key"
	export NP_TRACE_DIR="$BATS_TEST_TMPDIR/nptrace"
	export NP_TRACE_BASE_URL="http://127.0.0.1:1"
	export NP_TRACE_AUTH_URL="http://127.0.0.1:1"
	export NP_TRACE_FLUSH_TIMEOUT=1
	export NP_TRACE_MAX_RETRIES=0
}

teardown() {
	unset NP_TRACE NP_API_KEY NP_TRACE_DIR NP_TRACE_BASE_URL NP_TRACE_AUTH_URL
	unset NP_TRACE_FLUSH_TIMEOUT NP_TRACE_MAX_RETRIES
}

# Run a snippet in a fresh bash with logging sourced, then print every spooled
# envelope (the spool is the wire: it is what the API would receive).
run_logged() {
	run "$BASH" -c "
		source '$LOGGING'
		$1
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
}

@test "log error lands as a tracing.error facet on the current step" {
	run_logged 'log error "❌ kubectl apply failed: forbidden"'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"run_id":"scope-provision-42~apply-manifests@0.0"'
	echo "$output" | grep -q '"tracing.error"'
	echo "$output" | grep -q 'kubectl apply failed: forbidden'
}

@test "the error attaches to the step CURRENT at the moment it happened" {
	# NP_TRACE moves between steps; adoption is per-call, so a later error must
	# land on the later step.
	run_logged '
		log error "first failure"
		export NP_TRACE="1|trace-9|scope-provision-42~wait-for-alb@0.0"
		log error "second failure"
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"first failure"' | grep -q 'apply-manifests@0.0'
	echo "$output" | grep '"second failure"' | grep -q 'wait-for-alb@0.0'
}

@test "an uncaught command failure surfaces the failing command" {
	run "$BASH" -c "
		source '$LOGGING'
		"$BASH" -c 'exit 7'   # a real failing command, no log error anywhere
	" || true
	run "$BASH" -c "
		source '$LOGGING'
		trap - EXIT        # neutralize for inspection after the inner shell
		( source '$LOGGING'; bash -c 'exit 7' ) || true
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"tracing.error"'
	echo "$output" | grep -q 'exit 7'
}

@test "a log error already recorded is not shadowed by the exit trap" {
	run "$BASH" -c "
		( source '$LOGGING'; log error 'the real reason'; exit 3 ) || true
		source '$LOGGING'; trap - EXIT ERR
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'the real reason'
	# exactly one error facet: the generic exit report stood down
	[ "$(echo "$output" | grep -c 'tracing.error')" -eq 1 ]
}

@test "wait heartbeat marks the step waiting with progress labels" {
	run_logged 'np_scope_wait_heartbeat "alb-active" 90 300 "pending"'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"status":"waiting"'
	echo "$output" | grep -q '"wait.what":"alb-active"'
	echo "$output" | grep -q '"wait.elapsed_s":"90"'
	echo "$output" | grep -q '"wait.timeout_s":"300"'
}

@test "without NP_TRACE, logging is byte-identical to plain logging" {
	unset NP_TRACE
	run "$BASH" -c "source '$LOGGING'; log error 'plain'; log info 'hello'"
	[ "$status" -eq 0 ]
	[ "$output" = "plain
hello" ]
	[ ! -d "$NP_TRACE_DIR/spool" ] || [ -z "$(ls -A "$NP_TRACE_DIR/spool" 2>/dev/null)" ]
}

@test "without NP_API_KEY, logging is byte-identical to plain logging" {
	unset NP_API_KEY
	run "$BASH" -c "source '$LOGGING'; log error 'plain'"
	[ "$status" -eq 0 ]
	[ "$output" = "plain" ]
	[ ! -d "$NP_TRACE_DIR/spool" ] || [ -z "$(ls -A "$NP_TRACE_DIR/spool" 2>/dev/null)" ]
}

@test "heartbeat is a defined no-op when the workflow is untraced" {
	unset NP_TRACE
	run "$BASH" -c "source '$LOGGING'; np_scope_wait_heartbeat what 1 2; echo rc=\$?"
	[ "$status" -eq 0 ]
	[[ "$output" == *"rc=0"* ]]
}

@test "stdout and stderr routing of log() is unchanged when traced" {
	run "$BASH" -c "source '$LOGGING'; log info 'to-stdout' 2>/dev/null"
	[[ "$output" == *"to-stdout"* ]]
	run "$BASH" -c "source '$LOGGING'; log error 'to-stderr' 2>&1 >/dev/null"
	[[ "$output" == *"to-stderr"* ]]
}
