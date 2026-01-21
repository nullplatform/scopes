#!/bin/bash
# =============================================================================
# Traffic Management Script for Azure App Service Deployment Slots
# =============================================================================
# This script helps manage traffic splitting between production and staging slots
# for canary deployments and gradual rollouts.
#
# Usage:
#   ./traffic-management.sh <resource-group> <app-name> <staging-percentage>
#
# Examples:
#   ./traffic-management.sh my-app-rg my-awesome-app 10   # 10% to staging
#   ./traffic-management.sh my-app-rg my-awesome-app 50   # 50% to staging
#   ./traffic-management.sh my-app-rg my-awesome-app 0    # All traffic to production
#   ./traffic-management.sh my-app-rg my-awesome-app swap # Swap slots
# =============================================================================

set -e

RESOURCE_GROUP=$1
APP_NAME=$2
ACTION=$3

if [ -z "$RESOURCE_GROUP" ] || [ -z "$APP_NAME" ] || [ -z "$ACTION" ]; then
    echo "Usage: $0 <resource-group> <app-name> <staging-percentage|swap|status>"
    echo ""
    echo "Commands:"
    echo "  <0-100>  Set percentage of traffic to route to staging slot"
    echo "  swap     Swap staging and production slots"
    echo "  status   Show current traffic distribution"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "Error: Not logged in to Azure. Run 'az login' first."
    exit 1
fi

case $ACTION in
    "status")
        echo "Current traffic distribution for $APP_NAME:"
        az webapp traffic-routing show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APP_NAME" \
            --output table
        ;;
    
    "swap")
        echo "Swapping staging slot with production for $APP_NAME..."
        az webapp deployment slot swap \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APP_NAME" \
            --slot staging \
            --target-slot production
        echo "Swap completed successfully!"
        ;;
    
    *)
        # Validate percentage
        if ! [[ "$ACTION" =~ ^[0-9]+$ ]] || [ "$ACTION" -lt 0 ] || [ "$ACTION" -gt 100 ]; then
            echo "Error: Invalid percentage. Must be between 0 and 100."
            exit 1
        fi
        
        STAGING_PERCENTAGE=$ACTION
        PRODUCTION_PERCENTAGE=$((100 - STAGING_PERCENTAGE))
        
        echo "Setting traffic distribution for $APP_NAME:"
        echo "  Production: ${PRODUCTION_PERCENTAGE}%"
        echo "  Staging: ${STAGING_PERCENTAGE}%"
        
        if [ "$STAGING_PERCENTAGE" -eq 0 ]; then
            # Clear all routing rules (100% to production)
            az webapp traffic-routing clear \
                --resource-group "$RESOURCE_GROUP" \
                --name "$APP_NAME"
        else
            # Set traffic routing to staging
            az webapp traffic-routing set \
                --resource-group "$RESOURCE_GROUP" \
                --name "$APP_NAME" \
                --distribution staging="$STAGING_PERCENTAGE"
        fi
        
        echo "Traffic routing updated successfully!"
        ;;
esac
