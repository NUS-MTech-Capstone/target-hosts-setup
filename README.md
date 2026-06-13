# Target Hosts Setup

Terraform for private SSH targets used by DenDenMushi.

The private key is never passed to Terraform. `scripts/bootstrap.sh` creates it
in a temporary directory, installs only the public key through EC2 key-pair
metadata, uploads the raw OpenSSH private key to Secrets Manager, and deletes
the temporary files. Re-running the script reuses the existing secret.

## Prerequisites

- The main `aws-terraform` stack has been applied.
- AWS CLI credentials can access EC2, IAM, SSM, Secrets Manager, and the remote
  Terraform state.
- `aws`, `terraform`, and `ssh-keygen` are installed.

## Apply

```bash
aws sts get-caller-identity
./scripts/bootstrap.sh -auto-approve
```

Defaults:

```text
AWS_REGION=ap-southeast-1
HOST_ID=host-dev-1
instance type=t3.micro
SSH user=ec2-user
```

The instance is created in a private subnet with no public IP. Port 22 accepts
traffic only from the EKS worker-node security group. Use AWS Systems Manager
for administrative access.

## Destroy

Destroying the stack also deletes the Secrets Manager secret immediately:

```bash
./scripts/destroy.sh -auto-approve
```
