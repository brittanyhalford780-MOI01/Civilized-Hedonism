# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — OpenTofu / Terraform Infrastructure as Code
#
# This provisions the complete AWS infrastructure:
#   - VPC Security Group (SSH + HTTP + HTTPS only)
#   - EC2 Instance (Ubuntu 24.04 LTS)
#   - Elastic IP (static public IP for DNS A-record)
#
# Usage:
#   1. Copy terraform.tfvars.example → terraform.tfvars and fill in real values
#   2. tofu init
#   3. tofu plan    (review what will be created)
#   4. tofu apply   (provision infrastructure)
#
# Credentials:
#   OpenTofu reads AWS credentials from environment variables or ~/.aws/credentials.
#   NEVER put credentials in this file.
#   Export them before running:
#     export AWS_ACCESS_KEY_ID="AKIAxxxxxxxxxx"
#     export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxx"
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# ─── Provider ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region
}

# ─── SSH Key Pair ─────────────────────────────────────────────────────────────

resource "tls_private_key" "vault_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vault_key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.vault_key.public_key_openssh

  tags = {
    Name    = var.key_name
    Project = "MOI01"
  }
}

resource "local_sensitive_file" "private_key_pem" {
  content         = tls_private_key.vault_key.private_key_pem
  filename        = "${path.module}/../credentials/${var.key_name}.pem"
  file_permission = "0400"
}

# ─── Security Group ──────────────────────────────────────────────────────────

resource "aws_security_group" "vault_sg" {
  name        = "moi01-vault-sg"
  description = "MOI01 Vault - SSH, HTTP, HTTPS only"

  # SSH — Restrict to known IPs in production
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # HTTP — Required for Let's Encrypt ACME challenge and redirect
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — Production traffic
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound (required for package installs, Let's Encrypt, webhook relay)
  egress {
    description = "All Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "moi01-vault-sg"
    Project = "MOI01"
  }
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "vault_node" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.vault_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.vault_sg.id]

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name    = "moi01-vault"
    Project = "MOI01"
  }
}

# ─── Elastic IP ───────────────────────────────────────────────────────────────

resource "aws_eip" "vault_ip" {
  instance = aws_instance.vault_node.id
  domain   = "vpc"

  tags = {
    Name    = "moi01-vault-eip"
    Project = "MOI01"
  }
}
