# Outputs of the recovery-vault module.
output "id" {
  description = "Vault resource ID."
  value       = azurerm_recovery_services_vault.this.id
}

output "name" {
  description = "Vault name."
  value       = azurerm_recovery_services_vault.this.name
}
