output "host_id" {
  value = var.host_id
}

output "private_address" {
  value = aws_instance.target.private_ip
}

output "ssh_username" {
  value = "ec2-user"
}

output "connection_type" {
  value = "ssh"
}

output "credential_secret_id" {
  value = aws_secretsmanager_secret.ssh_private_key.arn
}

output "credential_secret_name" {
  value = aws_secretsmanager_secret.ssh_private_key.name
}

output "instance_id" {
  value = aws_instance.target.id
}

output "automation_service_name" {
  value = var.automation_service_name
}

output "automation_health_url" {
  value = var.automation_health_url
}

output "automation_helper_path" {
  value = "/usr/local/sbin/ddm-ops"
}

output "system_log_group_name" {
  value = aws_cloudwatch_log_group.system.name
}

output "ops_log_group_name" {
  value = aws_cloudwatch_log_group.ops.name
}

output "cloudwatch_metrics_namespace" {
  value = local.metrics_namespace
}

output "alarm_sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "incident_alerts_topic_arn" {
  value = local.incident_alerts_topic_arn
}

output "alarm_sqs_queue_arn" {
  value = aws_sqs_queue.alarm_events.arn
}

output "alarm_sqs_queue_url" {
  value = aws_sqs_queue.alarm_events.url
}

output "alarm_dlq_arn" {
  value = try(aws_sqs_queue.alarm_dlq[0].arn, null)
}

output "alarm_dlq_url" {
  value = try(aws_sqs_queue.alarm_dlq[0].url, null)
}

output "high_cpu_alarm_name" {
  value = try(aws_cloudwatch_metric_alarm.high_cpu[0].alarm_name, null)
}

output "high_cpu_alarm_arn" {
  value = try(aws_cloudwatch_metric_alarm.high_cpu[0].arn, null)
}

output "status_check_failed_alarm_name" {
  value = try(aws_cloudwatch_metric_alarm.status_check_failed[0].alarm_name, null)
}

output "status_check_failed_alarm_arn" {
  value = try(aws_cloudwatch_metric_alarm.status_check_failed[0].arn, null)
}

output "demo_app_unhealthy_alarm_name" {
  value = try(aws_cloudwatch_metric_alarm.demo_app_unhealthy[0].alarm_name, null)
}

output "demo_app_unhealthy_alarm_arn" {
  value = try(aws_cloudwatch_metric_alarm.demo_app_unhealthy[0].arn, null)
}

output "demo_app_fail_command" {
  value = "curl -fsS -XPOST http://127.0.0.1:18080/admin/fail"
}

output "demo_app_recover_command" {
  value = "curl -fsS -XPOST http://127.0.0.1:18080/admin/recover"
}

output "cpu_spike_demo_command" {
  value = "sudo /usr/local/sbin/ddm-ops cpu_spike ${var.cpu_spike_max_duration_seconds} ${var.cpu_spike_max_workers}"
}
