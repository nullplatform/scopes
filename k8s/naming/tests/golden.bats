#!/usr/bin/env bats

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	RENDER_DIR="$(mktemp -d)"
}

teardown() {
	if [ -n "${RENDER_DIR:-}" ]; then rm -r "$RENDER_DIR"; fi
}

@test "golden: normal context renders byte-identically" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal-raw.json" "$RENDER_DIR"
	run diff -r "$PROJECT_ROOT/k8s/naming/tests/goldens/normal" "$RENDER_DIR"
	[ "$status" -eq 0 ]
}

@test "golden: long context renders byte-identically" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-long-raw.json" "$RENDER_DIR"
	run diff -r "$PROJECT_ROOT/k8s/naming/tests/goldens/long" "$RENDER_DIR"
	[ "$status" -eq 0 ]
}

@test "golden: full context renders byte-identically" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-full-raw.json" "$RENDER_DIR"
	run diff -r "$PROJECT_ROOT/k8s/naming/tests/goldens/full" "$RENDER_DIR"
	[ "$status" -eq 0 ]
}

@test "golden: renders all fifteen templates" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal-raw.json" "$RENDER_DIR"
	run bash -c "ls '$RENDER_DIR' | wc -l | tr -d ' '"
	assert_equal "$output" "15"
}
