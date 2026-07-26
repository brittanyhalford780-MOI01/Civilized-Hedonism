# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — OpenTofu Variables
# ──────────────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS AMI ID (region-specific)"
  type        = string
  default     = "ami-0b6d9d3d33ba97d99" # Ubuntu 24.04 LTS us-east-1
}

variable "key_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH into the instance. Restrict in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

