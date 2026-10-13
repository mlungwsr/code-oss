#!/usr/bin/env bash
#
# Deploy the Code-OSS + CloudFront stack.
#
# Usage:
#   ./deploy.sh <vpc-id> <subnet-id> [stack-name] [region]
#
# Example:
#   ./deploy.sh vpc-0a03b5275331952f5 subnet-00556ca730a258128 code-oss us-west-2
#
set -euo pipefail

VPC_ID="${1:?Usage: ./deploy.sh <vpc-id> <subnet-id> [stack-name] [region]}"
SUBNET_ID="${2:?Usage: ./deploy.sh <vpc-id> <subnet-id> [stack-name] [region]}"
STACK_NAME="${3:-code-oss}"
REGION="${4:-us-west-2}"
TEMPLATE="code-oss-cloudfront.yaml"

echo "Deploying stack '$STACK_NAME' in '$REGION'..."
aws cloudformation create-stack \
  --stack-name "$STACK_NAME" \
  --template-body "file://${TEMPLATE}" \
  --capabilities CAPABILITY_IAM \
  --parameters \
      ParameterKey=VpcId,ParameterValue="$VPC_ID" \
      ParameterKey=SubnetId,ParameterValue="$SUBNET_ID" \
  --region "$REGION"

echo "Waiting for stack creation to complete (this includes CloudFront + instance bootstrap)..."
aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  && echo "CREATE_COMPLETE" \
  || { echo "Stack did not reach CREATE_COMPLETE; check events."; exit 1; }

echo
echo "Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' \
  --output table
