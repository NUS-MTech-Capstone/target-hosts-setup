#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AWS_REGION=${AWS_REGION:-ap-southeast-1}
HOST_ID=${HOST_ID:-host-dev-1}
SECRET_NAME="dendenmushi/targets/${HOST_ID}/ssh-private-key"
TEMP_DIR=$(mktemp -d)
PRIVATE_KEY="${TEMP_DIR}/id_ed25519"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
NEW_KEY=false

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

aws sts get-caller-identity >/dev/null

if aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${SECRET_NAME}" \
  --query SecretString \
  --output text >"${PRIVATE_KEY}" 2>/dev/null; then
  chmod 600 "${PRIVATE_KEY}"
  ssh-keygen -y -f "${PRIVATE_KEY}" >"${PUBLIC_KEY}"
  echo "Reusing the existing SSH key from Secrets Manager."
else
  rm -f "${PRIVATE_KEY}"
  ssh-keygen -q -t ed25519 -N "" -C "dendenmushi-${HOST_ID}" -f "${PRIVATE_KEY}"
  NEW_KEY=true
  echo "Generated a new SSH key in temporary storage."
fi

export TF_VAR_aws_region="${AWS_REGION}"
export TF_VAR_host_id="${HOST_ID}"
export TF_VAR_target_public_key
TF_VAR_target_public_key=$(cat "${PUBLIC_KEY}")

terraform -chdir="${ROOT_DIR}" init -reconfigure

if [[ "${NEW_KEY}" == "true" ]]; then
  terraform -chdir="${ROOT_DIR}" apply \
    -target=aws_secretsmanager_secret.ssh_private_key \
    "$@"
  SECRET_ID=$(terraform -chdir="${ROOT_DIR}" output -raw credential_secret_id)
  aws secretsmanager put-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${SECRET_ID}" \
    --secret-string "file://${PRIVATE_KEY}" >/dev/null
  echo "Uploaded the private key to Secrets Manager."
fi

terraform -chdir="${ROOT_DIR}" apply "$@"
terraform -chdir="${ROOT_DIR}" output
