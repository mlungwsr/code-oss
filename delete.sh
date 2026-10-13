#!/usr/bin/env bash
#
# Delete the Code-OSS + CloudFront stack and wait for completion.
#
# Usage:
#   ./delete.sh [stack-name] [region]
#
# Example:
#   ./delete.sh code-oss us-west-2
#
set -euo pipefail

STACK_NAME="${1:-code-oss}"
REGION="${2:-us-west-2}"

echo "Deleting stack '$STACK_NAME' in '$REGION'..."
aws cloudformation delete-stack \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  && echo "DELETE_COMPLETE" \
  || echo "wait returned non-zero"
