variable "resource_group_name" {
  description = "Workload resource group (created by the network module)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}

variable "log_analytics_workspace_id" {
  description = "Workspace for vault diagnostics."
  type        = string
}

variable "vault" {
  description = "Recovery Services Vault settings."
  type = object({
    name                         = string
    storage_mode_type            = string # GeoRedundant | LocallyRedundant | ZoneRedundant
    cross_region_restore_enabled = bool
    immutability                 = string # Disabled | Unlocked | Locked
    diagnostic_setting_name      = string
  })

  validation {
    condition     = !var.vault.cross_region_restore_enabled || var.vault.storage_mode_type == "GeoRedundant"
    error_message = "cross_region_restore_enabled requires storage_mode_type = GeoRedundant."
  }
}

variable "vm_backup_policy" {
  description = "Daily Azure VM backup policy; null = do not create one."
  type = object({
    name                           = string
    timezone                       = string # Windows time zone name
    time                           = string # HH:MM, 24h, on the quarter hour
    daily_retention_days           = number
    instant_restore_retention_days = number # 1-5
  })
  default = null
}
