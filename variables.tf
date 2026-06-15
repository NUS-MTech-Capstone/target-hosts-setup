variable "aws_region" {
  description = "AWS region containing the DenDenMushi VPC and target host."
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "host_id" {
  description = "Stable host identifier used by STS inventory."
  type        = string
  default     = "host-dev-1"
}

variable "instance_type" {
  description = "EC2 instance type for the SSH target."
  type        = string
  default     = "t3.micro"
}

variable "target_public_key" {
  description = "OpenSSH public key installed for ec2-user. The matching private key is uploaded outside Terraform."
  type        = string

  validation {
    condition     = startswith(trimspace(var.target_public_key), "ssh-")
    error_message = "target_public_key must be an OpenSSH public key."
  }
}

variable "automation_service_name" {
  description = "Systemd service managed by the incident automation helper."
  type        = string
  default     = "nginx"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.@-]+$", var.automation_service_name))
    error_message = "automation_service_name must be a systemd unit name without shell metacharacters."
  }
}

variable "automation_health_url" {
  description = "Loopback HTTP endpoint used to verify the managed service."
  type        = string
  default     = "http://127.0.0.1/"

  validation {
    condition     = can(regex("^https?://(127\\.0\\.0\\.1|localhost)(:[0-9]+)?(/.*)?$", var.automation_health_url))
    error_message = "automation_health_url must be an HTTP(S) loopback URL."
  }
}
