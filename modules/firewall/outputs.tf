# Outputs of the firewall module.
output "id" {
  description = "Firewall resource ID."
  value       = azurerm_firewall.this.id
}

output "private_ip_address" {
  description = "Firewall private IP (compare with the value used in tfvars route tables)."
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "public_ip_address" {
  description = "Firewall public IP."
  value       = azurerm_public_ip.this.ip_address
}
