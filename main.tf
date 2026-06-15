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
  name        = "dendenmushi-target-${var.host_id}-${var.environment}"
  secret_name = "dendenmushi/targets/${var.host_id}/ssh-private-key"
}

resource "aws_secretsmanager_secret" "ssh_private_key" {
  name                    = local.secret_name
  description             = "SSH private key used by DenDenMushi to connect to ${var.host_id}"
  recovery_window_in_days = 0

  tags = {
    Environment = var.environment
    HostId      = var.host_id
    Project     = "dendenmushi"
  }
}

resource "aws_key_pair" "target" {
  key_name   = local.name
  public_key = trimspace(var.target_public_key)

  tags = {
    Environment = var.environment
    HostId      = var.host_id
    Project     = "dendenmushi"
  }
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

  tags = {
    Environment = var.environment
    HostId      = var.host_id
    Project     = "dendenmushi"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.target.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "target" {
  name = local.name
  role = aws_iam_role.target.name
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
    service_name_b64 = base64encode(var.automation_service_name)
    health_url_b64   = base64encode(var.automation_health_url)
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
