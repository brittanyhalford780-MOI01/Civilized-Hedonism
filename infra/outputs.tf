# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — OpenTofu Outputs
# ──────────────────────────────────────────────────────────────────────────────

output "elastic_ip" {
  description = "The public Elastic IP assigned to the Vault instance. Use this for your DNS A-Record."
  value       = aws_eip.vault_ip.public_ip
}

output "instance_id" {
  description = "The EC2 instance ID"
  value       = aws_instance.vault_node.id
}

output "security_group_id" {
  description = "The Security Group ID"
  value       = aws_security_group.vault_sg.id
}
