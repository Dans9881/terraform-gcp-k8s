#!/bin/bash
set -euo pipefail

echo "=== TERRAFORM INIT ==="

ENV=${1:-dev}

if [[ "$ENV" != "dev" && "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  echo "Usage: ./init.sh [dev|staging|prod]"
  exit 1
fi

if [ ! -d "environments/$ENV" ]; then
  echo "Environment folder not found: $ENV"
  exit 1
fi

if ! command -v terraform &> /dev/null; then
  echo "Terraform is not installed"
  exit 1
fi

echo "Environment: $ENV"

cd environments/$ENV

if [ ! -f terraform.tfvars ]; then
  echo "Creating terraform.tfvars..."
  cp terraform.tfvars.example terraform.tfvars
else
  echo "terraform.tfvars exists"
fi

if [ -z "${TF_BUCKET:-}" ]; then
  echo "WARNING: TF_BUCKET not set, using default: danz-tf-state"
fi

BUCKET=${TF_BUCKET:-danz-tf-state}

echo "Using backend bucket: $BUCKET"

terraform init -reconfigure \
  -backend-config="bucket=$BUCKET" \
  -backend-config="prefix=k8s/$ENV"

echo ""
echo "=== FORMAT ==="
terraform fmt -recursive

echo ""
echo "=== VALIDATE ==="
terraform validate

echo ""
echo "=== READY ==="
echo "Next steps:"
echo "cd environments/$ENV"
echo "terraform plan"
echo "terraform apply"