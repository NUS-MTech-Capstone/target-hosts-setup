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

