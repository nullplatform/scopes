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

@test "golden: pdb selector matches the deployment's pod labels" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-full-raw.json" "$RENDER_DIR"
	# An unrendered PDB or an empty selector would pass the check below vacuously.
	run yq -e '.spec.selector.matchLabels | length > 0' "$RENDER_DIR/k8s-pdb.yaml"
	[ "$status" -eq 0 ]
	# A selector that matches no pods is valid to the API server, so the PDB
	# would silently protect nothing.
	local unmatched
	unmatched="$(yq ea -N '
		select(fi == 0).spec.template.metadata.labels as $pod
		| select(fi == 1).spec.selector.matchLabels
		| to_entries | .[] | select($pod[.key] != .value) | .key
	' "$RENDER_DIR/k8s-deployment.yaml" "$RENDER_DIR/k8s-pdb.yaml")"
	assert_equal "$unmatched" ""
}

@test "golden: renders all fifteen templates" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-normal-raw.json" "$RENDER_DIR"
	run bash -c "ls '$RENDER_DIR' | wc -l | tr -d ' '"
	assert_equal "$output" "15"
}

@test "golden: service-to-service shared mode renders the stable Service and one internal HTTPRoute per HTTP port" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-s2s-shared-raw.json" "$RENDER_DIR"
	for f in k8s-istio-initial-httproute.yaml k8s-istio-blue-green-httproute.yaml; do
		run diff "$PROJECT_ROOT/k8s/naming/tests/goldens/s2s-shared/$f" "$RENDER_DIR/$f"
		[ "$status" -eq 0 ]
	done
}

@test "golden: service-to-service dedicated mode adds the short hostnames" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-s2s-dedicated-raw.json" "$RENDER_DIR"
	for f in k8s-istio-initial-httproute.yaml k8s-istio-blue-green-httproute.yaml; do
		run diff "$PROJECT_ROOT/k8s/naming/tests/goldens/s2s-dedicated/$f" "$RENDER_DIR/$f"
		[ "$status" -eq 0 ]
	done
}

@test "golden: service-to-service objects carry no deployment_id, so deployment cleanup never removes them" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-s2s-shared-raw.json" "$RENDER_DIR"
	run yq ea -N 'select(.metadata.labels["nullplatform.io/stable-service"] == "true") | .metadata.labels | has("deployment_id")' \
		"$RENDER_DIR/k8s-istio-blue-green-httproute.yaml"
	assert_equal "$output" "false
false
false"
}

@test "golden: service-to-service renders valid multi-document YAML" {
	"$PROJECT_ROOT/k8s/naming/tests/render_golden.sh" \
		"$PROJECT_ROOT/k8s/naming/tests/fixtures/context-s2s-dedicated-raw.json" "$RENDER_DIR"
	run yq ea -N '.kind' "$RENDER_DIR/k8s-istio-initial-httproute.yaml"
	assert_equal "$output" "HTTPRoute
Service
HTTPRoute
HTTPRoute
HTTPRoute"
}
