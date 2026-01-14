#!/bin/bash
account_id=""
scope_type_name=""
dry_run=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --account-id) account_id="$2"; shift ;;
    --scope-type-name) scope_type_name="$2"; shift ;;
    --dry-run) dry_run=true ;;
  esac
  shift
done

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Scope Deletion Tool${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}\n"

# Validate account_id
if [[ -z "$account_id" ]]; then
	echo -e "${RED}✗ Missing --account-id flag${NC}"
	exit 1
else
	echo -e "${GREEN}✓${NC} Found account-id: ${BOLD}$account_id${NC}"
fi

# Validate scope_type_name
if [[ -z "$scope_type_name" ]]; then
	echo -e "${RED}✗ Missing --scope-type-name flag${NC}"
	echo "  You must use the name it appears on the ui (it is not a slug)"
	exit 1
else
	echo -e "${GREEN}✓${NC} Found scope-type-name: ${BOLD}$scope_type_name${NC}"
fi

# Show dry-run mode if enabled
if [[ "$dry_run" == true ]]; then
	echo -e "${YELLOW}⚠${NC}  Running in ${BOLD}DRY RUN${NC} mode - no changes will be made"
fi

echo -e "\n${BLUE}→${NC} Deleting all '${BOLD}$scope_type_name${NC}' scopes in account '${BOLD}$account_id${NC}'"

account_nrn=$(np account read --id "$account_id" --format json | jq -r .nrn)
echo -e "${GRAY}  Looking for scope type in nrn=$account_nrn${NC}"

scope_type=$(np scope type list --nrn "$account_nrn" --name "$scope_type_name" --format json | jq ".results[0]")
if [[ $scope_type == "null" ]]; then
	echo -e "${RED}✗ No scope type with name=$scope_type_name and nrn=$account_nrn${NC}"
	exit 1
fi

scope_type_id=$(echo $scope_type | jq -r .id)
service_id=$(echo $scope_type | jq -r .provider_id)
echo -e "${GREEN}✓${NC} Found scope type ${GRAY}[id=$scope_type_id, provider_id=$service_id]${NC}\n"

namespaces=$(np namespace list --account_id "$account_id" --format json)

# Counter for dry-run
total_scopes=0

# Iterate through namespaces using process substitution instead of pipe
while IFS='|' read -r namespace_id namespace_name; do
  echo -e "\n${BLUE}📦 Namespace:${NC} ${BOLD}$namespace_name${NC} ${GRAY}(id=$namespace_id)${NC}"
  
  # Get applications for this namespace
  applications=$(np application list --namespace_id "$namespace_id" --format json)
  
  # Check if there are any applications
  app_count=$(echo "$applications" | jq -r '.results | length')
  if [[ $app_count -eq 0 ]]; then
    echo -e "   ${GRAY}└─ No applications in this namespace${NC}"
    continue
  fi
  
  # Iterate through applications
  while IFS='|' read -r application_id application_name; do
    echo -e "   ${BLUE}├─ Application:${NC} ${BOLD}$application_name${NC} ${GRAY}(id=$application_id)${NC}"
    
    # Get scopes for this application
    scopes=$(np scope list --application_id "$application_id" --format json)
    
    # Check if there are any matching scopes
    matching_scopes=$(echo "$scopes" | jq -r --arg service_id "$service_id" \
      '.results[] | select(.status != "deleted" and .provider == $service_id) | "\(.id)|\(.name)"')
    
    if [[ -z "$matching_scopes" ]]; then
      echo -e "   ${GRAY}│  └─ No matching scopes${NC}"
      continue
    fi
    
    # Filter and iterate through scopes
    while IFS='|' read -r scope_id scope_name; do
      echo -e "   ${BLUE}│  ├─ Scope:${NC} ${BOLD}$scope_name${NC} ${GRAY}(id=$scope_id)${NC}"
      
      if [[ "$dry_run" == true ]]; then
        echo -e "   ${YELLOW}│  └─ ⚠ Would be processed (dry run)${NC}"
        ((total_scopes++))
      else
        # Execute all three commands independently
        echo -e "   ${GRAY}│  │  ├─ Setting status to 'deleting'...${NC}"
        np scope patch --id "$scope_id" --body '{"status": "deleting"}' > /dev/null 2>&1
        
        echo -e "   ${GRAY}│  │  ├─ Setting status to 'failed'...${NC}"
        np scope patch --id "$scope_id" --body '{"status": "failed"}' > /dev/null 2>&1
        
        echo -e "   ${GRAY}│  │  └─ Force deleting scope...${NC}"
        np scope delete --id "$scope_id" --force > /dev/null 2>&1
        
        if [[ $? -eq 0 ]]; then
          echo -e "   ${GREEN}│  └─ ✓ Successfully processed${NC}"
          ((total_scopes++))
        else
          echo -e "   ${RED}│  └─ ✗ Failed to process${NC}"
        fi
      fi
    done < <(echo "$matching_scopes")
  done < <(echo "$applications" | jq -r '.results[] | "\(.id)|\(.name)"')
done < <(echo "$namespaces" | jq -r '.results[] | "\(.id)|\(.name)"')

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════${NC}"
if [[ "$dry_run" == true ]]; then
  echo -e "${YELLOW}⚠${NC}  Dry run completed - found ${BOLD}$total_scopes${NC} scope(s) to delete - no changes were made"
else
  echo -e "${GREEN}✓${NC} Process completed - ${BOLD}$total_scopes${NC} scope(s) processed"
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
