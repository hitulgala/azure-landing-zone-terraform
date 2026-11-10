# ==============================================================================
# Module  : recovery-vault   (WORKLOAD subscription)
# Purpose : Recovery Services Vault for Azure Backup AND Azure Site Recovery,
#           with an optional daily VM backup policy and diagnostics.
#
# One vault per region. The SECONDARY-region vault doubles as the ASR target vault
# for primary-region VMs. storage_mode_type cannot change once items are protected;
# cross_region_restore_enabled requires GeoRedundant.
# ==============================================================================
resource "azurerm_recovery_services_vault" "this" {
  name                         = var.vault.name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  sku                          = "Standard"
  storage_mode_type            = var.vault.storage_mode_type
  cross_region_restore_enabled = var.vault.cross_region_restore_enabled
  immutability                 = var.vault.immutability
  tags                         = var.tags
}

resource "azurerm_backup_policy_vm" "daily" {
  count = var.vm_backup_policy == null ? 0 : 1

  name                           = var.vm_backup_policy.name
  resource_group_name            = var.resource_group_name
  recovery_vault_name            = azurerm_recovery_services_vault.this.name
  timezone                       = var.vm_backup_policy.timezone
  instant_restore_retention_days = var.vm_backup_policy.instant_restore_retention_days

  backup {
    frequency = "Daily"
    time      = var.vm_backup_policy.time
  }

  retention_daily {
    count = var.vm_backup_policy.daily_retention_days
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                           = var.vault.diagnostic_setting_name
  target_resource_id             = azurerm_recovery_services_vault.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
