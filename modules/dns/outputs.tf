# Outputs of the dns module.
output "resolver_inbound_ip" {
  description = "Resolver inbound endpoint IP."
  value       = azurerm_private_dns_resolver_inbound_endpoint.this.ip_configurations[0].private_ip_address
}

output "private_dns_zone_ids" {
  description = "Map of zone name => zone ID (only the region that creates the zones)."
  value       = { for name, z in azurerm_private_dns_zone.this : name => z.id }
}
