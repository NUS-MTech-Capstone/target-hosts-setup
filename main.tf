data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = "ddm-capstone-tfstate"
    key    = "ddm/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name                      = "dendenmushi-target-${var.host_id}-${var.environment}"
  secret_name               = "dendenmushi/targets/${var.host_id}/ssh-private-key"
  system_log_group_name     = "/dendenmushi/targets/${var.environment}/${var.host_id}/system"
  ops_log_group_name        = "/dendenmushi/targets/${var.environment}/${var.host_id}/ops"
  metrics_namespace         = "DendenMushi/TargetHost"
  demo_app_metric_name      = "${local.name}-demo-app-unhealthy"
  incident_alerts_topic_arn = trimspace(var.incident_alerts_topic_arn) != "" ? trimspace(var.incident_alerts_topic_arn) : try(data.terraform_remote_state.platform.outputs.incident_alerts_topic_arn, "")
  alarm_action_arns         = distinct(compact([aws_sns_topic.alarms.arn, local.incident_alerts_topic_arn]))
  alarm_description_base = {
    source         = "managed-server"
    hostId         = var.host_id
    runbookVersion = "v1"
  }

  tags = {
    Environment = var.environment
    HostId      = var.host_id
    Project     = "dendenmushi"
  }
}

resource "aws_secretsmanager_secret" "ssh_private_key" {
  name                    = local.secret_name
  description             = "SSH private key used by DenDenMushi to connect to ${var.host_id}"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_key_pair" "target" {
  key_name   = local.name
  public_key = trimspace(var.target_public_key)

  tags = local.tags
}

resource "aws_security_group" "target" {
  name        = local.name
  description = "SSH target access from DenDenMushi EKS nodes"
  vpc_id      = data.terraform_remote_state.platform.outputs.vpc_id

  ingress {
    description     = "SSH from EKS worker nodes"
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [data.terraform_remote_state.platform.outputs.eks_node_security_group_id]
  }

  egress {
    description = "Allow target outbound access through the private subnet NAT gateway"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = local.name
    Environment = var.environment
    HostId      = var.host_id
    Project     = "dendenmushi"
  }
}

resource "aws_iam_role" "target" {
  name = local.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.target.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "cloudwatch_agent" {
  name = "${local.name}-cloudwatch-agent"
  role = aws_iam_role.target.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteTargetLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.system.arn}:*",
          "${aws_cloudwatch_log_group.ops.arn}:*"
        ]
      },
      {
        Sid      = "PublishTargetMetrics"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = local.metrics_namespace
          }
        }
      },
      {
        Sid      = "ReadInstanceTagsForMetrics"
        Effect   = "Allow"
        Action   = "ec2:DescribeTags"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "target" {
  name = local.name
  role = aws_iam_role.target.name
}

resource "aws_cloudwatch_log_group" "system" {
  name              = local.system_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "ops" {
  name              = local.ops_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.tags
}

resource "aws_sqs_queue" "alarm_dlq" {
  count = var.alarm_queue_dlq_enabled ? 1 : 0

  name                      = "${local.name}-alarm-dlq"
  message_retention_seconds = var.alarm_queue_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = local.tags
}

resource "aws_sqs_queue" "alarm_events" {
  name                      = "${local.name}-alarm-events"
  message_retention_seconds = var.alarm_queue_retention_seconds
  sqs_managed_sse_enabled   = true

  redrive_policy = var.alarm_queue_dlq_enabled ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.alarm_dlq[0].arn
    maxReceiveCount     = var.alarm_queue_max_receive_count
  }) : null

  tags = local.tags
}

resource "aws_sns_topic" "alarms" {
  name = "${local.name}-alarms"

  tags = local.tags
}

resource "aws_sns_topic_subscription" "alarm_events" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.alarm_events.arn
}

resource "aws_sqs_queue_policy" "alarm_events" {
  queue_url = aws_sqs_queue.alarm_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudWatchAlarmTopic"
      Effect = "Allow"
      Principal = {
        Service = "sns.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.alarm_events.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sns_topic.alarms.arn
        }
      }
    }]
  })
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = var.observability_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name}-high-cpu"
  alarm_description   = jsonencode(merge(local.alarm_description_base, { signal = "high_cpu" }))
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cpu_alarm_evaluation_periods
  datapoints_to_alarm = var.cpu_alarm_datapoints_to_alarm
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.cpu_alarm_period_seconds
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_action_arns
  ok_actions          = local.alarm_action_arns

  dimensions = {
    InstanceId = aws_instance.target.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  count = var.observability_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name}-status-check-failed"
  alarm_description   = jsonencode(merge(local.alarm_description_base, { signal = "status_check_failed" }))
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_action_arns
  ok_actions          = local.alarm_action_arns

  dimensions = {
    InstanceId = aws_instance.target.id
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_metric_filter" "demo_app_unhealthy" {
  count = var.observability_alarms_enabled ? 1 : 0

  name           = local.demo_app_metric_name
  log_group_name = aws_cloudwatch_log_group.ops.name
  pattern        = "{ $.service = \"ddm-demo-app\" && $.status = \"unhealthy\" }"

  metric_transformation {
    name          = local.demo_app_metric_name
    namespace     = local.metrics_namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "demo_app_unhealthy" {
  count = var.observability_alarms_enabled ? 1 : 0

  alarm_name          = local.demo_app_metric_name
  alarm_description   = jsonencode(merge(local.alarm_description_base, { signal = "demo_app_unhealthy" }))
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  metric_name         = local.demo_app_metric_name
  namespace           = local.metrics_namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_action_arns
  ok_actions          = local.alarm_action_arns

  tags = local.tags

  depends_on = [aws_cloudwatch_log_metric_filter.demo_app_unhealthy]
}

resource "aws_instance" "target" {
  ami                         = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type               = var.instance_type
  subnet_id                   = data.terraform_remote_state.platform.outputs.private_subnet_ids[0]
  associate_public_ip_address = false
  key_name                    = aws_key_pair.target.key_name
  vpc_security_group_ids      = [aws_security_group.target.id]
  iam_instance_profile        = aws_iam_instance_profile.target.name
  user_data = templatefile("${path.module}/templates/install-ddm-ops.sh.tftpl", {
    service_name_b64               = base64encode(var.automation_service_name)
    health_url_b64                 = base64encode(var.automation_health_url)
    environment_b64                = base64encode(var.environment)
    host_id_b64                    = base64encode(var.host_id)
    aws_region_b64                 = base64encode(var.aws_region)
    system_log_group_name_b64      = base64encode(aws_cloudwatch_log_group.system.name)
    ops_log_group_name_b64         = base64encode(aws_cloudwatch_log_group.ops.name)
    cloudwatch_metrics_namespace   = local.metrics_namespace
    cpu_spike_max_duration_seconds = var.cpu_spike_max_duration_seconds
    cpu_spike_max_workers          = var.cpu_spike_max_workers
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name        = local.name
    Environment = var.environment
    HostId      = var.host_id
    Project     = "dendenmushi"
  }
}
