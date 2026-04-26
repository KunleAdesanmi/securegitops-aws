#!/usr/bin/env bash
# Bootstraps the Terraform remote backend (S3 + DynamoDB).
# Idempotent: safe to re-run.
set -euo pipefail

REGION="${1:-eu-west-2}"
BUCKET="${2:-securegitops-tfstate-$(aws sts get-caller-identity --query Account --output text)}"
TABLE="${3:-securegitops-tflock}"

echo "Creating state bucket ${BUCKET} in ${REGION}..."
aws s3api create-bucket \
  --bucket "${BUCKET}" \
  --region "${REGION}" \
  --create-bucket-configuration LocationConstraint="${REGION}" 2>/dev/null || echo "Bucket exists, continuing."

# Block all public access — state files contain secrets.
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Versioning lets us recover from accidental state corruption.
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

# Server-side encryption with AWS-managed keys (good enough for state).
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "Creating lock table ${TABLE}..."
aws dynamodb create-table \
  --table-name "${TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}" 2>/dev/null || echo "Table exists, continuing."

echo "Done. Backend config:"
echo "  bucket         = \"${BUCKET}\""
echo "  dynamodb_table = \"${TABLE}\""
echo "  region         = \"${REGION}\""
