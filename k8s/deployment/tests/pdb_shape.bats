#!/usr/bin/env bats
# =============================================================================
# Structural tests for pdb.yaml.tpl's deployment_id label.
#
# delete_cluster_objects deletes deployment,service,hpa,ingress,pdb,secret,
# configmap with `-l deployment_id=<id>`. A PodDisruptionBudget with no
# deployment_id label never matches that selector, so it survives every
# cleanup and accumulates, one per deployment, in every scope with
# pod_disruption_budget_enabled: true.
# =============================================================================

setup() {
	export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
	source "$PROJECT_ROOT/testing/assertions.sh"
	export TEMPLATE="$PROJECT_ROOT/k8s/deployment/templates/pdb.yaml.tpl"
}

render_pdb() {
	local context="$1" out="$2"
	gomplate -c .="$context" --file "$TEMPLATE" --out "$out"
}

write_context() {
	local deployment_id="$1" out="$2"
	jq -n --arg deployment_id "$deployment_id" '{
		pdb_enabled: "true",
		pdb_max_unavailable: "25%",
		k8s_namespace: "nullplatform",
		account: {slug: "acme"},
		namespace: {slug: "payments"},
		application: {slug: "checkout-api"},
		scope: {slug: "production"},
		deployment: {id: $deployment_id},
		names: {pdb: ("pdb-d-123456-" + $deployment_id), deployment: ("d-123456-" + $deployment_id)},
		k8s_modifiers: {}
	}' > "$out"
}

@test "pdb: carries a deployment_id label matching the deployment" {
	local ctx="$BATS_TEST_TMPDIR/context.json"
	write_context "789012" "$ctx"

	local out="$BATS_TEST_TMPDIR/pdb.yaml"
	render_pdb "$ctx" "$out"

	local label
	label="$(yq -N '.metadata.labels.deployment_id' "$out")"
	assert_equal "$label" "789012"
}

@test "pdb: its deployment_id label matches what delete_cluster_objects selects on" {
	local ctx="$BATS_TEST_TMPDIR/context.json"
	write_context "789012" "$ctx"

	local out="$BATS_TEST_TMPDIR/pdb.yaml"
	render_pdb "$ctx" "$out"

	# delete_cluster_objects deletes with `-l deployment_id=$DEPLOYMENT_ID_TO_DELETE`,
	# and DEPLOYMENT_ID_TO_DELETE is exactly .deployment.id from the same
	# context that built this PDB. The selector matches only if the rendered
	# label carries that same value.
	local deployment_id_to_delete="789012"
	local label
	label="$(yq -N '.metadata.labels.deployment_id' "$out")"
	assert_equal "$label" "$deployment_id_to_delete"
}
