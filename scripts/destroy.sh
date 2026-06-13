#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AWS_REGION=${AWS_REGION:-ap-southeast-1}
HOST_ID=${HOST_ID:-host-dev-1}
SECRET_NAME="dendenmushi/targets/${HOST_ID}/ssh-private-key"
TEMP_DIR=$(mktemp -d)
PRIVATE_KEY="${TEMP_DIR}/id_ed25519"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

for command in aws terraform ssh-keygen; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
done

aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${SECRET_NAME}" \
  --query SecretString \
  --output text >"${PRIVATE_KEY}"
chmod 600 "${PRIVATE_KEY}"

export TF_VAR_aws_region="${AWS_REGION}"
export TF_VAR_host_id="${HOST_ID}"
export TF_VAR_target_public_key
TF_VAR_target_public_key=$(ssh-keygen -y -f "${PRIVATE_KEY}")

terraform -chdir="${ROOT_DIR}" init -reconfigure
terraform -chdir="${ROOT_DIR}" destroy "$@"
