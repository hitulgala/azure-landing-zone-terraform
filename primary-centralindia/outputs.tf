# Stack: primary-centralindia  |  Outputs
output "hub_network_resource_group_name" {
  description = "Hub network RG (holds the Private DNS zones). Copy into the secondary tfvars."
  value       = module.hub_network.resource_group_name
}

output "hub_vnet_name" {
  description = "Hub VNet name. Copy into the secondary tfvars (primary_hub)."
  value       = module.hub_network.vnet_name
}

output "firewall_private_ip" {
  description = "Verify it equals the primary firewall IP referenced in the SECONDARY tfvars."
  value       = module.hub_firewall.private_ip_address
}

output "domain_controller_ips" {
  description = "Domain controller private IPs."
  value       = module.domain_controllers.private_ips
}

output "key_vault_name" {
  description = "Key Vault holding the DC admin password."
  value       = module.key_vault.name
}

output "key_vault_secret_name" {
  description = "Secret name of the DC admin password."
  value       = module.key_vault.secret_name
}

output "log_analytics_workspace_name" {
  description = "Regional Log Analytics workspace."
  value       = module.governance.log_analytics_workspace_name
}
