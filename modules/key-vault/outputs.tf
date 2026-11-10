# Outputs of the key-vault module.
output "name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "secret_name" {
  description = "Name of the stored admin password secret."
  value       = azurerm_key_vault_secret.admin.name
}

output "admin_password" {
  description = "Generated admin password for the domain controllers. Available only after the secret is safely stored."
  value       = random_password.admin.result
  sensitive   = true
  depends_on  = [azurerm_key_vault_secret.admin]
}
