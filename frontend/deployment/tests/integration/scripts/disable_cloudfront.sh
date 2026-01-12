#!/bin/bash
# Disable a CloudFront distribution by comment
# Usage: disable_cloudfront.sh "Distribution comment"

set -e

COMMENT="$1"
MOTO_ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5555}"

if [ -z "$COMMENT" ]; then
  echo "Usage: $0 <distribution-comment>"
  exit 1
fi

echo "Looking for CloudFront distribution with comment: $COMMENT"

# Get distribution ID by comment
DIST_ID=$(aws --endpoint-url="$MOTO_ENDPOINT" cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='$COMMENT'].Id" \
  --output text 2>/dev/null)

if [ -z "$DIST_ID" ] || [ "$DIST_ID" = "None" ]; then
  echo "No distribution found with comment: $COMMENT"
  exit 0
fi

echo "Found distribution: $DIST_ID"

# Get current ETag
ETAG=$(aws --endpoint-url="$MOTO_ENDPOINT" cloudfront get-distribution \
  --id "$DIST_ID" \
  --query "ETag" \
  --output text)

echo "Current ETag: $ETAG"

# Get current config and save to temp file
TEMP_CONFIG=$(mktemp)
aws --endpoint-url="$MOTO_ENDPOINT" cloudfront get-distribution-config \
  --id "$DIST_ID" \
  --query "DistributionConfig" \
  > "$TEMP_CONFIG"

# Set Enabled to false
jq '.Enabled = false' "$TEMP_CONFIG" > "${TEMP_CONFIG}.new"
mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"

echo "Disabling distribution..."

# Update distribution to disabled
aws --endpoint-url="$MOTO_ENDPOINT" cloudfront update-distribution \
  --id "$DIST_ID" \
  --distribution-config "file://$TEMP_CONFIG" \
  --if-match "$ETAG" \
  > /dev/null

rm -f "$TEMP_CONFIG"

echo "Distribution $DIST_ID disabled successfully"
