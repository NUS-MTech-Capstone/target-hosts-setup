#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AWS_REGION=${AWS_REGION:-ap-southeast-1}
HOST_ID=${HOST_ID:-host-dev-1}
APPLY_MAX_ATTEMPTS=${APPLY_MAX_ATTEMPTS:-3}
APPLY_RETRY_DELAY_SECONDS=${APPLY_RETRY_DELAY_SECONDS:-5}
SECRET_NAME="dendenmushi/targets/${HOST_ID}/ssh-private-key"
TEMP_DIR=$(mktemp -d)
PRIVATE_KEY="${TEMP_DIR}/id_ed25519"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
SECRET_ERROR="${TEMP_DIR}/secret-error"
NEW_KEY=false

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

terraform_apply() {
  local attempt=1

  while true; do
    if terraform -chdir="${ROOT_DIR}" apply "$@"; then
      return 0
    fi

    if (( attempt >= APPLY_MAX_ATTEMPTS )); then
      echo "Terraform apply failed after ${attempt} attempts." >&2
      return 1
    fi

    echo "Terraform apply attempt ${attempt} failed; retrying in ${APPLY_RETRY_DELAY_SECONDS}s..." >&2
    sleep "${APPLY_RETRY_DELAY_SECONDS}"
    ((attempt += 1))
  done
}

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
  --output text >"${PRIVATE_KEY}" 2>"${SECRET_ERROR}"; then
  chmod 600 "${PRIVATE_KEY}"
  ssh-keygen -y -f "${PRIVATE_KEY}" >"${PUBLIC_KEY}"
  echo "Reusing the existing SSH key from Secrets Manager."
elif grep -q "ResourceNotFoundException" "${SECRET_ERROR}"; then
  rm -f "${PRIVATE_KEY}"
  ssh-keygen -q -t ed25519 -N "" -C "dendenmushi-${HOST_ID}" -f "${PRIVATE_KEY}"
  NEW_KEY=true
  echo "Generated a new SSH key in temporary storage."
else
  echo "Failed to read ${SECRET_NAME} from Secrets Manager:" >&2
  cat "${SECRET_ERROR}" >&2
  exit 1
fi

export TF_VAR_aws_region="${AWS_REGION}"
export TF_VAR_host_id="${HOST_ID}"
export TF_VAR_target_public_key
TF_VAR_target_public_key=$(cat "${PUBLIC_KEY}")

terraform -chdir="${ROOT_DIR}" init -reconfigure

if [[ "${NEW_KEY}" == "true" ]]; then
  terraform_apply \
    -target=aws_secretsmanager_secret.ssh_private_key \
    "$@"
  SECRET_ID=$(terraform -chdir="${ROOT_DIR}" output -raw credential_secret_id)
  aws secretsmanager put-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${SECRET_ID}" \
    --secret-string "file://${PRIVATE_KEY}" >/dev/null
  echo "Uploaded the private key to Secrets Manager."
fi

terraform_apply "$@"
terraform -chdir="${ROOT_DIR}" output
echo
echo "NOTE: If the target instance changed, refresh:"
echo "  kubernetes/apps/dendenmushi/overlays/dev/server-inventory.static.json"
echo "with the new private_address, SSH host key, credential secret, and automation metadata"
echo "before relying on STS inventory."
