# =============================================================================
# App Service Assertions
# Custom assertions for verifying Azure App Service resources in integration tests
# =============================================================================

# -----------------------------------------------------------------------------
# assert_service_plan_exists
# Verify that an App Service Plan exists with the expected SKU
#
# Arguments:
#   $1 - plan_name: Name of the App Service Plan
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
#   $4 - expected_sku: Expected SKU name (optional, e.g., "S1", "P1v3")
# -----------------------------------------------------------------------------
assert_service_plan_exists() {
  local plan_name=$1
  local subscription_id=$2
  local resource_group=$3
  local expected_sku=${4:-}

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/serverfarms/${plan_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')

  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "FAIL: App Service Plan '$plan_name' not found"
    echo "Response: $response"
    return 1
  fi

  if [[ "$actual_name" != "$plan_name" ]]; then
    echo "FAIL: Expected App Service Plan name '$plan_name', got '$actual_name'"
    return 1
  fi

  # Check SKU if provided
  if [[ -n "$expected_sku" ]]; then
    local actual_sku
    actual_sku=$(echo "$response" | jq -r '.sku.name // empty')
    if [[ "$actual_sku" != "$expected_sku" ]]; then
      echo "FAIL: Expected SKU '$expected_sku', got '$actual_sku'"
      return 1
    fi
  fi

  echo "PASS: App Service Plan '$plan_name' exists"
  return 0
}

# -----------------------------------------------------------------------------
# assert_service_plan_not_exists
# Verify that an App Service Plan does NOT exist
#
# Arguments:
#   $1 - plan_name: Name of the App Service Plan
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_service_plan_not_exists() {
  local plan_name=$1
  local subscription_id=$2
  local resource_group=$3

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/serverfarms/${plan_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local error_code
  error_code=$(echo "$response" | jq -r '.error.code // empty')

  if [[ "$error_code" == "ResourceNotFound" ]]; then
    echo "PASS: App Service Plan '$plan_name' does not exist (as expected)"
    return 0
  fi

  # Check if the name field is empty or null (also indicates not found)
  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')
  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "PASS: App Service Plan '$plan_name' does not exist (as expected)"
    return 0
  fi

  echo "FAIL: App Service Plan '$plan_name' still exists"
  echo "Response: $response"
  return 1
}

# -----------------------------------------------------------------------------
# assert_web_app_exists
# Verify that a Linux Web App exists
#
# Arguments:
#   $1 - app_name: Name of the Web App
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_web_app_exists() {
  local app_name=$1
  local subscription_id=$2
  local resource_group=$3

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${app_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')

  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "FAIL: Web App '$app_name' not found"
    echo "Response: $response"
    return 1
  fi

  if [[ "$actual_name" != "$app_name" ]]; then
    echo "FAIL: Expected Web App name '$app_name', got '$actual_name'"
    return 1
  fi

  echo "PASS: Web App '$app_name' exists"
  return 0
}

# -----------------------------------------------------------------------------
# assert_web_app_not_exists
# Verify that a Linux Web App does NOT exist
#
# Arguments:
#   $1 - app_name: Name of the Web App
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_web_app_not_exists() {
  local app_name=$1
  local subscription_id=$2
  local resource_group=$3

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${app_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local error_code
  error_code=$(echo "$response" | jq -r '.error.code // empty')

  if [[ "$error_code" == "ResourceNotFound" ]]; then
    echo "PASS: Web App '$app_name' does not exist (as expected)"
    return 0
  fi

  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')
  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "PASS: Web App '$app_name' does not exist (as expected)"
    return 0
  fi

  echo "FAIL: Web App '$app_name' still exists"
  echo "Response: $response"
  return 1
}

# -----------------------------------------------------------------------------
# assert_azure_app_service_configured
# Comprehensive assertion that verifies both the App Service Plan and Web App exist
#
# Arguments:
#   $1 - app_name: Name of the Web App
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
#   $4 - expected_sku: Expected SKU name (optional)
# -----------------------------------------------------------------------------
assert_azure_app_service_configured() {
  local app_name=$1
  local subscription_id=$2
  local resource_group=$3
  local expected_sku=${4:-}

  local plan_name="${app_name}-plan"

  echo "Verifying App Service configuration..."

  # Check App Service Plan
  if ! assert_service_plan_exists "$plan_name" "$subscription_id" "$resource_group" "$expected_sku"; then
    return 1
  fi

  # Check Web App
  if ! assert_web_app_exists "$app_name" "$subscription_id" "$resource_group"; then
    return 1
  fi

  echo "PASS: Azure App Service '$app_name' is fully configured"
  return 0
}

# -----------------------------------------------------------------------------
# assert_azure_app_service_not_configured
# Comprehensive assertion that verifies both the App Service Plan and Web App are removed
#
# Arguments:
#   $1 - app_name: Name of the Web App
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_azure_app_service_not_configured() {
  local app_name=$1
  local subscription_id=$2
  local resource_group=$3

  local plan_name="${app_name}-plan"

  echo "Verifying App Service resources are removed..."

  # Check Web App is removed
  if ! assert_web_app_not_exists "$app_name" "$subscription_id" "$resource_group"; then
    return 1
  fi

  # Check App Service Plan is removed
  if ! assert_service_plan_not_exists "$plan_name" "$subscription_id" "$resource_group"; then
    return 1
  fi

  echo "PASS: Azure App Service '$app_name' is fully removed"
  return 0
}

# -----------------------------------------------------------------------------
# assert_log_analytics_exists
# Verify that a Log Analytics Workspace exists
#
# Arguments:
#   $1 - workspace_name: Name of the Log Analytics Workspace
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_log_analytics_exists() {
  local workspace_name=$1
  local subscription_id=$2
  local resource_group=$3

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.OperationalInsights/workspaces/${workspace_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')

  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "FAIL: Log Analytics Workspace '$workspace_name' not found"
    return 1
  fi

  echo "PASS: Log Analytics Workspace '$workspace_name' exists"
  return 0
}

# -----------------------------------------------------------------------------
# assert_app_insights_exists
# Verify that Application Insights exists
#
# Arguments:
#   $1 - insights_name: Name of the Application Insights
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_app_insights_exists() {
  local insights_name=$1
  local subscription_id=$2
  local resource_group=$3

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Insights/components/${insights_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')

  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "FAIL: Application Insights '$insights_name' not found"
    return 1
  fi

  echo "PASS: Application Insights '$insights_name' exists"
  return 0
}

# -----------------------------------------------------------------------------
# assert_deployment_slot_exists
# Verify that a deployment slot exists for a Web App
#
# Arguments:
#   $1 - app_name: Name of the Web App
#   $2 - slot_name: Name of the deployment slot
#   $3 - subscription_id: Azure subscription ID
#   $4 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_deployment_slot_exists() {
  local app_name=$1
  local slot_name=$2
  local subscription_id=$3
  local resource_group=$4

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${app_name}/slots/${slot_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')

  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "FAIL: Deployment slot '$slot_name' not found for app '$app_name'"
    echo "Response: $response"
    return 1
  fi

  # The slot name in the response includes the app name (e.g., "myapp/staging")
  local expected_full_name="${app_name}/${slot_name}"
  if [[ "$actual_name" != "$slot_name" && "$actual_name" != "$expected_full_name" ]]; then
    echo "FAIL: Expected slot name '$slot_name', got '$actual_name'"
    return 1
  fi

  echo "PASS: Deployment slot '$slot_name' exists for app '$app_name'"
  return 0
}

# -----------------------------------------------------------------------------
# assert_deployment_slot_not_exists
# Verify that a deployment slot does NOT exist for a Web App
#
# Arguments:
#   $1 - app_name: Name of the Web App
#   $2 - slot_name: Name of the deployment slot
#   $3 - subscription_id: Azure subscription ID
#   $4 - resource_group: Azure resource group name
# -----------------------------------------------------------------------------
assert_deployment_slot_not_exists() {
  local app_name=$1
  local slot_name=$2
  local subscription_id=$3
  local resource_group=$4

  local path="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${app_name}/slots/${slot_name}"
  local response
  response=$(azure_mock "$path" 2>/dev/null)

  local error_code
  error_code=$(echo "$response" | jq -r '.error.code // empty')

  if [[ "$error_code" == "ResourceNotFound" ]]; then
    echo "PASS: Deployment slot '$slot_name' does not exist (as expected)"
    return 0
  fi

  local actual_name
  actual_name=$(echo "$response" | jq -r '.name // empty')
  if [[ -z "$actual_name" || "$actual_name" == "null" ]]; then
    echo "PASS: Deployment slot '$slot_name' does not exist (as expected)"
    return 0
  fi

  echo "FAIL: Deployment slot '$slot_name' still exists for app '$app_name'"
  echo "Response: $response"
  return 1
}

# -----------------------------------------------------------------------------
# assert_azure_app_service_with_slot_configured
# Comprehensive assertion that verifies App Service Plan, Web App, and staging slot exist
#
# Arguments:
#   $1 - app_name: Name of the Web App
#   $2 - subscription_id: Azure subscription ID
#   $3 - resource_group: Azure resource group name
#   $4 - expected_sku: Expected SKU name (optional)
#   $5 - slot_name: Name of the deployment slot (default: "staging")
# -----------------------------------------------------------------------------
assert_azure_app_service_with_slot_configured() {
  local app_name=$1
  local subscription_id=$2
  local resource_group=$3
  local expected_sku=${4:-}
  local slot_name=${5:-staging}

  echo "Verifying App Service configuration with staging slot..."

  # First check base App Service configuration
  if ! assert_azure_app_service_configured "$app_name" "$subscription_id" "$resource_group" "$expected_sku"; then
    return 1
  fi

  # Check deployment slot
  if ! assert_deployment_slot_exists "$app_name" "$slot_name" "$subscription_id" "$resource_group"; then
    return 1
  fi

  echo "PASS: Azure App Service '$app_name' with slot '$slot_name' is fully configured"
  return 0
}
