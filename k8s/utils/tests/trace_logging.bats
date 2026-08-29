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
	# exactly one error facet ON THE STEP: the generic exit report stood down
	# (the run-level mirror is a separate node and is asserted elsewhere)
	[ "$(echo "$output" | grep 'apply-manifests@0.0"' | grep -c 'tracing.error')" -eq 1 ]
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

# --- sub-steps --------------------------------------------------------------

@test "step_begin opens a keyed sub-step under the platform step" {
	# The title rides the next lifecycle emit (own-node enrichment is bagged,
	# not emitted eagerly), so close the step to see it on the wire.
	run_logged 'np_scope_step_begin wait-alb-active --title "Wait for the ALB"; np_scope_step_end 0'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"run_id":"scope-provision-42~apply-manifests@0.0~wait-alb-active@0.0"'
	echo "$output" | grep -q '"status":"started"'
	echo "$output" | grep -q 'Wait for the ALB'
}

@test "step_end 0 completes the sub-step" {
	run_logged 'np_scope_step_begin wait-alb-active; np_scope_step_end 0'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"status":"completed"' | grep -q 'wait-alb-active@0.0'
}

@test "step_end with a non-zero rc fails the sub-step with the message" {
	run_logged 'np_scope_step_begin wait-alb-active; np_scope_step_end 1 "ALB never came up"'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"status":"failed"' | grep -q 'wait-alb-active@0.0'
	echo "$output" | grep -q 'ALB never came up'
}

@test "step_timeout closes the sub-step as timed_out, not failed" {
	run_logged 'np_scope_step_begin wait-alb-active; np_scope_step_timeout "deadline hit"'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"status":"timed_out"' | grep -q 'wait-alb-active@0.0'
	echo "$output" | grep -q 'deadline hit'
	! echo "$output" | grep '"status":"failed"' | grep -q 'wait-alb-active@0.0'
}

@test "while a sub-step is open, log error attaches to IT, not the platform step" {
	# The facet rides the step's closing emit — and because a real message was
	# already recorded, the close adds no generic shadow next to it.
	run_logged 'np_scope_step_begin wait-alb-active; log error "quota exceeded"; np_scope_step_end 1'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"quota exceeded"' | grep -q 'wait-alb-active@0.0'
	! echo "$output" | grep -q 'phase exited with status'
}

@test "while a sub-step is open, heartbeats attach to it" {
	run_logged 'np_scope_step_begin wait-alb-active; np_scope_wait_heartbeat "alb-active" 30 300 "pending"'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"status":"waiting"' | grep -q 'wait-alb-active@0.0'
}

@test "heartbeat extra k=v pairs land as labels" {
	run_logged 'np_scope_wait_heartbeat "deployment-active" 20 600 "progressing" "wait.ready=2" "wait.desired=5"'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"wait.ready":"2"'
	echo "$output" | grep -q '"wait.desired":"5"'
}

@test "a sub-step left open when the platform moves on is forgotten, not reused" {
	run_logged '
		np_scope_step_begin wait-alb-active
		export NP_TRACE="1|trace-9|scope-provision-42~wait-for-alb@0.0"
		log error "late failure"
	'
	[ "$status" -eq 0 ]
	# the error lands on the NEW platform step, not the stale sub-step
	echo "$output" | grep '"late failure"' | grep -q 'scope-provision-42~wait-for-alb@0.0"'
}

@test "a sub-step still open when the shell dies inherits the failure" {
	run "$BASH" -c "
		( source '$LOGGING'; np_scope_step_begin wait-alb-active; log error 'the real reason'; exit 3 ) || true
		source '$LOGGING'; trap - EXIT ERR
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
	[ "$status" -eq 0 ]
	echo "$output" | grep '"status":"failed"' | grep -q 'wait-alb-active@0.0'
	echo "$output" | grep '"the real reason"' | grep -q 'wait-alb-active@0.0'
	# no generic 'phase exited' shadow next to the real message
	! echo "$output" | grep -q 'phase exited with status'
}

@test "opening a second sub-step completes the first — phases are sequential" {
	run_logged 'np_scope_step_begin phase-one; np_scope_step_begin phase-two; np_scope_step_end 0'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"status":"completed"' | grep -q 'phase-one@0.0'
	echo "$output" | grep '"status":"completed"' | grep -q 'phase-two@0.0'
}

@test "step functions are defined no-ops when the workflow is untraced" {
	unset NP_TRACE
	run "$BASH" -c "source '$LOGGING'; np_scope_step_begin x; np_scope_step_end 1; np_scope_step_timeout; echo rc=\$?"
	[ "$status" -eq 0 ]
	[[ "$output" == *"rc=0"* ]]
}

@test "step_end without an open sub-step is a no-op" {
	run_logged 'np_scope_step_end 1 "nothing open"'
	[ "$status" -eq 0 ]
	! echo "$output" | grep -q 'nothing open'
}

# --- lineage ----------------------------------------------------------------

@test "produces records the edge and the pointer on the current step" {
	run_logged 'np_scope_produces "dns-record:api.example.com" dns_record "api.example.com"'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"edge.produces"' | grep -q '"id":"dns-record:api.example.com"'
	echo "$output" | grep -q '"tracing.binding":{"kind":"pointer","name":"dns_record","uri":"api.example.com"}'
	# foreign re-emit carries the io facet on the adopted step
	echo "$output" | grep '"tracing.output"' | grep -q 'apply-manifests@0.0'
}

@test "consumes records the cross-flow image edge" {
	run_logged 'np_scope_consumes "docker-image:registry.example.com/app:1.2" image "registry.example.com/app:1.2"'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"edge.consumes"' | grep -q '"id":"docker-image:registry.example.com/app:1.2"'
}

@test "lineage inside an open sub-step attaches to the sub-step" {
	run_logged '
		np_scope_step_begin wait-alb-active
		np_scope_consumes "load-balancer:arn:aws:elb:demo" load_balancer "arn:aws:elb:demo"
		np_scope_step_end 0
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"edge.consumes"' | grep -q 'wait-alb-active@0.0'
}

@test "kubectl apply output becomes workload/service/ingress lineage" {
	run_logged '
		np_scope_k8s_applied "ns-42" "deployment.apps/d-1-2 created
service/s-1-2 configured
ingress.networking.k8s.io/i-1-2 created
secret/sec-1 created"
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"id":"k8s-deployment:ns-42/d-1-2"'
	echo "$output" | grep -q '"id":"k8s-service:ns-42/s-1-2"'
	echo "$output" | grep -q '"id":"k8s-ingress:ns-42/i-1-2"'
	# kinds outside the platform lineage model are not datasets
	! echo "$output" | grep -q 'sec-1'
}

@test "affordance and progress land as their core facets" {
	run_logged '
		np_scope_affordance "{\"kind\":\"deploy-log\",\"application_id\":\"7\"}"
		np_scope_progress 3 10 count
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"tracing.affordances":\[{"kind":"deploy-log","application_id":"7"}\]'
	echo "$output" | grep -q '"tracing.progress":{"current":3,"target":10,"unit":"instances"}'
}

@test "lineage helpers are defined no-ops when untraced" {
	unset NP_TRACE
	run "$BASH" -c "source '$LOGGING'; np_scope_produces d:1 n u; np_scope_consumes d:2; np_scope_affordance '{\"kind\":\"x\"}'; np_scope_progress 1 2; np_scope_k8s_applied ns 'deployment.apps/x created'; echo rc=\$?"
	[ "$status" -eq 0 ]
	[[ "$output" == *"rc=0"* ]]
}

# --- narrative: inline io, explain, structured errors ------------------------

@test "inline output and explain land on the open sub-step" {
	run_logged '
		np_scope_step_begin wait-deployment-active
		np_scope_output instances "{\"healthy\":2,\"desired\":3}"
		np_scope_explain --title "Instance health check" --severity warn --what "Waiting for 2/3 instances to be healthy"
		np_scope_step_end 0
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep '"tracing.output"' | grep -q 'wait-deployment-active@0.0'
	echo "$output" | grep -q '"value":{"healthy":2,"desired":3}'
	echo "$output" | grep -q '"severity":"warn"'
	echo "$output" | grep -q 'Waiting for 2/3 instances to be healthy'
}

@test "the traffic switch set lands whole on the current step" {
	run_logged '
		np_scope_labels "deployment.id=777" "action=traffic-switch"
		np_scope_explain --title "Switch traffic for deployment 777" --what "Switching blue/green traffic for deployment 777 from 0% to 100%"
		np_scope_affordance "{\"kind\":\"traffic-switch\",\"deployment_id\":\"777\",\"current_traffic\":100,\"new_traffic\":100,\"old_traffic\":0,\"target_traffic\":100}"
		np_scope_input traffic "{\"from\":0,\"desired\":100}"
		np_scope_output traffic "{\"switched\":100}"
		np_scope_progress 100 100 percent
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"kind":"traffic-switch"'
	echo "$output" | grep -q '"tracing.input":\[{"kind":"inline","name":"traffic","value":{"from":0,"desired":100}}\]'
	echo "$output" | grep -q '"tracing.output":\[{"kind":"inline","name":"traffic","value":{"switched":100}}\]'
	echo "$output" | grep -q '"tracing.progress":{"current":100,"target":100,"unit":"percent"}'
	echo "$output" | grep -q '"action":"traffic-switch"'
}

@test "np_scope_error carries structured details and stands down the exit trap" {
	run "$BASH" -c "
		( source '$LOGGING'; np_scope_error 'gave up' '{\"instances\":{\"healthy\":1,\"desired\":3}}'; exit 3 ) || true
		source '$LOGGING'; trap - EXIT ERR
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"details":{"instances":{"healthy":1,"desired":3}}'
	[ "$(echo "$output" | grep 'apply-manifests@0.0"' | grep -c 'tracing.error')" -eq 1 ]
}

@test "narrative helpers are defined no-ops when untraced" {
	unset NP_TRACE
	run "$BASH" -c "source '$LOGGING'; np_scope_output x '{}'; np_scope_input x '{}'; np_scope_explain --title t; np_scope_error m; np_scope_labels a=b; echo rc=\$?"
	[ "$status" -eq 0 ]
	[[ "$output" == *"rc=0"* ]]
}

@test "a fatal exit mirrors the real reason onto the RUN, one level up" {
	run "$BASH" -c "
		( source '$LOGGING'; log error 'the real reason'; exit 3 ) || true
		source '$LOGGING'; trap - EXIT ERR
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
	[ "$status" -eq 0 ]
	# the step carries it...
	echo "$output" | grep '"the real reason"' | grep -q 'scope-provision-42~apply-manifests@0.0"'
	# ...and so does the run (the step path minus its last segment)
	echo "$output" | grep '"the real reason"' | grep -q '"run_id":"scope-provision-42"'
}

@test "a run-level NP_TRACE (no step segment) mirrors nowhere extra" {
	run "$BASH" -c "
		export NP_TRACE='1|trace-9|scope-provision-42'
		( source '$LOGGING'; log error 'root failure'; exit 3 ) || true
		source '$LOGGING'; trap - EXIT ERR
		for f in \"\$NP_TRACE_DIR\"/spool/*.json \"\$NP_TRACE_DIR\"/failed/*.json; do
			[ -f \"\$f\" ] && cat \"\$f\" && echo
		done
		true
	"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | grep -c '"root failure"')" -eq 1 ]
}

@test "a hint burst never shadows the cause: first message wins, hints ride as evidence" {
	run_logged '
		log error "❌ HostedZone not found (AccessDenied)"
		log error "💡 Possible causes:"
		log error "   • The role lacks route53:ListHostedZones"
	'
	[ "$status" -eq 0 ]
	# every emission of the burst carries the CAUSE as the message — with the
	# console decoration (indentation, ❌ marker) stripped for the trace
	! echo "$output" | grep '"tracing.error"' | grep -q '"message":"💡'
	echo "$output" | grep -q '"message":"HostedZone not found (AccessDenied)","details":{"hints":\["💡 Possible causes:","• The role lacks route53:ListHostedZones"\]}'
}

@test "the first error cause is stated to the workflow engine via np_step_error" {
	STATED="$BATS_TEST_TMPDIR/stated"
	export STATED
	run_logged '
		np_step_error() { printf "%s\n" "$1" >>"$STATED"; }
		log error "❌ HostedZone not found (AccessDenied)"
		log error "💡 a hint, not a cause"
	'
	[ "$status" -eq 0 ]
	run cat "$STATED"
	assert_equal "$output" "HostedZone not found (AccessDenied)"
}

@test "the exit trap's synthetic message is never stated as a cause" {
	STATED="$BATS_TEST_TMPDIR/stated"
	export STATED
	run_logged '
		np_step_error() { printf "%s\n" "$1" >>"$STATED"; }
		( exit 3 )   # arm LAST_ERR without any log error, then die unhandled
		exit 3
	'
	[ "$status" -eq 3 ]
	[ ! -s "$STATED" ]
}

@test "trace errors carry the cause stripped of console decoration" {
	run_logged '
		log error "   ❌ Failed to find IAM role: An error occurred (NoSuchEntity)"
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '"message":"Failed to find IAM role: An error occurred (NoSuchEntity)"'
	! echo "$output" | grep '"tracing.error"' | grep -q '"message":"   ❌'
}

@test "a new step starts a new error burst" {
	run_logged '
		log error "first cause"
		export NP_TRACE="1|trace-9|scope-provision-42~create-dns@0.0"
		log error "second cause"
		log error "a hint for the second"
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep 'create-dns@0.0' | grep '"tracing.error"' | grep -q '"message":"second cause"'
	echo "$output" | grep -q '"hints":\["a hint for the second"\]'
	! echo "$output" | grep 'create-dns@0.0' | grep -q '"message":"first cause"'
}

@test "a traced run with credentials but NO bundled SDK warns loudly instead of degrading silently" {
	run "$BASH" -c '
		export NP_TRACE="1|trace-1|run-1@0.0"
		export NP_API_KEY="key"
		NP_SCOPES_TEST_ROOT="$BATS_TEST_TMPDIR/empty-bundle"
		mkdir -p "$NP_SCOPES_TEST_ROOT/k8s"
		cp "'"$LOGGING"'" "$NP_SCOPES_TEST_ROOT/k8s/logging"
		source "$NP_SCOPES_TEST_ROOT/k8s/logging"
		log info "workflow proceeds"
	'
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "tracing SDK not bundled"
	echo "$output" | grep -q "workflow proceeds"
}

@test "an untraced run (no NP_TRACE) stays silent about the SDK" {
	run "$BASH" -c '
		unset NP_TRACE
		export NP_API_KEY="key"
		NP_SCOPES_TEST_ROOT="$BATS_TEST_TMPDIR/empty-bundle2"
		mkdir -p "$NP_SCOPES_TEST_ROOT/k8s"
		cp "'"$LOGGING"'" "$NP_SCOPES_TEST_ROOT/k8s/logging"
		source "$NP_SCOPES_TEST_ROOT/k8s/logging"
		log info "plain logging"
	'
	[ "$status" -eq 0 ]
	! echo "$output" | grep -q "tracing SDK not bundled"
}
