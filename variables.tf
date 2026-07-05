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

variable "cloudwatch_log_retention_days" {
  description = "Retention period in days for target host CloudWatch log groups."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a retention value supported by CloudWatch Logs."
  }
}

variable "observability_alarms_enabled" {
  description = "Whether to create CloudWatch alarms for target host health signals."
  type        = bool
  default     = true
}

variable "incident_alerts_topic_arn" {
  description = "Optional central DenDenMushi Incident Agent SNS topic ARN for managed-server alarm notifications."
  type        = string
  default     = ""

  validation {
    condition     = var.incident_alerts_topic_arn == "" || can(regex("^arn:aws[a-zA-Z-]*:sns:", var.incident_alerts_topic_arn))
    error_message = "incident_alerts_topic_arn must be empty or an SNS topic ARN."
  }
}

variable "cpu_alarm_threshold_percent" {
  description = "CPU utilization percentage that triggers the target host high CPU alarm."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold_percent > 0 && var.cpu_alarm_threshold_percent <= 100
    error_message = "cpu_alarm_threshold_percent must be greater than 0 and less than or equal to 100."
  }
}

variable "cpu_alarm_period_seconds" {
  description = "CloudWatch high CPU alarm period in seconds."
  type        = number
  default     = 60

  validation {
    condition     = contains([10, 30, 60, 120, 300, 600, 900], var.cpu_alarm_period_seconds)
    error_message = "cpu_alarm_period_seconds must be a valid CloudWatch alarm period."
  }
}

variable "cpu_alarm_evaluation_periods" {
  description = "Number of periods evaluated by the high CPU alarm."
  type        = number
  default     = 2

  validation {
    condition     = var.cpu_alarm_evaluation_periods >= 1 && var.cpu_alarm_evaluation_periods <= 10
    error_message = "cpu_alarm_evaluation_periods must be between 1 and 10."
  }
}

variable "cpu_alarm_datapoints_to_alarm" {
  description = "Number of breaching datapoints required to trigger the high CPU alarm."
  type        = number
  default     = 2

  validation {
    condition     = var.cpu_alarm_datapoints_to_alarm >= 1 && var.cpu_alarm_datapoints_to_alarm <= var.cpu_alarm_evaluation_periods
    error_message = "cpu_alarm_datapoints_to_alarm must be at least 1 and no greater than cpu_alarm_evaluation_periods."
  }
}

variable "alarm_queue_retention_seconds" {
  description = "Retention period in seconds for SQS alarm event messages."
  type        = number
  default     = 345600

  validation {
    condition     = var.alarm_queue_retention_seconds >= 60 && var.alarm_queue_retention_seconds <= 1209600
    error_message = "alarm_queue_retention_seconds must be between 60 seconds and 14 days."
  }
}

variable "alarm_queue_dlq_enabled" {
  description = "Whether to create a dead-letter queue for alarm event delivery failures."
  type        = bool
  default     = true
}

variable "alarm_queue_max_receive_count" {
  description = "Receive attempts before an alarm event is moved to the dead-letter queue."
  type        = number
  default     = 5

  validation {
    condition     = var.alarm_queue_max_receive_count >= 1 && var.alarm_queue_max_receive_count <= 100
    error_message = "alarm_queue_max_receive_count must be between 1 and 100."
  }
}

variable "cpu_spike_max_duration_seconds" {
  description = "Maximum duration accepted by the ddm-ops cpu_spike demo operation."
  type        = number
  default     = 300

  validation {
    condition     = var.cpu_spike_max_duration_seconds >= 10 && var.cpu_spike_max_duration_seconds <= 900
    error_message = "cpu_spike_max_duration_seconds must be between 10 and 900 seconds."
  }
}

variable "cpu_spike_max_workers" {
  description = "Maximum worker count accepted by the ddm-ops cpu_spike demo operation."
  type        = number
  default     = 2

  validation {
    condition     = var.cpu_spike_max_workers >= 1 && var.cpu_spike_max_workers <= 8
    error_message = "cpu_spike_max_workers must be between 1 and 8."
  }
}
