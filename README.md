# Target Hosts Setup

Terraform for private SSH targets used by DenDenMushi.

This repository owns the Phase 1 test target and the host-side hooks used by
Phase 2 incident automation. It creates the SSH target, stores the SSH private
key in Secrets Manager, installs the bounded `ddm-ops` helper and demo incident
service, and publishes CloudWatch alarm notifications for the Incident Agent.

The private key is never passed to Terraform. `scripts/bootstrap.sh` creates it
in a temporary directory, installs only the public key through EC2 key-pair
metadata, uploads the raw OpenSSH private key to Secrets Manager, and deletes
the temporary files. Re-running the script reuses the existing secret.

Terraform apply is retried up to three times to recover from transient AWS API
or DNS failures. Override `APPLY_MAX_ATTEMPTS` or
`APPLY_RETRY_DELAY_SECONDS` when needed. Errors reading Secrets Manager are
fatal unless AWS explicitly reports that the secret does not exist, preventing
an accidental key replacement during an outage.

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
automation service=ddm-demo-app
automation health URL=http://127.0.0.1:18080/healthz
```

The instance is created in a private subnet with no public IP. Port 22 accepts
traffic only from the EKS worker-node security group. Use AWS Systems Manager
for administrative access.

The instance also installs:

- `ddm-demo-app.service`, a loopback-only HTTP service for incident demos.
- `ddm-demo-health-probe.timer`, which records bounded health status metadata.
- `/usr/local/sbin/ddm-ops`, a root-owned operation helper used by the incident
  workflow.

Configure the managed systemd service and loopback health endpoint only when
overriding the default demo app:

```bash
./scripts/bootstrap.sh -auto-approve \
  -var='automation_service_name=myapp' \
  -var='automation_health_url=http://127.0.0.1:8080/healthz'
```

By default, the target-host stack reads the central Incident Agent SNS topic
from the main `aws-terraform` remote state. Override
`incident_alerts_topic_arn` only when testing against a different incident
topic.

The SSH account has passwordless sudo access only to this helper. The helper
rejects operations outside the fixed diagnostic catalog and code-reviewed v1
remediation catalog.

Changing user data replaces the EC2 target. After applying changes that replace
the instance, refresh the Kubernetes dev static inventory so STS has the current
private address and SSH host key.

The launch AMI is resolved from the Amazon Linux 2023 `latest` SSM parameter
only when Terraform creates the host. Later AMI publication does not replace a
working demo target during an ordinary plan. Upgrade the AMI through an
explicit, reviewed host replacement and then refresh the Kubernetes inventory.

## Observability

Terraform creates CloudWatch Logs groups, CloudWatch alarms, an SNS topic, and
an SQS queue for alarm delivery. The EC2 instance installs the CloudWatch Agent
at boot and ships:

- `/var/log/messages` and `/var/log/cloud-init-output.log` to the system log
  group.
- `/var/log/ddm-bootstrap.log`, `/var/log/ddm-ops.log`, and
  `/var/log/ddm-demo-health.log` to the ops log group.
- CPU, memory, disk, and swap metrics to the `DendenMushi/TargetHost`
  namespace.

The logs contain system and operation metadata only. Do not use this target
setup to collect terminal streams or command contents.

Default observability settings:

```text
CloudWatch log retention=14 days
CPU alarm threshold=80 percent
CPU alarm period=60 seconds
CPU alarm evaluation periods=2
Demo app unhealthy alarm period=60 seconds
SQS alarm event retention=345600 seconds
DLQ enabled=true
```

Tune these with Terraform variables when applying:

```bash
./scripts/bootstrap.sh -auto-approve \
  -var='cloudwatch_log_retention_days=7' \
  -var='cpu_alarm_threshold_percent=75' \
  -var='cpu_alarm_evaluation_periods=2' \
  -var='cpu_alarm_datapoints_to_alarm=2'
```

Alarm state changes are published to the target-host SNS topic and delivered to
the target-host SQS queue. When the main platform remote state exposes the
central Incident Agent SNS topic, the same ALARM/OK transitions are also
published there. The `incident_alerts_topic_arn` output shows the resolved
central topic ARN, if one is configured.

Alarm descriptions are JSON metadata consumed by the Incident Agent:

```json
{"source":"managed-server","hostId":"host-dev-1","runbookVersion":"v1","signal":"high_cpu"}
```

The local `alarm_sqs_queue_url`, `alarm_sqs_queue_arn`, and
`alarm_sns_topic_arn` outputs remain available for standalone validation.

## Demo App Incident

The default target host runs `ddm-demo-app` on `127.0.0.1:18080`. Its health
endpoint returns `ok` while healthy and `unhealthy` after a demo failure is
injected. Restarting the systemd service clears the in-memory failure state.

Trigger the incident through SSM or an approved SSH session:

```bash
curl -fsS -XPOST http://127.0.0.1:18080/admin/fail
```

The health probe writes an unhealthy record to `/var/log/ddm-demo-health.log`.
CloudWatch Logs converts that record into the `demo-app-unhealthy` metric alarm,
which publishes managed-server metadata to the target-host SNS topic and to the
central Incident Agent topic when `incident_alerts_topic_arn` is configured.

During triage, Incident Agent gathers bounded diagnostics through the existing
operation IDs. `ddm-ops health_check` prints the response body and returns
nonzero for HTTP 503, so the evidence contains `unhealthy` and the fallback
planner can propose an approved v1 remediation operation.

`ddm-ops target_probe` is a read-only readiness check for the automation target.
It prints bounded JSON with helper readiness, host ID, configured service name,
service active state, health URL, HTTP status, curl exit code, and a short
health response body. It exits nonzero when the service is inactive or the
health endpoint is unreachable or unhealthy.

Manual verification commands:

```bash
systemctl is-active ddm-demo-app
curl -fsS http://127.0.0.1:18080/healthz
curl -fsS -XPOST http://127.0.0.1:18080/admin/fail
sudo /usr/local/sbin/ddm-ops target_probe
sudo /usr/local/sbin/ddm-ops health_check
sudo /usr/local/sbin/ddm-ops recover_demo_app
sudo /usr/local/sbin/ddm-ops reload_service
sudo /usr/local/sbin/ddm-ops restart_service
sudo /usr/local/sbin/ddm-ops health_check
```

## CPU Spike Demo

The `ddm-ops` helper includes a bounded CPU spike operation for the alarm demo.
Run it through SSM or an approved SSH session:

```bash
sudo /usr/local/sbin/ddm-ops cpu_spike 300 2
```

Arguments are `duration_seconds` and `worker_count`. The helper rejects values
above `cpu_spike_max_duration_seconds` and `cpu_spike_max_workers`, which
default to 300 seconds and 2 workers. Increase the duration only when the alarm
period and evaluation settings require it.

After the alarm enters `ALARM`, confirm the notification reached the queue:

```bash
aws sqs receive-message \
  --region "${AWS_REGION:-ap-southeast-1}" \
  --queue-url "$(terraform output -raw alarm_sqs_queue_url)"
```

## Destroy

Destroying the stack also deletes the Secrets Manager secret immediately:

```bash
./scripts/destroy.sh -auto-approve
```
