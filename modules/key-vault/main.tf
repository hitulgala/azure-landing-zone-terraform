# ==============================================================================
# Module  : key-vault   (IDENTITY subscription)
# Purpose : The vault that holds the domain-controller local admin password:
#             - Key Vault (RBAC mode, purge protection, firewall default DENY)
#             - Private endpoint (+ DNS zone group in the hub's Private DNS zone)
#             - Role assignment so the Terraform identity can write the secret
#             - Generated password stored as a secret
#             - Diagnostics to Log Analytics
#
# Network access
#   public_network_access_enabled = true  : vault reachable ONLY from allowed_ip_ranges
#                                           (needed while Terraform runs outside the VNet)
#   public_network_access_enabled = false : private endpoint only
# ==============================================================================
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.key_vault.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault.sku_name

  rbac_authorization_enabled    = true # azurerm 4.x name
  purge_protection_enabled      = var.key_vault.purge_protection_enabled
  soft_delete_retention_days    = var.key_vault.soft_delete_retention_days
  public_network_access_enabled = var.key_vault.public_network_access_enabled

  /*
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.key_vault.allowed_ip_ranges # plain IPs or CIDRs (no /31, /32)
  }
*/ # This can be uncommented once we have Azure DevOps self hosted agent or GitHub Runners inside Azure
  tags = var.tags
}

resource "azurerm_private_endpoint" "this" {
  name                = var.private_endpoint.name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = var.private_endpoint.connection_name
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  # The Private DNS zone lives in the HUB subscription. The deploying identity needs "Private DNS Zone Contributor" on it.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

# The vault uses RBAC, so the identity running Terraform needs a data-plane role to write the secret. This is the only role assignment in this repository.
resource "azurerm_role_assignment" "deployer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# New role assignments can take a minute to become effective.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.deployer]
  create_duration = var.key_vault.role_propagation_wait
}

resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?" # avoids characters that trip shells / RDP clients
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_key_vault_secret" "admin" {
  name         = var.key_vault.secret_name
  value        = random_password.admin.result
  key_vault_id = azurerm_key_vault.this.id
  content_type = "Domain controller local administrator password"
  tags         = var.tags

  depends_on = [time_sleep.rbac_propagation, azurerm_private_endpoint.this]
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = var.key_vault.diagnostic_setting_name
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs" # includes AuditEvent
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
